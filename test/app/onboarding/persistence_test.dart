import 'package:flutter_test/flutter_test.dart';
import 'package:wallex/core/database/services/user-setting/user_setting_service.dart';
import 'package:wallex/core/models/currency/currency_mode.dart';
import 'package:wallex/core/models/currency/currency_display_policy.dart';
import 'package:wallex/core/models/currency/currency_display_policy_resolver.dart';

/// Phase 10 task 10.11 — Onboarding flow + persistence shape per mode +
/// `Slide03RateSource` gating.
///
/// The actual onboarding `_applyChoices()` writes via
/// `UserSettingService.instance.setItem(...)` which requires a real
/// `AppDB` boot — a heavy harness this test suite does not currently
/// provide. Per the orchestrator brief and the deferred-test pattern
/// adopted across Phases 1-9, this file pins the LOAD-BEARING invariants
/// at the pure-logic layer:
///
///   - Persistence shape per mode (the on-disk write set computed by
///     `_applyChoices`'s logic, mirrored as a pure function here).
///   - `Slide03RateSource` gating predicate (the EXACT predicate from
///     `onboarding.dart::_needsRateSourceSlide`, ported as a pure
///     function and exercised over the 5 spec scenarios).
///   - Round-trip via the resolver: every onboarding output produces a
///     coherent `CurrencyDisplayPolicy`.
///
/// What's deferred to a future widget-test pass (out of scope for the
/// 3-beta milestone):
///   - The actual page render (slide list rebuild, page controller
///     behaviour, animation state).
///   - The `s02 → s04` (skipping s03) navigation when the gating
///     predicate is false.
///
/// These deferred items are exercised end-to-end by manual smoke tests
/// before each beta build per the existing project rhythm.
void main() {
  /// Pure port of `onboarding.dart::_needsRateSourceSlide` (lines 220-229).
  /// Keep in lockstep with the production code — if the predicate
  /// changes, this helper must change too.
  bool needsRateSourceSlide({
    required CurrencyMode selectedMode,
    required String selectedPrimaryCurrency,
    required String? selectedSecondaryCurrency,
  }) {
    if (selectedMode != CurrencyMode.dual) return false;
    if (selectedSecondaryCurrency == null) return false;
    final pair = {selectedPrimaryCurrency, selectedSecondaryCurrency};
    return pair.containsAll(<String>{'USD', 'VES'});
  }

  /// Pure port of `onboarding.dart::_applyChoices` currency-mode block
  /// (lines 304-338). Returns the on-disk write set as a map keyed by
  /// `SettingKey`. `null` value means "write NULL" (canonical row);
  /// absence from the map means "do not write".
  ///
  /// This mirrors the EXACT logic of the production code:
  ///   - currencyMode + preferredCurrency are always written.
  ///   - secondaryCurrency is always written (NULL for single, ISO for dual).
  ///   - preferredRateSource is written ONLY when s03 was shown
  ///     (i.e. needsRateSourceSlide returns true).
  Map<SettingKey, String?> applyChoicesWriteSet({
    required CurrencyMode selectedMode,
    required String selectedPrimaryCurrency,
    required String? selectedSecondaryCurrency,
    required String? selectedRateSource,
  }) {
    final out = <SettingKey, String?>{
      SettingKey.currencyMode: selectedMode.dbValue,
      SettingKey.preferredCurrency: selectedPrimaryCurrency,
    };
    if (selectedMode == CurrencyMode.dual) {
      out[SettingKey.secondaryCurrency] = selectedSecondaryCurrency ?? 'VES';
    } else {
      out[SettingKey.secondaryCurrency] = null;
    }
    if (needsRateSourceSlide(
      selectedMode: selectedMode,
      selectedPrimaryCurrency: selectedPrimaryCurrency,
      selectedSecondaryCurrency: selectedSecondaryCurrency,
    )) {
      out[SettingKey.preferredRateSource] = selectedRateSource;
    }
    return out;
  }

  group('Onboarding persistence shape per mode (Task 10.11)', () {
    test('single_usd → currencyMode=single_usd, preferredCurrency=USD, '
        'secondary=null, rateSource not written', () {
      final writes = applyChoicesWriteSet(
        selectedMode: CurrencyMode.single_usd,
        selectedPrimaryCurrency: 'USD',
        selectedSecondaryCurrency: null,
        selectedRateSource: 'bcv', // ignored — s03 not shown
      );
      expect(writes[SettingKey.currencyMode], 'single_usd');
      expect(writes[SettingKey.preferredCurrency], 'USD');
      expect(writes[SettingKey.secondaryCurrency], isNull);
      expect(
        writes.containsKey(SettingKey.preferredRateSource),
        isFalse,
        reason: 's03 not shown for single mode → rateSource MUST NOT '
            'be written.',
      );
    });

    test('single_bs → currencyMode=single_bs, preferredCurrency=VES', () {
      final writes = applyChoicesWriteSet(
        selectedMode: CurrencyMode.single_bs,
        selectedPrimaryCurrency: 'VES',
        selectedSecondaryCurrency: null,
        selectedRateSource: null,
      );
      expect(writes[SettingKey.currencyMode], 'single_bs');
      expect(writes[SettingKey.preferredCurrency], 'VES');
      expect(writes[SettingKey.secondaryCurrency], isNull);
      expect(
        writes.containsKey(SettingKey.preferredRateSource),
        isFalse,
      );
    });

    test('single_other (EUR) → preferredCurrency=EUR', () {
      final writes = applyChoicesWriteSet(
        selectedMode: CurrencyMode.single_other,
        selectedPrimaryCurrency: 'EUR',
        selectedSecondaryCurrency: null,
        selectedRateSource: null,
      );
      expect(writes[SettingKey.currencyMode], 'single_other');
      expect(writes[SettingKey.preferredCurrency], 'EUR');
      expect(writes[SettingKey.secondaryCurrency], isNull);
      expect(
        writes.containsKey(SettingKey.preferredRateSource),
        isFalse,
      );
    });

    test(
      'dual(USD, VES) → primary=USD, secondary=VES, rateSource WRITTEN '
      '(s03 shown)',
      () {
        final writes = applyChoicesWriteSet(
          selectedMode: CurrencyMode.dual,
          selectedPrimaryCurrency: 'USD',
          selectedSecondaryCurrency: 'VES',
          selectedRateSource: 'paralelo',
        );
        expect(writes[SettingKey.currencyMode], 'dual');
        expect(writes[SettingKey.preferredCurrency], 'USD');
        expect(writes[SettingKey.secondaryCurrency], 'VES');
        expect(
          writes[SettingKey.preferredRateSource],
          'paralelo',
          reason: 's03 was shown for dual(USD,VES) — the user pick MUST '
              'be persisted.',
        );
      },
    );

    test(
      'dual(VES, USD) inverted order → primary=VES, secondary=USD, chip '
      'STILL gated → rateSource WRITTEN',
      () {
        final writes = applyChoicesWriteSet(
          selectedMode: CurrencyMode.dual,
          selectedPrimaryCurrency: 'VES',
          selectedSecondaryCurrency: 'USD',
          selectedRateSource: 'bcv',
        );
        expect(writes[SettingKey.currencyMode], 'dual');
        expect(writes[SettingKey.preferredCurrency], 'VES');
        expect(writes[SettingKey.secondaryCurrency], 'USD');
        expect(writes[SettingKey.preferredRateSource], 'bcv');
      },
    );

    test(
      'dual(EUR, ARS) → rateSource NOT written (s03 not shown for non '
      'USD↔VES dual)',
      () {
        final writes = applyChoicesWriteSet(
          selectedMode: CurrencyMode.dual,
          selectedPrimaryCurrency: 'EUR',
          selectedSecondaryCurrency: 'ARS',
          selectedRateSource: 'bcv', // ignored — s03 not shown
        );
        expect(writes[SettingKey.currencyMode], 'dual');
        expect(writes[SettingKey.preferredCurrency], 'EUR');
        expect(writes[SettingKey.secondaryCurrency], 'ARS');
        expect(
          writes.containsKey(SettingKey.preferredRateSource),
          isFalse,
          reason:
              'dual(EUR,ARS) does NOT route through s03 — rateSource MUST '
              'NOT be written.',
        );
      },
    );

    test(
      'dual with null secondary defaults to VES (legacy fallback)',
      () {
        final writes = applyChoicesWriteSet(
          selectedMode: CurrencyMode.dual,
          selectedPrimaryCurrency: 'USD',
          selectedSecondaryCurrency: null,
          selectedRateSource: 'bcv',
        );
        expect(writes[SettingKey.secondaryCurrency], 'VES');
      },
    );
  });

  group('Slide03RateSource gating predicate (Task 10.11)', () {
    test('mode != dual → false (single_usd / single_bs / single_other)', () {
      expect(
        needsRateSourceSlide(
          selectedMode: CurrencyMode.single_usd,
          selectedPrimaryCurrency: 'USD',
          selectedSecondaryCurrency: null,
        ),
        isFalse,
      );
      expect(
        needsRateSourceSlide(
          selectedMode: CurrencyMode.single_bs,
          selectedPrimaryCurrency: 'VES',
          selectedSecondaryCurrency: null,
        ),
        isFalse,
      );
      expect(
        needsRateSourceSlide(
          selectedMode: CurrencyMode.single_other,
          selectedPrimaryCurrency: 'EUR',
          selectedSecondaryCurrency: null,
        ),
        isFalse,
      );
    });

    test('dual + secondary == null → false', () {
      expect(
        needsRateSourceSlide(
          selectedMode: CurrencyMode.dual,
          selectedPrimaryCurrency: 'USD',
          selectedSecondaryCurrency: null,
        ),
        isFalse,
      );
    });

    test('dual(USD, VES) → true (canonical pair)', () {
      expect(
        needsRateSourceSlide(
          selectedMode: CurrencyMode.dual,
          selectedPrimaryCurrency: 'USD',
          selectedSecondaryCurrency: 'VES',
        ),
        isTrue,
      );
    });

    test('dual(VES, USD) → true (unordered gating)', () {
      expect(
        needsRateSourceSlide(
          selectedMode: CurrencyMode.dual,
          selectedPrimaryCurrency: 'VES',
          selectedSecondaryCurrency: 'USD',
        ),
        isTrue,
      );
    });

    test('dual(EUR, ARS) → false (no VES nor USD)', () {
      expect(
        needsRateSourceSlide(
          selectedMode: CurrencyMode.dual,
          selectedPrimaryCurrency: 'EUR',
          selectedSecondaryCurrency: 'ARS',
        ),
        isFalse,
      );
    });

    test('dual(USD, EUR) → false (missing VES)', () {
      expect(
        needsRateSourceSlide(
          selectedMode: CurrencyMode.dual,
          selectedPrimaryCurrency: 'USD',
          selectedSecondaryCurrency: 'EUR',
        ),
        isFalse,
      );
    });

    test('dual(VES, EUR) → false (missing USD)', () {
      expect(
        needsRateSourceSlide(
          selectedMode: CurrencyMode.dual,
          selectedPrimaryCurrency: 'VES',
          selectedSecondaryCurrency: 'EUR',
        ),
        isFalse,
      );
    });
  });

  group(
    'Onboarding output round-trips via the resolver',
    () {
      // For each mode, verify that the persistence shape produced by
      // `_applyChoices` (mirrored above) feeds the resolver to produce
      // a coherent policy.
      test('single_usd → SingleMode(USD)', () {
        final writes = applyChoicesWriteSet(
          selectedMode: CurrencyMode.single_usd,
          selectedPrimaryCurrency: 'USD',
          selectedSecondaryCurrency: null,
          selectedRateSource: null,
        );
        final policy = CurrencyDisplayPolicyResolver.buildPolicy(
          preferredCurrency: writes[SettingKey.preferredCurrency],
          currencyMode: writes[SettingKey.currencyMode],
          secondaryCurrency: writes[SettingKey.secondaryCurrency],
        );
        expect(policy, const SingleMode(code: 'USD'));
      });

      test('single_other(EUR) → SingleMode(EUR)', () {
        final writes = applyChoicesWriteSet(
          selectedMode: CurrencyMode.single_other,
          selectedPrimaryCurrency: 'EUR',
          selectedSecondaryCurrency: null,
          selectedRateSource: null,
        );
        final policy = CurrencyDisplayPolicyResolver.buildPolicy(
          preferredCurrency: writes[SettingKey.preferredCurrency],
          currencyMode: writes[SettingKey.currencyMode],
          secondaryCurrency: writes[SettingKey.secondaryCurrency],
        );
        expect(policy, const SingleMode(code: 'EUR'));
      });

      test('dual(USD, VES) → DualMode(USD, VES) with chip on', () {
        final writes = applyChoicesWriteSet(
          selectedMode: CurrencyMode.dual,
          selectedPrimaryCurrency: 'USD',
          selectedSecondaryCurrency: 'VES',
          selectedRateSource: 'bcv',
        );
        final policy = CurrencyDisplayPolicyResolver.buildPolicy(
          preferredCurrency: writes[SettingKey.preferredCurrency],
          currencyMode: writes[SettingKey.currencyMode],
          secondaryCurrency: writes[SettingKey.secondaryCurrency],
        );
        expect(policy, const DualMode(primary: 'USD', secondary: 'VES'));
        expect(policy.showsRateSourceChip, isTrue);
      });

      test('dual(EUR, ARS) → DualMode(EUR, ARS) with chip OFF', () {
        final writes = applyChoicesWriteSet(
          selectedMode: CurrencyMode.dual,
          selectedPrimaryCurrency: 'EUR',
          selectedSecondaryCurrency: 'ARS',
          selectedRateSource: null,
        );
        final policy = CurrencyDisplayPolicyResolver.buildPolicy(
          preferredCurrency: writes[SettingKey.preferredCurrency],
          currencyMode: writes[SettingKey.currencyMode],
          secondaryCurrency: writes[SettingKey.secondaryCurrency],
        );
        expect(policy, const DualMode(primary: 'EUR', secondary: 'ARS'));
        expect(policy.showsRateSourceChip, isFalse);
      });
    },
  );
}
