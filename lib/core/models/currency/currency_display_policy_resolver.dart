import 'package:rxdart/rxdart.dart';
import 'package:bolsio/core/database/services/user-setting/user_setting_service.dart';
import 'package:bolsio/core/models/currency/currency_display_policy.dart';
import 'package:bolsio/core/models/currency/currency_mode.dart';

/// Resolves a reactive [CurrencyDisplayPolicy] from `userSettings` rows.
///
/// Combines the three keys that drive layout decisions:
///
/// - `SettingKey.preferredCurrency`
/// - `SettingKey.currencyMode`
/// - `SettingKey.secondaryCurrency`
///
/// and emits a new policy on any change. The output stream is
/// `.distinct()`-suppressed — equal policies do not re-emit.
///
/// Widgets MUST consume `instance.watch()` instead of subscribing to the
/// raw setting keys individually. See
/// `openspec/changes/currency-modes-rework/design.md` §3.
class CurrencyDisplayPolicyResolver {
  CurrencyDisplayPolicyResolver._({UserSettingService? userSettingService})
    : _userSettingService = userSettingService ?? UserSettingService.instance;

  /// Process-wide singleton. Mirrors the convention used by other
  /// `lib/core/database/services/` services (see `PrivateModeService`,
  /// `HiddenModeService`).
  static final CurrencyDisplayPolicyResolver instance =
      CurrencyDisplayPolicyResolver._();

  /// Internal-only constructor for unit tests. Lets a test inject a
  /// fake / fixture `UserSettingService` without touching the real
  /// database. Not exposed via the public singleton — production code
  /// uses [instance].
  static CurrencyDisplayPolicyResolver forTesting({
    required UserSettingService userSettingService,
  }) => CurrencyDisplayPolicyResolver._(
    userSettingService: userSettingService,
  );

  final UserSettingService _userSettingService;

  /// Returns a stream that emits the current [CurrencyDisplayPolicy] and
  /// re-emits whenever `preferredCurrency`, `currencyMode`, or
  /// `secondaryCurrency` changes.
  ///
  /// Equal policies are suppressed via `.distinct()` (relies on the
  /// `==` overrides in [SingleMode] and [DualMode]).
  Stream<CurrencyDisplayPolicy> watch() {
    return Rx.combineLatest3<String?, String?, String?, CurrencyDisplayPolicy>(
      _userSettingService.getSettingFromDB(SettingKey.preferredCurrency),
      _userSettingService.getSettingFromDB(SettingKey.currencyMode),
      _userSettingService.getSettingFromDB(SettingKey.secondaryCurrency),
      _buildPolicy,
    ).distinct();
  }

  /// Pure builder — exposed as a `static` so unit tests can exercise the
  /// resolution table without booting an `Rx.combineLatest3` pipeline.
  ///
  /// Resolution rules (per design §3):
  ///
  /// | mode            | primary               | secondary       | result                                  |
  /// |-----------------|-----------------------|-----------------|-----------------------------------------|
  /// | `single_usd`    | (forced) `'USD'`      | n/a             | `SingleMode('USD')`                     |
  /// | `single_bs`     | (forced) `'VES'`      | n/a             | `SingleMode('VES')`                     |
  /// | `single_other`  | `pref` (or `'USD'`)   | n/a             | `SingleMode(pref)`                      |
  /// | `dual`          | `pref` (or `'USD'`)   | `sec` (or `'VES'`) | `DualMode(pref, sec)`                |
  /// | unknown / null  | fallback              | fallback        | `DualMode('USD','VES')` (forward-compat)|
  ///
  /// The fallback for unknown values mirrors `CurrencyMode.fromDb` — any
  /// future mode emitted by a newer client downgrades to the safe
  /// `dual(USD,VES)` policy on this client.
  static CurrencyDisplayPolicy buildPolicy({
    required String? preferredCurrency,
    required String? currencyMode,
    required String? secondaryCurrency,
  }) {
    final mode = CurrencyMode.fromDb(currencyMode);
    switch (mode) {
      case CurrencyMode.single_usd:
        return const SingleMode(code: 'USD');
      case CurrencyMode.single_bs:
        return const SingleMode(code: 'VES');
      case CurrencyMode.single_other:
        // `single_other` honours `preferredCurrency` verbatim. If the user
        // somehow lands here without a preferred currency, fall back to
        // USD (matches the legacy default everywhere else in the app).
        return SingleMode(code: preferredCurrency ?? 'USD');
      case CurrencyMode.dual:
        return DualMode(
          primary: preferredCurrency ?? 'USD',
          secondary: secondaryCurrency ?? 'VES',
        );
    }
  }

  /// Bridge between the `Rx.combineLatest3` raw tuple and [buildPolicy].
  static CurrencyDisplayPolicy _buildPolicy(
    String? preferredCurrency,
    String? currencyMode,
    String? secondaryCurrency,
  ) => buildPolicy(
    preferredCurrency: preferredCurrency,
    currencyMode: currencyMode,
    secondaryCurrency: secondaryCurrency,
  );
}
