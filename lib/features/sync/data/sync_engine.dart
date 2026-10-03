import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:fintech_wallet/core/database/app_database.dart';
import 'package:fintech_wallet/core/network/connectivity_service.dart';
import 'package:fintech_wallet/features/sync/data/outbox_writer.dart';

/// Result of one [SyncEngine.syncNow] pass.
typedef SyncReport = ({int sent, int failed, bool interrupted});

/// Drains the outbox to the server.
///
/// * Entries are sent **in order** and a transient failure stops the pass, so
///   a delete can never overtake the create it depends on.
/// * Every request carries the entry's idempotency key, so a retry after a
///   lost response cannot create a duplicate (ADR 0003).
/// * Transient failures back off exponentially; a 4xx is permanent and marks
///   the affected records as failed.
class SyncEngine {
  SyncEngine({
    required AppDatabase db,
    required Dio dio,
    required ConnectivityService connectivity,
    DateTime Function()? clock,
    this.retryInterval = const Duration(seconds: 30),
    Random? random,
  }) : _db = db,
       _dio = dio,
       _connectivity = connectivity,
       _clock = clock ?? DateTime.now,
       _random = random ?? Random();

  final AppDatabase _db;
  final Dio _dio;
  final ConnectivityService _connectivity;
  final DateTime Function() _clock;
  final Random _random;
  final Duration retryInterval;

  static const maxBackoff = Duration(minutes: 5);

  Future<SyncReport>? _running;
  StreamSubscription<bool>? _onlineSubscription;
  StreamSubscription<void>? _outboxSubscription;
  Timer? _timer;

  /// Number of writes waiting to reach the server.
  Stream<int> watchPendingCount() {
    final count = _db.outbox.id.count();
    return (_db.selectOnly(_db.outbox)
          ..addColumns([count])
          ..where(_db.outbox.lastError.isNull()))
        .map((r) => r.read(count) ?? 0)
        .watchSingle();
  }

  /// Syncs on reconnect, after every local write, and periodically.
  void start() {
    _onlineSubscription = _connectivity.onlineChanges.where((online) => online).listen((_) => unawaited(syncNow()));
    _outboxSubscription = _db
        .tableUpdates(TableUpdateQuery.onTableName(_db.outbox.actualTableName, limitUpdateKind: UpdateKind.insert))
        .listen((_) => unawaited(syncNow()));
    _timer = Timer.periodic(retryInterval, (_) => unawaited(syncNow()));
    unawaited(syncNow());
  }

  Future<void> stop() async {
    _timer?.cancel();
    await _onlineSubscription?.cancel();
    await _outboxSubscription?.cancel();
    await _running;
  }

  /// Runs one pass; concurrent callers share the in-flight pass.
  Future<SyncReport> syncNow() => _running ??= _drain().whenComplete(() => _running = null);

  Future<SyncReport> _drain() async {
    var sent = 0;
    var failed = 0;
    if (!_connectivity.isOnline) return (sent: 0, failed: 0, interrupted: true);

    while (true) {
      final entry =
          await (_db.select(_db.outbox)
                ..where((o) => o.lastError.isNull())
                ..orderBy([(o) => OrderingTerm.asc(o.id)])
                ..limit(1))
              .getSingleOrNull();
      if (entry == null) return (sent: sent, failed: failed, interrupted: false);
      if (entry.nextAttemptAt.isAfter(_clock())) return (sent: sent, failed: failed, interrupted: true);

      // Record the attempt before sending: from now on the server may have
      // seen this write, even if we never get a response.
      final attempted = entry.copyWith(attempts: entry.attempts + 1);
      await (_db.update(
        _db.outbox,
      )..where((o) => o.id.equals(entry.id))).write(OutboxCompanion(attempts: Value(attempted.attempts)));

      final outcome = await _send(attempted);
      switch (outcome) {
        case _Outcome.delivered:
          sent++;
          await _complete(entry, SyncStatus.synced);
        case _Outcome.rejected:
          failed++;
          await _complete(entry, SyncStatus.failed);
        case _Outcome.retryLater:
          await _scheduleRetry(attempted);
          return (sent: sent, failed: failed, interrupted: true);
      }
    }
  }

  Future<_Outcome> _send(OutboxRow entry) async {
    final payload = jsonDecode(entry.payload) as Map<String, dynamic>;
    final options = Options(headers: {'Idempotency-Key': entry.idempotencyKey});
    try {
      switch (entry.operation) {
        case OutboxOperation.createTransaction:
          await _dio.post<dynamic>('/transactions', data: payload, options: options);
        case OutboxOperation.createTransfer:
          await _dio.post<dynamic>('/transfers', data: payload, options: options);
        case OutboxOperation.deleteTransaction:
          await _dio.delete<dynamic>('/transactions/${payload['id']}', options: options);
        default:
          return _Outcome.rejected;
      }
      return _Outcome.delivered;
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      // 401 means the session could not be refreshed — keep the entry for
      // after the next login rather than discarding the user's data.
      if (status != null && status >= 400 && status < 500 && status != 401 && status != 429) {
        await (_db.update(_db.outbox)..where((o) => o.id.equals(entry.id))).write(
          OutboxCompanion(lastError: Value('HTTP $status ${e.response?.data}')),
        );
        return _Outcome.rejected;
      }
      return _Outcome.retryLater;
    }
  }

  Future<void> _complete(OutboxRow entry, SyncStatus status) => _db.transaction(() async {
    final ids = (jsonDecode(entry.recordIds) as List<dynamic>).cast<String>();
    if (ids.isNotEmpty) {
      await (_db.update(
        _db.transactions,
      )..where((t) => t.id.isIn(ids))).write(TransactionsCompanion(syncStatus: Value(status)));
    }
    if (status == SyncStatus.synced) {
      await (_db.delete(_db.outbox)..where((o) => o.id.equals(entry.id))).go();
    }
  });

  Future<void> _scheduleRetry(OutboxRow entry) => (_db.update(_db.outbox)..where((o) => o.id.equals(entry.id))).write(
    OutboxCompanion(nextAttemptAt: Value(_clock().add(backoff(entry.attempts)))),
  );

  /// Exponential backoff with jitter: ~2s, 4s, 8s … capped at [maxBackoff].
  Duration backoff(int attempts) {
    final base = Duration(seconds: pow(2, min(attempts, 16)).toInt());
    final capped = base > maxBackoff ? maxBackoff : base;
    final jitter = Duration(milliseconds: _random.nextInt(1000));
    return capped + jitter;
  }
}

enum _Outcome { delivered, rejected, retryLater }
