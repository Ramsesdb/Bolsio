import 'package:flutter_test/flutter_test.dart';
import 'package:wallex/core/models/currency/currency_display_policy.dart';
import 'package:wallex/core/models/currency/currency_display_policy_resolver.dart';
import 'package:wallex/core/services/rate_providers/rate_source.dart';

/// Phase 2 stub tests for [CurrencyDisplayPolicy] and the pure
/// [CurrencyDisplayPolicyResolver.buildPolicy] resolver.
///
/// Per `tasks.md` task 2.4, this file is a STUB — the full coverage matrix
/// (including stream-emission, distinct suppression, integration with the
/// real `UserSettingService`) lives in Phase 10 (tasks 10.3 and 10.4).
///
/// What's covered here:
///   - Each [CurrencyMode] resolves to the expected policy variant.
///   - `displayCurrencies()` returns the right shape per mode.
///   - `showsRateSourceChip` gates on the unordered USD+VES pair.
///   - `rateSourceForPair` honours the BCV/Paralelo / Frankfurter split.
///
/// What's deferred to Phase 10:
///   - End-to-end resolver stream tests (`watch()` emissions, `.distinct()`).
///   - Settings-change reactivity (<200ms emission per spec scenario).
///   - Integration with the real `UserSettingService`.
void main() {
  group('CurrencyDisplayPolicyResolver.buildPolicy — resolution table', () {
    test('single_usd → SingleMode(USD) regardless of preferredCurrency', () {
      final policy = CurrencyDisplayPolicyResolver.buildPolicy(
        preferredCurrency: 'EUR', // ignored for single_usd
        currencyMode: 'single_usd',
        secondaryCurrency: null,
      );
      expect(policy, const SingleMode(code: 'USD'));
    });

    test('single_bs → SingleMode(VES) regardless of preferredCurrency', () {
      final policy = CurrencyDisplayPolicyResolver.buildPolicy(
        preferredCurrency: 'USD',
        currencyMode: 'single_bs',
        secondaryCurrency: 'VES',
      );
      expect(policy, const SingleMode(code: 'VES'));
    });

    test('single_other → SingleMode(preferredCurrency)', () {
      final policy = CurrencyDisplayPolicyResolver.buildPolicy(
        preferredCurrency: 'EUR',
        currencyMode: 'single_other',
        secondaryCurrency: null,
      );
      expect(policy, const SingleMode(code: 'EUR'));
    });

    test('single_other with null preferredCurrency falls back to USD', () {
      final policy = CurrencyDisplayPolicyResolver.buildPolicy(
        preferredCurrency: null,
        currencyMode: 'single_other',
        secondaryCurrency: null,
      );
      expect(policy, const SingleMode(code: 'USD'));
    });

    test('dual with explicit primary+secondary', () {
      final policy = CurrencyDisplayPolicyResolver.buildPolicy(
        preferredCurrency: 'USD',
        currencyMode: 'dual',
        secondaryCurrency: 'VES',
      );
      expect(policy, const DualMode(primary: 'USD', secondary: 'VES'));
    });

    test('dual EUR+ARS', () {
      final policy = CurrencyDisplayPolicyResolver.buildPolicy(
        preferredCurrency: 'EUR',
        currencyMode: 'dual',
        secondaryCurrency: 'ARS',
      );
      expect(policy, const DualMode(primary: 'EUR', secondary: 'ARS'));
    });

    test('dual with null secondary falls back to VES', () {
      final policy = CurrencyDisplayPolicyResolver.buildPolicy(
        preferredCurrency: 'USD',
        currencyMode: 'dual',
        secondaryCurrency: null,
      );
      expect(policy, const DualMode(primary: 'USD', secondary: 'VES'));
    });

    test('unknown mode falls back to dual(USD, VES)', () {
      final policy = CurrencyDisplayPolicyResolver.buildPolicy(
        preferredCurrency: null,
        currencyMode: 'something_from_a_newer_client',
        secondaryCurrency: null,
      );
      expect(policy, const DualMode(primary: 'USD', secondary: 'VES'));
    });

    test('null mode falls back to dual(USD, VES)', () {
      final policy = CurrencyDisplayPolicyResolver.buildPolicy(
        preferredCurrency: null,
        currencyMode: null,
        secondaryCurrency: null,
      );
      expect(policy, const DualMode(primary: 'USD', secondary: 'VES'));
    });
  });

  group('CurrencyDisplayPolicy — displayCurrencies()', () {
    test('SingleMode returns single-element list', () {
      expect(const SingleMode(code: 'USD').displayCurrencies(), ['USD']);
      expect(const SingleMode(code: 'EUR').displayCurrencies(), ['EUR']);
    });

    test('DualMode returns [primary, secondary] in render order', () {
      expect(
        const DualMode(primary: 'USD', secondary: 'VES').displayCurrencies(),
        ['USD', 'VES'],
      );
      expect(
        const DualMode(primary: 'EUR', secondary: 'ARS').displayCurrencies(),
        ['EUR', 'ARS'],
      );
    });
  });

  group('CurrencyDisplayPolicy — showsEquivalence / equivalenceCurrency', () {
    test('SingleMode: no equivalence', () {
      expect(const SingleMode(code: 'USD').showsEquivalence, isFalse);
      expect(const SingleMode(code: 'USD').equivalenceCurrency, isNull);
    });

    test('DualMode: equivalence is secondary', () {
      const policy = DualMode(primary: 'USD', secondary: 'VES');
      expect(policy.showsEquivalence, isTrue);
      expect(policy.equivalenceCurrency, 'VES');
    });
  });

  group('CurrencyDisplayPolicy — showsRateSourceChip', () {
    test('SingleMode: chip never shown', () {
      expect(const SingleMode(code: 'USD').showsRateSourceChip, isFalse);
      expect(const SingleMode(code: 'VES').showsRateSourceChip, isFalse);
      expect(const SingleMode(code: 'EUR').showsRateSourceChip, isFalse);
    });

    test('DualMode USD+VES: chip shown', () {
      expect(
        const DualMode(primary: 'USD', secondary: 'VES').showsRateSourceChip,
        isTrue,
      );
    });

    test('DualMode VES+USD (inverted order): chip still shown', () {
      // Per spec scenario "Modo dual con VES+USD (orden invertido) — chip presente".
      expect(
        const DualMode(primary: 'VES', secondary: 'USD').showsRateSourceChip,
        isTrue,
      );
    });

    test('DualMode EUR+ARS: chip absent', () {
      expect(
        const DualMode(primary: 'EUR', secondary: 'ARS').showsRateSourceChip,
        isFalse,
      );
    });

    test('DualMode USD+EUR: chip absent (no VES)', () {
      expect(
        const DualMode(primary: 'USD', secondary: 'EUR').showsRateSourceChip,
        isFalse,
      );
    });

    test('DualMode VES+EUR: chip absent (no USD)', () {
      expect(
        const DualMode(primary: 'VES', secondary: 'EUR').showsRateSourceChip,
        isFalse,
      );
    });
  });

  group('CurrencyDisplayPolicy — rateSourceForPair', () {
    test('USD↔VES uses preferred BCV/Paralelo (defaults to BCV)', () {
      const policy = DualMode(primary: 'USD', secondary: 'VES');
      expect(policy.rateSourceForPair('USD', 'VES'), RateSource.bcv);
      expect(policy.rateSourceForPair('VES', 'USD'), RateSource.bcv);
      expect(
        policy.rateSourceForPair(
          'USD',
          'VES',
          preferredVesRateSource: RateSource.paralelo,
        ),
        RateSource.paralelo,
      );
    });

    test('Non-VES fiat-fiat returns autoFrankfurter', () {
      const policy = DualMode(primary: 'USD', secondary: 'EUR');
      expect(
        policy.rateSourceForPair('USD', 'EUR'),
        RateSource.autoFrankfurter,
      );
      expect(
        policy.rateSourceForPair('EUR', 'JPY'),
        RateSource.autoFrankfurter,
      );
    });

    test('Same currency returns null', () {
      expect(
        const DualMode(primary: 'USD', secondary: 'VES')
            .rateSourceForPair('USD', 'USD'),
        isNull,
      );
      expect(
        const SingleMode(code: 'EUR').rateSourceForPair('EUR', 'EUR'),
        isNull,
      );
    });

    test('SingleMode dispatches the same rules', () {
      // The pair rules are policy-independent — Single and Dual must
      // resolve identically for the same (from, to) pair.
      const single = SingleMode(code: 'USD');
      expect(single.rateSourceForPair('USD', 'VES'), RateSource.bcv);
      expect(single.rateSourceForPair('USD', 'EUR'), RateSource.autoFrankfurter);
    });
  });

  group('CurrencyDisplayPolicy — equality and hashCode', () {
    test('SingleMode equality by code', () {
      expect(const SingleMode(code: 'USD'), const SingleMode(code: 'USD'));
      expect(
        const SingleMode(code: 'USD'),
        isNot(const SingleMode(code: 'EUR')),
      );
      expect(
        const SingleMode(code: 'USD').hashCode,
        const SingleMode(code: 'USD').hashCode,
      );
    });

    test('DualMode equality by (primary, secondary)', () {
      expect(
        const DualMode(primary: 'USD', secondary: 'VES'),
        const DualMode(primary: 'USD', secondary: 'VES'),
      );
      expect(
        const DualMode(primary: 'USD', secondary: 'VES'),
        isNot(const DualMode(primary: 'VES', secondary: 'USD')),
      );
    });

    test('SingleMode and DualMode are never equal', () {
      expect(
        const SingleMode(code: 'USD'),
        isNot(const DualMode(primary: 'USD', secondary: 'VES')),
      );
    });
  });
}
