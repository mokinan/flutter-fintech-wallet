/// ISO 4217 currencies supported by the wallet.
///
/// [decimals] is the number of minor units per major unit, which is *not*
/// always 2: the Kuwaiti dinar has 3 (fils), the Japanese yen has 0.
enum Currency {
  sar('SAR', 2),
  aed('AED', 2),
  kwd('KWD', 3),
  usd('USD', 2),
  eur('EUR', 2),
  jpy('JPY', 0);

  const Currency(this.code, this.decimals);

  final String code;
  final int decimals;

  /// Minor units in one major unit, e.g. 100 for SAR, 1000 for KWD.
  int get minorPerMajor {
    var factor = 1;
    for (var i = 0; i < decimals; i++) {
      factor *= 10;
    }
    return factor;
  }

  static Currency fromCode(String code) => values.firstWhere(
    (c) => c.code == code,
    orElse: () => throw ArgumentError.value(code, 'code', 'Unsupported currency'),
  );
}
