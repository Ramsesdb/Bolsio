/// Currency display mode persisted under `SettingKey.currencyMode`.
///
/// Drives how the dashboard renders totals:
///
/// - [single_usd]: dashboard shows ONE line in USD.
/// - [single_bs]: dashboard shows ONE line in VES.
/// - [single_other]: dashboard shows ONE line in `preferredCurrency`
///   (any non-USD/non-VES ISO code chosen by the user).
/// - [dual]: dashboard shows TWO lines: `preferredCurrency` (primary)
///   and `secondaryCurrency` (secondary).
///
/// The enum value names map 1:1 to the on-disk lowercase strings
/// (`single_usd`, `single_bs`, `single_other`, `dual`). Use [CurrencyMode.fromDb]
/// to parse a stored value tolerantly — unknown / null values resolve to [dual]
/// (per spec: "valor desconocido (versión futura → downgrade)").
// ignore_for_file: constant_identifier_names
enum CurrencyMode {
  single_usd,
  single_bs,
  single_other,
  dual;

  /// On-disk canonical string for this mode. Matches [Enum.name] verbatim;
  /// kept as an explicit getter so callers do not couple to the enum's
  /// `name` accessor and so future renames (if ever) only update this getter.
  String get dbValue => name;

  /// Tolerant parser for the on-disk value. Any unknown / null / casing
  /// variant resolves to [dual] (forward-compat default per spec).
  static CurrencyMode fromDb(String? value) {
    if (value == null) return CurrencyMode.dual;
    final normalized = value.toLowerCase().trim();
    for (final mode in CurrencyMode.values) {
      if (mode.name == normalized) return mode;
    }
    return CurrencyMode.dual;
  }
}
