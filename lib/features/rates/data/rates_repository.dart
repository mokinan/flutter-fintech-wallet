import 'package:dio/dio.dart';
import 'package:fintech_wallet/core/database/app_database.dart';
import 'package:fintech_wallet/core/money/currency.dart';
import 'package:fintech_wallet/core/network/api_client.dart';
import 'package:fintech_wallet/core/result/result.dart';
import 'package:fintech_wallet/features/rates/domain/rate_table.dart';

/// Serves FX rates from a local cache, refreshing when older than [ttl].
///
/// When a refresh fails, stale rates are returned (flagged) rather than an
/// error: an approximate total is more useful than no total.
class RatesRepository {
  RatesRepository(this._db, this._dio, {this.ttl = const Duration(hours: 12), DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final AppDatabase _db;
  final Dio _dio;
  final Duration ttl;
  final DateTime Function() _clock;

  Future<Result<RateTable>> rates({bool forceRefresh = false}) async {
    final cached = await _cached();
    if (!forceRefresh && cached != null && _clock().difference(cached.fetchedAt) < ttl) {
      return Ok(cached);
    }
    try {
      final response = await _dio.get<Map<String, dynamic>>('/rates');
      final raw = (response.data!['rates'] as Map<String, dynamic>).cast<String, int>();
      final now = _clock();
      final table = RateTable(
        rateMicros: {
          for (final e in raw.entries)
            if (Currency.values.any((c) => c.code == e.key)) Currency.fromCode(e.key): e.value,
        },
        fetchedAt: now,
      );
      await _db.batch(
        (b) => b.insertAllOnConflictUpdate(_db.exchangeRates, [
          for (final e in table.rateMicros.entries)
            ExchangeRatesCompanion.insert(currency: e.key.code, rateMicros: e.value, fetchedAt: now),
        ]),
      );
      return Ok(table);
    } on DioException catch (e) {
      if (cached != null) {
        return Ok(RateTable(rateMicros: cached.rateMicros, fetchedAt: cached.fetchedAt, isStale: true));
      }
      return Err(failureFromDio(e));
    }
  }

  Future<RateTable?> _cached() async {
    final rows = await _db.select(_db.exchangeRates).get();
    if (rows.isEmpty) return null;
    return RateTable(
      rateMicros: {for (final r in rows) Currency.fromCode(r.currency): r.rateMicros},
      fetchedAt: rows.map((r) => r.fetchedAt).reduce((a, b) => a.isBefore(b) ? a : b),
    );
  }
}
