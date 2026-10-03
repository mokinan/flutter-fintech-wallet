import 'package:equatable/equatable.dart';
import 'package:fintech_wallet/core/money/currency.dart';
import 'package:fintech_wallet/core/money/money.dart';

/// A snapshot of FX rates: the price of one unit of each currency in the base
/// currency, scaled by 1,000,000.
class RateTable extends Equatable {
  const RateTable({required this.rateMicros, required this.fetchedAt, this.isStale = false});

  final Map<Currency, int> rateMicros;
  final DateTime fetchedAt;

  /// True when the rates are older than the cache TTL because a refresh
  /// failed — the UI shows when they were last updated.
  final bool isStale;

  bool supports(Currency currency) => rateMicros.containsKey(currency);

  Money convert(Money money, Currency target) {
    if (money.currency == target) return money;
    final source = rateMicros[money.currency];
    final destination = rateMicros[target];
    if (source == null || destination == null) {
      throw StateError('No rate for ${money.currency.code} → ${target.code}');
    }
    return money.convertCross(target, sourceRateMicros: source, targetRateMicros: destination);
  }

  /// Sums amounts in mixed currencies into [target].
  Money total(Iterable<Money> amounts, Currency target) =>
      amounts.fold(Money.zero(target), (sum, m) => sum + convert(m, target));

  @override
  List<Object> get props => [rateMicros, fetchedAt, isStale];
}
