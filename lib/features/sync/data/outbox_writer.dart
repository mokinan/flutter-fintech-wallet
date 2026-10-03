import 'dart:convert';

import 'package:fintech_wallet/core/database/app_database.dart';
import 'package:uuid/uuid.dart';

/// Operations the sync engine knows how to send.
abstract final class OutboxOperation {
  static const createTransaction = 'create_transaction';
  static const createTransfer = 'create_transfer';
  static const deleteTransaction = 'delete_transaction';
}

/// Queues a server write. Must be called inside the same database
/// transaction as the local change, so the two can never diverge.
class OutboxWriter {
  OutboxWriter(this._db, {Uuid uuid = const Uuid(), DateTime Function()? clock})
    : _uuid = uuid,
      _clock = clock ?? DateTime.now;

  final AppDatabase _db;
  final Uuid _uuid;
  final DateTime Function() _clock;

  Future<void> enqueue({
    required String operation,
    required Map<String, Object?> payload,
    required List<String> recordIds,
  }) async {
    final now = _clock();
    await _db
        .into(_db.outbox)
        .insert(
          OutboxCompanion.insert(
            idempotencyKey: _uuid.v4(),
            operation: operation,
            payload: jsonEncode(payload),
            recordIds: jsonEncode(recordIds),
            nextAttemptAt: now,
            createdAt: now,
          ),
        );
  }
}
