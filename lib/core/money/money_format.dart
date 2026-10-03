import 'package:fintech_wallet/core/money/money.dart';
import 'package:intl/intl.dart';

/// Locale-aware display formatting for [Money].
///
/// Formatting goes through the decimal string rather than `double`, so large
/// amounts are never rounded for display.
abstract final class MoneyFormat {
  static String format(Money money, String locale, {bool signed = false}) {
    final formatter = NumberFormat.decimalPattern(locale);
    final decimal = money.abs().toDecimalString();
    final parts = decimal.split('.');
    final grouped = formatter.format(int.parse(parts.first));
    final separator = formatter.symbols.DECIMAL_SEP;
    final number = parts.length > 1 ? '$grouped$separator${_localizeDigits(parts[1], formatter)}' : grouped;

    final sign = money.isNegative
        ? '-'
        : signed && money.isPositive
        ? '+'
        : '';
    return '$sign$number ${money.currency.code}';
  }

  static String _localizeDigits(String digits, NumberFormat formatter) {
    final zero = formatter.symbols.ZERO_DIGIT.codeUnitAt(0);
    if (zero == 0x30) return digits;
    return String.fromCharCodes(digits.codeUnits.map((c) => c - 0x30 + zero));
  }
}
