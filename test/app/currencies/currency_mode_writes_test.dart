import 'package:flutter_test/flutter_test.dart';
import 'package:wallex/app/currencies/widgets/currency_mode_picker.dart';
import 'package:wallex/core/models/currency/currency_mode.dart';

/// Phase 5 task 5.3 — verifies the on-disk write set produced for a
/// mode change. The implementation MUST:
///
///   1. Write [SettingKey.currencyMode] and [SettingKey.preferredCurrency]
///      on every change.
///   2. Write [SettingKey.secondaryCurrency] ONLY when the new mode is
///      `dual`. On Dual → Single switches the row MUST be left untouched
///      (resolved decision #2: "secondaryCurrency is PRESERVED on Dual
///      → Single switch").
///   3. Write [SettingKey.preferredRateSource] ONLY when the new mode is
///      `dual` AND the unordered pair is exactly USD+VES.
///   4. Touch NO other setting (and by extension no accounts /
///      transactions tables — see [computeModeWrites] doc).
///
/// These tests exercise the pure value-object factory; widget-level
/// behaviour (bottom sheet flow, snackbar) is out of scope for the
/// stub-test pattern adopted across `currency-modes-rework`.
void main() {
  group('computeModeWrites — single_usd', () {
    test('writes currencyMode + preferredCurrency, leaves secondary alone',
        () {
      final writes = computeModeWrites(
        newMode: CurrencyMode.single_usd,
        primary: 'USD',
        secondary: null,
        selectedRateSource: 'bcv',
      );
      expect(writes.currencyMode, 'single_usd');
      expect(writes.preferredCurrency, 'USD');
      expect(writes.shouldWriteSecondary, isFalse);
      expect(writes.shouldWriteRateSource, isFalse);
    });

    test('Dual → single_usd PRESERVES the existing secondaryCurrency '
        '(resolved decision #2)', () {
      // Simulate the input the widget would pass when the user's current
      // dual pair was USD+VES and they pick "Solo USD" in the bottom sheet.
      // The picker's [CurrencyModeChoice.secondary] for a single mode is
      // null OR the in-memory cache; either way, the resulting writes
      // MUST NOT touch [SettingKey.secondaryCurrency].
      final writes = computeModeWrites(
        newMode: CurrencyMode.single_usd,
        primary: 'USD',
        // The widget keeps `_secondary` populated as 'VES' (preserved
        // across single switches) — but `computeModeWrites` MUST ignore
        // it for single modes.
        secondary: 'VES',
        selectedRateSource: 'bcv',
      );
      expect(writes.shouldWriteSecondary, isFalse,
          reason: 'Dual → Single MUST NOT write secondaryCurrency '
              '(it is preserved on disk).');
      expect(writes.secondaryCurrency, isNull);
    });
  });

  group('computeModeWrites — single_bs', () {
    test('writes preferredCurrency=VES, leaves secondary alone', () {
      final writes = computeModeWrites(
        newMode: CurrencyMode.single_bs,
        primary: 'VES',
        secondary: null,
        selectedRateSource: 'bcv',
      );
      expect(writes.currencyMode, 'single_bs');
      expect(writes.preferredCurrency, 'VES');
      expect(writes.shouldWriteSecondary, isFalse);
      expect(writes.shouldWriteRateSource, isFalse);
    });

    test('Dual(EUR+ARS) → single_bs PRESERVES secondaryCurrency', () {
      final writes = computeModeWrites(
        newMode: CurrencyMode.single_bs,
        primary: 'VES',
        secondary: 'ARS',
        selectedRateSource: 'paralelo',
      );
      expect(writes.shouldWriteSecondary, isFalse);
      expect(writes.shouldWriteRateSource, isFalse);
    });
  });

  group('computeModeWrites — single_other', () {
    test('writes preferredCurrency to picked code, leaves secondary alone',
        () {
      final writes = computeModeWrites(
        newMode: CurrencyMode.single_other,
        primary: 'EUR',
        secondary: null,
        selectedRateSource: 'bcv',
      );
      expect(writes.currencyMode, 'single_other');
      expect(writes.preferredCurrency, 'EUR');
      expect(writes.shouldWriteSecondary, isFalse);
      expect(writes.shouldWriteRateSource, isFalse);
    });

    test('uppercases the chosen code', () {
      final writes = computeModeWrites(
        newMode: CurrencyMode.single_other,
        primary: 'eur',
        secondary: null,
        selectedRateSource: 'bcv',
      );
      expect(writes.preferredCurrency, 'EUR');
    });

    test('Dual → single_other(EUR) PRESERVES the dual secondary on disk',
        () {
      final writes = computeModeWrites(
        newMode: CurrencyMode.single_other,
        primary: 'EUR',
        secondary: 'VES',
        selectedRateSource: 'bcv',
      );
      expect(writes.shouldWriteSecondary, isFalse);
    });
  });

  group('computeModeWrites — dual', () {
    test('writes the full triple for dual USD+VES + rate source', () {
      final writes = computeModeWrites(
        newMode: CurrencyMode.dual,
        primary: 'USD',
        secondary: 'VES',
        selectedRateSource: 'bcv',
      );
      expect(writes.currencyMode, 'dual');
      expect(writes.preferredCurrency, 'USD');
      expect(writes.shouldWriteSecondary, isTrue);
      expect(writes.secondaryCurrency, 'VES');
      expect(writes.shouldWriteRateSource, isTrue);
      expect(writes.preferredRateSource, 'bcv');
    });

    test('VES + USD (reversed pair) still gates the rate-source chip ON',
        () {
      final writes = computeModeWrites(
        newMode: CurrencyMode.dual,
        primary: 'VES',
        secondary: 'USD',
        selectedRateSource: 'paralelo',
      );
      expect(writes.shouldWriteRateSource, isTrue,
          reason: 'Pair is unordered for chip gating per design §3.');
      expect(writes.preferredRateSource, 'paralelo');
    });

    test('non-VES pair (EUR+ARS) does NOT write the rate source', () {
      final writes = computeModeWrites(
        newMode: CurrencyMode.dual,
        primary: 'EUR',
        secondary: 'ARS',
        selectedRateSource: 'bcv',
      );
      expect(writes.shouldWriteSecondary, isTrue);
      expect(writes.secondaryCurrency, 'ARS');
      expect(writes.shouldWriteRateSource, isFalse,
          reason: 'BCV/Paralelo gating is USD+VES only.');
    });

    test('dual with null secondary defaults to VES', () {
      final writes = computeModeWrites(
        newMode: CurrencyMode.dual,
        primary: 'USD',
        secondary: null,
        selectedRateSource: 'bcv',
      );
      expect(writes.secondaryCurrency, 'VES');
    });

    test('uppercases primary and secondary', () {
      final writes = computeModeWrites(
        newMode: CurrencyMode.dual,
        primary: 'usd',
        secondary: 'ves',
        selectedRateSource: 'bcv',
      );
      expect(writes.preferredCurrency, 'USD');
      expect(writes.secondaryCurrency, 'VES');
      expect(writes.shouldWriteRateSource, isTrue);
    });
  });

  group('computeModeWrites — invariants', () {
    test('every mode change writes currencyMode and preferredCurrency', () {
      for (final mode in CurrencyMode.values) {
        final writes = computeModeWrites(
          newMode: mode,
          primary: 'USD',
          secondary: 'VES',
          selectedRateSource: 'bcv',
        );
        expect(writes.currencyMode, isNotEmpty);
        expect(writes.preferredCurrency, isNotEmpty);
      }
    });

    test('only dual mode ever writes secondaryCurrency', () {
      for (final mode in CurrencyMode.values) {
        final writes = computeModeWrites(
          newMode: mode,
          primary: 'USD',
          secondary: 'VES',
          selectedRateSource: 'bcv',
        );
        if (mode == CurrencyMode.dual) {
          expect(writes.shouldWriteSecondary, isTrue);
        } else {
          expect(writes.shouldWriteSecondary, isFalse,
              reason: '$mode MUST NOT write secondaryCurrency '
                  '(preservation rule).');
        }
      }
    });

    test('only dual USD+VES writes preferredRateSource', () {
      // Single modes
      for (final mode in [
        CurrencyMode.single_usd,
        CurrencyMode.single_bs,
        CurrencyMode.single_other,
      ]) {
        final writes = computeModeWrites(
          newMode: mode,
          primary: 'USD',
          secondary: 'VES',
          selectedRateSource: 'bcv',
        );
        expect(writes.shouldWriteRateSource, isFalse);
      }

      // Dual non-VES
      final dualEurArs = computeModeWrites(
        newMode: CurrencyMode.dual,
        primary: 'EUR',
        secondary: 'ARS',
        selectedRateSource: 'bcv',
      );
      expect(dualEurArs.shouldWriteRateSource, isFalse);

      // Dual USD+VES (forward and reversed)
      final dualUsdVes = computeModeWrites(
        newMode: CurrencyMode.dual,
        primary: 'USD',
        secondary: 'VES',
        selectedRateSource: 'bcv',
      );
      expect(dualUsdVes.shouldWriteRateSource, isTrue);

      final dualVesUsd = computeModeWrites(
        newMode: CurrencyMode.dual,
        primary: 'VES',
        secondary: 'USD',
        selectedRateSource: 'paralelo',
      );
      expect(dualVesUsd.shouldWriteRateSource, isTrue);
    });
  });

  group('CurrencyModeWrites — value semantics', () {
    test('equality + hashCode reflect all fields', () {
      const a = CurrencyModeWrites(
        currencyMode: 'dual',
        preferredCurrency: 'USD',
        secondaryCurrency: 'VES',
        preferredRateSource: 'bcv',
      );
      const b = CurrencyModeWrites(
        currencyMode: 'dual',
        preferredCurrency: 'USD',
        secondaryCurrency: 'VES',
        preferredRateSource: 'bcv',
      );
      const c = CurrencyModeWrites(
        currencyMode: 'dual',
        preferredCurrency: 'USD',
        secondaryCurrency: 'VES',
        preferredRateSource: 'paralelo',
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
    });

    test('toString includes all fields for debug output', () {
      const w = CurrencyModeWrites(
        currencyMode: 'single_usd',
        preferredCurrency: 'USD',
      );
      final s = w.toString();
      expect(s, contains('single_usd'));
      expect(s, contains('USD'));
    });
  });
}
