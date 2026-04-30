/// Canonical exchange-rate source enum.
///
/// Mirrors the lowercase string stored in `exchangeRates.source` and
/// `transactions.exchangeRateSource` after the v28 migration. Lowercase is
/// canonical post-migration — callers MUST NOT add defensive `.toLowerCase()`
/// reads on persisted rows; legacy uppercase values were rewritten by v28.
///
/// | dbValue | Meaning |
/// |---|---|
/// | `bcv` | Banco Central de Venezuela (USD↔VES) — `DolarApiProvider` |
/// | `paralelo` | Tasa paralelo (USD↔VES) — `DolarApiProvider` |
/// | `auto_frankfurter` | Auto fiat-fiat via api.frankfurter.app (ECB-backed) |
/// | `manual` | User-entered manual override (also default for crypto pairs) |
enum RateSource {
  bcv('bcv'),
  paralelo('paralelo'),
  autoFrankfurter('auto_frankfurter'),
  manual('manual');

  final String dbValue;
  const RateSource(this.dbValue);

  /// Tolerant parser for the on-disk value.
  ///
  /// - `null` → [RateSource.manual] (preserves the row's effective source).
  /// - Legacy `'auto'` (pre-v28) → [RateSource.autoFrankfurter] (alias).
  /// - Mixed case / unknown → [RateSource.manual] (don't drop the row).
  ///
  /// The `.toLowerCase()` call here is the ONE allowed defensive read site;
  /// it covers (a) any row that escaped the v28 migration and (b) sync blobs
  /// from older clients during the rollout window. Do NOT replicate this
  /// pattern in new code — read raw `dbValue` everywhere else.
  static RateSource fromDb(String? value) {
    if (value == null) return RateSource.manual;
    final normalized = value.toLowerCase().trim();
    if (normalized == 'auto') return RateSource.autoFrankfurter;
    for (final source in RateSource.values) {
      if (source.dbValue == normalized) return source;
    }
    return RateSource.manual;
  }
}
