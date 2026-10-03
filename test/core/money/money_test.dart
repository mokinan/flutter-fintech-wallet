import 'package:fintech_wallet/core/money/currency.dart';
import 'package:fintech_wallet/core/money/money.dart';
import 'package:fintech_wallet/core/money/money_format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Money.tryParse', () {
    test('parses whole and fractional amounts into minor units', () {
      expect(Money.tryParse('12', Currency.sar), const Money(1200, Currency.sar));
      expect(Money.tryParse('12.5', Currency.sar), const Money(1250, Currency.sar));
      expect(Money.tryParse('1,234.05', Currency.sar), const Money(123405, Currency.sar));
    });

    test('respects currency precision', () {
      expect(Money.tryParse('1.125', Currency.kwd), const Money(1125, Currency.kwd));
      expect(Money.tryParse('500', Currency.jpy), const Money(500, Currency.jpy));
    });

    test('rejects more decimals than the currency allows instead of rounding', () {
      expect(Money.tryParse('1.005', Currency.sar), isNull);
      expect(Money.tryParse('1.5', Currency.jpy), isNull);
    });

    test('accepts Arabic-Indic digits and separators', () {
      expect(Money.tryParse('١٢٣٫٤٥', Currency.sar), const Money(12345, Currency.sar));
      expect(Money.tryParse('١٬٠٠٠', Currency.sar), const Money(100000, Currency.sar));
    });

    test('handles negatives and rejects garbage', () {
      expect(Money.tryParse('-3.20', Currency.usd), const Money(-320, Currency.usd));
      for (final input in ['', '.', '1.2.3', 'abc', '1e5', '--1']) {
        expect(Money.tryParse(input, Currency.sar), isNull, reason: input);
      }
    });

    test('rejects amounts that overflow 64-bit integers', () {
      expect(Money.tryParse('99999999999999999999', Currency.sar), isNull);
    });
  });

  group('arithmetic', () {
    test('adds and subtracts exactly', () {
      // 0.1 + 0.2 == 0.3, unlike with doubles.
      final sum = const Money(10, Currency.usd) + const Money(20, Currency.usd);
      expect(sum, const Money(30, Currency.usd));
      expect(sum - const Money(30, Currency.usd), const Money.zero(Currency.usd));
    });

    test('refuses to mix currencies', () {
      expect(() => const Money(1, Currency.sar) + const Money(1, Currency.usd), throwsArgumentError);
      expect(() => const Money(1, Currency.sar).compareTo(const Money(1, Currency.usd)), throwsArgumentError);
    });

    test('allocate distributes the remainder without losing a cent', () {
      final parts = const Money(1000, Currency.sar).allocate(3);
      expect(parts.map((m) => m.minorUnits), [334, 333, 333]);
      expect(parts.fold(0, (sum, m) => sum + m.minorUnits), 1000);

      final negative = const Money(-1000, Currency.sar).allocate(3);
      expect(negative.map((m) => m.minorUnits), [-334, -333, -333]);
    });
  });

  group('conversion', () {
    test('converts with a single rounding step, half away from zero', () {
      // 10.00 USD * 3.75 = 37.50 SAR
      expect(const Money(1000, Currency.usd).convert(Currency.sar, 3750000), const Money(3750, Currency.sar));
      // 0.01 USD * 3.75 = 0.0375 → 0.04
      expect(const Money(1, Currency.usd).convert(Currency.sar, 3750000), const Money(4, Currency.sar));
      expect(const Money(-1, Currency.usd).convert(Currency.sar, 3750000), const Money(-4, Currency.sar));
    });

    test('converts between currencies with different precision', () {
      // 1.000 KWD at 12.195 SAR = 12.20 SAR (12.195 rounds up)
      expect(const Money(1000, Currency.kwd).convert(Currency.sar, 12195000), const Money(1220, Currency.sar));
      // 100 JPY at 0.0252 SAR = 2.52 SAR
      expect(const Money(100, Currency.jpy).convert(Currency.sar, 25200), const Money(252, Currency.sar));
    });

    test('cross conversion does not round the intermediate rate', () {
      // USD → KWD via SAR: 1000.00 * 3.75 / 12.195 = 307.503... KWD
      final kwd = const Money(100000, Currency.usd).convertCross(
        Currency.kwd,
        sourceRateMicros: 3750000,
        targetRateMicros: 12195000,
      );
      expect(kwd, const Money(307503, Currency.kwd));
    });
  });

  group('formatting', () {
    test('toDecimalString pads minor units', () {
      expect(const Money(5, Currency.sar).toDecimalString(), '0.05');
      expect(const Money(-1205, Currency.kwd).toDecimalString(), '-1.205');
      expect(const Money(42, Currency.jpy).toDecimalString(), '42');
    });

    test('MoneyFormat groups digits and adds the currency code', () {
      expect(MoneyFormat.format(const Money(123456789, Currency.sar), 'en'), '1,234,567.89 SAR');
      expect(MoneyFormat.format(const Money(-1500, Currency.kwd), 'en'), '-1.500 KWD');
      expect(MoneyFormat.format(const Money(2500, Currency.sar), 'en', signed: true), '+25.00 SAR');
    });

    test('formats large amounts without double precision loss', () {
      // 9,007,199,254,740,993 minor units is not representable as a double.
      // ignore: avoid_js_rounded_ints — the point of the test; the app does not target web.
      expect(MoneyFormat.format(const Money(9007199254740993, Currency.sar), 'en'), '90,071,992,547,409.93 SAR');
    });
  });
}
