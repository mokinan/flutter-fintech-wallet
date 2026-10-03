import 'package:fintech_wallet/core/database/app_database.dart';
import 'package:fintech_wallet/core/money/currency.dart';
import 'package:fintech_wallet/core/money/money.dart';
import 'package:fintech_wallet/core/result/failure.dart';
import 'package:fintech_wallet/features/rates/data/rates_repository.dart';
import 'package:fintech_wallet/features/rates/domain/rate_table.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fakes.dart';

void main() {
  late AppDatabase db;
  late TestBackend backend;
  late TestClock clock;
  late RatesRepository repository;

  setUp(() async {
    clock = TestClock();
    db = inMemoryDatabase();
    backend = TestBackend(clock: clock.call);
    await backend.login();
    repository = RatesRepository(db, backend.dio, clock: clock.call);
  });

  tearDown(() => db.close());

  test('fetches rates and caches them', () async {
    final first = (await repository.rates()).valueOrNull!;
    expect(first.rateMicros[Currency.usd], 3750000);
    expect(first.isStale, isFalse);

    backend.conditions.offline.value = true;
    final cached = (await repository.rates()).valueOrNull!;
    expect(cached.rateMicros, first.rateMicros);
    expect(cached.isStale, isFalse, reason: 'still within the TTL');
  });

  test('serves stale rates when a refresh fails after the TTL', () async {
    await repository.rates();
    clock.advance(const Duration(hours: 13));
    backend.conditions.offline.value = true;

    final table = (await repository.rates()).valueOrNull!;
    expect(table.isStale, isTrue);
    expect(table.rateMicros[Currency.kwd], 12195000);
  });

  test('fails when there is nothing cached and no network', () async {
    backend.conditions.offline.value = true;
    expect((await repository.rates()).failureOrNull, isA<NetworkFailure>());
  });

  group('RateTable', () {
    final table = RateTable(
      rateMicros: const {Currency.sar: 1000000, Currency.usd: 3750000, Currency.kwd: 12195000},
      fetchedAt: DateTime(2026),
    );

    test('converts to and from the base currency', () {
      expect(table.convert(const Money(1000, Currency.usd), Currency.sar), const Money(3750, Currency.sar));
      expect(table.convert(const Money(3750, Currency.sar), Currency.usd), const Money(1000, Currency.usd));
      expect(table.convert(const Money(5, Currency.sar), Currency.sar), const Money(5, Currency.sar));
    });

    test('totals mixed currencies', () {
      final total = table.total(const [Money(10000, Currency.sar), Money(1000, Currency.usd)], Currency.sar);
      expect(total, const Money(13750, Currency.sar));
    });

    test('throws for unknown currencies', () {
      expect(table.supports(Currency.jpy), isFalse);
      expect(() => table.convert(const Money(1, Currency.jpy), Currency.sar), throwsStateError);
    });
  });
}
