import 'package:kilatex/core/services/rate_providers/rate_source.dart';

/// Sealed abstraction that drives how the dashboard renders totals,
/// equivalences, and the BCV/Paralelo chip.
///
/// The policy is resolved from `userSettings` (`currencyMode`,
/// `preferredCurrency`, `secondaryCurrency`) by
/// [CurrencyDisplayPolicyResolver]. Widgets MUST consume the policy stream
/// instead of reading those keys individually, so layout decisions
/// ("two lines? show chip? what equivalence currency?") have a single
/// source of truth.
///
/// Two variants:
///
/// - [SingleMode]: dashboard renders ONE line in [SingleMode.code].
/// - [DualMode]: dashboard renders TWO lines —
///   [DualMode.primary] (top) and [DualMode.secondary] (subordinated).
///
/// See `openspec/changes/currency-modes-rework/specs/currency-display/spec.md`
/// for the full contract.
sealed class CurrencyDisplayPolicy {
  const CurrencyDisplayPolicy();

  /// Construct a single-line policy (one currency on the dashboard).
  const factory CurrencyDisplayPolicy.single({required String code}) =
      SingleMode;

  /// Construct a dual-line policy (primary + secondary equivalence).
  const factory CurrencyDisplayPolicy.dual({
    required String primary,
    required String secondary,
  }) = DualMode;

  /// Currencies the user wants to *see* on the dashboard.
  ///
  /// - `[code]` for [SingleMode];
  /// - `[primary, secondary]` for [DualMode] (in render order).
  List<String> displayCurrencies();

  /// True when the BCV/Paralelo chip / `RateSourceTooltip` MUST be rendered.
  ///
  /// Per spec, the chip appears EXCLUSIVELY when:
  ///   1. policy is [DualMode], AND
  ///   2. the unordered pair is exactly `{USD, VES}`.
  ///
  /// Always false for [SingleMode].
  bool get showsRateSourceChip;

  /// True when widgets render a secondary equivalence line.
  ///
  /// True only for [DualMode]; [SingleMode] never shows equivalence.
  bool get showsEquivalence => this is DualMode;

  /// The secondary equivalence currency, if any.
  ///
  /// Returns `DualMode.secondary` for dual mode; `null` for single mode.
  String? get equivalenceCurrency;

  /// Pick the [RateSource] to use for converting between [from] and [to].
  ///
  /// Resolution rules (per design §4):
  ///   - the (USD, VES) pair (unordered) returns the user's preferred
  ///     `bcv` / `paralelo` choice — supplied by the resolver via
  ///     [preferredVesRateSource]; defaults to [RateSource.bcv] when null.
  ///   - any other fiat-fiat pair returns [RateSource.autoFrankfurter].
  ///   - returns `null` if [from] equals [to] (no conversion needed).
  ///   - any non-fiat pair (crypto, unsupported) defaults to
  ///     [RateSource.manual].
  ///
  /// The optional [preferredVesRateSource] argument lets the resolver
  /// inject the user's `preferredRateSource` setting without coupling the
  /// policy to `UserSettingService`. Callers that don't have it can pass
  /// `null` and the policy assumes [RateSource.bcv] for the VES pair.
  RateSource? rateSourceForPair(
    String from,
    String to, {
    RateSource? preferredVesRateSource,
  });
}

/// One-line dashboard mode. The total is rendered in [code] only — no
/// secondary equivalence, no BCV/Paralelo chip.
final class SingleMode extends CurrencyDisplayPolicy {
  /// ISO 4217 (or supported crypto) code that drives the single line.
  final String code;

  const SingleMode({required this.code});

  @override
  List<String> displayCurrencies() => [code];

  @override
  bool get showsRateSourceChip => false;

  @override
  String? get equivalenceCurrency => null;

  @override
  RateSource? rateSourceForPair(
    String from,
    String to, {
    RateSource? preferredVesRateSource,
  }) => _rateSourceForPair(from, to, preferredVesRateSource);

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is SingleMode && other.code == code);

  @override
  int get hashCode => Object.hash('SingleMode', code);

  @override
  String toString() => 'SingleMode(code: $code)';
}

/// Two-line dashboard mode: [primary] on top, [secondary] equivalence below.
///
/// Order matters for visual presentation but NOT for the BCV/Paralelo chip
/// gating: `dual(USD, VES)` and `dual(VES, USD)` both show the chip.
final class DualMode extends CurrencyDisplayPolicy {
  /// Primary currency (top line).
  final String primary;

  /// Secondary equivalence currency (bottom line).
  final String secondary;

  const DualMode({required this.primary, required this.secondary});

  @override
  List<String> displayCurrencies() => [primary, secondary];

  @override
  bool get showsRateSourceChip {
    final pair = {primary, secondary};
    return pair.length == 2 && pair.contains('USD') && pair.contains('VES');
  }

  @override
  String? get equivalenceCurrency => secondary;

  @override
  RateSource? rateSourceForPair(
    String from,
    String to, {
    RateSource? preferredVesRateSource,
  }) => _rateSourceForPair(from, to, preferredVesRateSource);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DualMode &&
          other.primary == primary &&
          other.secondary == secondary);

  @override
  int get hashCode => Object.hash('DualMode', primary, secondary);

  @override
  String toString() => 'DualMode(primary: $primary, secondary: $secondary)';
}

/// Shared rate-source resolution shared by both variants.
///
/// Kept as a top-level helper so [SingleMode] and [DualMode] dispatch
/// identically (the rule is policy-independent — it depends only on the
/// pair). Lives at the file top-level (not on the sealed class) so it
/// stays a `const`-friendly pure function.
RateSource? _rateSourceForPair(
  String from,
  String to,
  RateSource? preferredVesRateSource,
) {
  if (from == to) return null;
  final pair = {from, to};
  if (pair.contains('USD') && pair.contains('VES')) {
    return preferredVesRateSource ?? RateSource.bcv;
  }
  // Non-VES fiat-fiat pairs use the auto Frankfurter provider.
  // Crypto / unsupported pairs default to manual at the provider layer;
  // the policy itself returns autoFrankfurter and lets the provider chain
  // fall back to manual when the pair is unsupported.
  return RateSource.autoFrankfurter;
}
