# 1. Represent money as integer minor units

- Status: accepted

## Context

Binary floating point cannot represent most decimal fractions: `0.1 + 0.2 != 0.3`.
In a wallet, these errors surface as balances that are off by a fil, totals that
don't match their parts, and reconciliation failures with the server.

Currencies also differ in precision. SAR and USD have 2 decimal places, KWD has
3, and JPY has none, so "store cents" is not enough on its own.

## Decision

- Every amount is a `Money` value: an `int` count of **minor units** plus a
  `Currency` that knows its ISO 4217 precision.
- The database stores `amount_minor INTEGER` and a currency code. No `REAL`
  columns exist on the money path.
- User input is parsed straight to minor units. Input with more decimals than
  the currency allows is **rejected**, not rounded.
- FX rates are stored as integers scaled by 10⁶. Conversion is computed as one
  exact fraction with `BigInt` and rounded once (half away from zero) at the
  end. Cross rates are never materialized, so they are never rounded.
- Formatting groups the integer part and appends the minor digits as text.
  Large amounts never pass through `double`.

## Consequences

- Arithmetic is exact, and mixing currencies throws instead of silently
  producing a wrong total.
- `Money.allocate` splits amounts without losing a minor unit, which is useful
  for bill splitting later.
- The maximum amount is bounded by 64-bit integers (~92 quadrillion SAR), which
  is acceptable.
- Every developer must use `Money` rather than `num`. This is enforced by
  review and by the domain types, not by a lint.
