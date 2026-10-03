import 'package:equatable/equatable.dart';
import 'package:fintech_wallet/core/money/currency.dart';

/// An exact amount of money in a single currency.
///
/// Amounts are stored as an integer number of minor units (cents, fils…), so
/// arithmetic never suffers from floating-point drift. See
/// `docs/adr/0001-money-as-integer-minor-units.md`.
class Money extends Equatable implements Comparable<Money> {
  const Money(this.minorUnits, this.currency);

  const Money.zero(this.currency) : minorUnits = 0;

  /// Parses user input such as `"1,234.5"` into [currency] minor units.
  ///
  /// Accepts Arabic-Indic digits and the Arabic decimal separator (`٫`).
  /// Returns `null` for malformed input or more fraction digits than the
  /// currency allows (e.g. `"1.234"` for SAR) — silently rounding user input
  /// is not acceptable in a financial app.
  static Money? tryParse(String input, Currency currency) {
    final normalized = _normalizeDigits(input).replaceAll(',', '').replaceAll('٬', '').replaceAll('٫', '.').trim();
    final match = RegExp(r'^(-)?(\d+)(?:\.(\d+))?$').firstMatch(normalized);
    if (match == null) return null;

    final fraction = match.group(3) ?? '';
    if (fraction.length > currency.decimals) return null;

    final whole = BigInt.parse(match.group(2)!);
    final fractionDigits = fraction.padRight(currency.decimals, '0');
    final minor =
        whole * BigInt.from(currency.minorPerMajor) +
        (fractionDigits.isEmpty ? BigInt.zero : BigInt.parse(fractionDigits));
    if (!minor.isValidInt) return null;
    final value = minor.toInt();
    return Money(match.group(1) == null ? value : -value, currency);
  }

  final int minorUnits;
  final Currency currency;

  bool get isZero => minorUnits == 0;
  bool get isNegative => minorUnits < 0;
  bool get isPositive => minorUnits > 0;

  Money operator +(Money other) {
    _assertSameCurrency(other);
    return Money(minorUnits + other.minorUnits, currency);
  }

  Money operator -(Money other) {
    _assertSameCurrency(other);
    return Money(minorUnits - other.minorUnits, currency);
  }

  Money operator -() => Money(-minorUnits, currency);

  Money abs() => isNegative ? -this : this;

  /// Converts to [target] using [rateMicros] — the price of one major unit of
  /// this currency in [target], scaled by 1,000,000.
  ///
  /// The calculation stays in integers and rounds half away from zero once,
  /// at the end.
  Money convert(Currency target, int rateMicros) =>
      convertCross(target, sourceRateMicros: rateMicros, targetRateMicros: 1000000);

  /// Converts via a common base currency, given the price of one major unit
  /// of each currency in that base (scaled by 1,000,000).
  ///
  /// Computing `source / target` as one exact fraction avoids rounding the
  /// intermediate cross rate.
  Money convertCross(Currency target, {required int sourceRateMicros, required int targetRateMicros}) {
    if (sourceRateMicros <= 0 || targetRateMicros <= 0) {
      throw ArgumentError('Rates must be positive');
    }
    // result_minor = (minor / sourceFactor) * (sourceRate / targetRate) * targetFactor
    final numerator = BigInt.from(minorUnits) * BigInt.from(sourceRateMicros) * BigInt.from(target.minorPerMajor);
    final denominator = BigInt.from(currency.minorPerMajor) * BigInt.from(targetRateMicros);
    return Money(_divideRounded(numerator, denominator), target);
  }

  /// Splits this amount into [parts] that sum exactly to the original,
  /// distributing leftover minor units to the first parts.
  List<Money> allocate(int parts) {
    if (parts <= 0) throw ArgumentError.value(parts, 'parts', 'must be positive');
    final base = minorUnits ~/ parts;
    final remainder = minorUnits.remainder(parts).abs();
    final step = minorUnits.isNegative ? -1 : 1;
    return List.generate(parts, (i) => Money(base + (i < remainder ? step : 0), currency));
  }

  /// Decimal string without grouping, e.g. `1234.50` or `-0.125`.
  String toDecimalString() {
    final factor = currency.minorPerMajor;
    final sign = isNegative ? '-' : '';
    final absolute = minorUnits.abs();
    final major = absolute ~/ factor;
    if (currency.decimals == 0) return '$sign$major';
    final minor = (absolute % factor).toString().padLeft(currency.decimals, '0');
    return '$sign$major.$minor';
  }

  @override
  int compareTo(Money other) {
    _assertSameCurrency(other);
    return minorUnits.compareTo(other.minorUnits);
  }

  void _assertSameCurrency(Money other) {
    if (other.currency != currency) {
      throw ArgumentError('Cannot combine ${currency.code} with ${other.currency.code}');
    }
  }

  static int _divideRounded(BigInt numerator, BigInt denominator) {
    final quotient = numerator ~/ denominator;
    final remainder = numerator.remainder(denominator).abs();
    if (remainder * BigInt.two >= denominator) {
      return (quotient + (numerator.isNegative ? -BigInt.one : BigInt.one)).toInt();
    }
    return quotient.toInt();
  }

  static String _normalizeDigits(String input) {
    final buffer = StringBuffer();
    for (final rune in input.runes) {
      if (rune >= 0x0660 && rune <= 0x0669) {
        buffer.writeCharCode(rune - 0x0660 + 0x30);
      } else if (rune >= 0x06F0 && rune <= 0x06F9) {
        buffer.writeCharCode(rune - 0x06F0 + 0x30);
      } else {
        buffer.writeCharCode(rune);
      }
    }
    return buffer.toString();
  }

  @override
  List<Object> get props => [minorUnits, currency];

  @override
  String toString() => '${toDecimalString()} ${currency.code}';
}
