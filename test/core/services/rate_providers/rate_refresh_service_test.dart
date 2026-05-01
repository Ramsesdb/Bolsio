import 'package:flutter_test/flutter_test.dart';
import 'package:nitido/core/models/currency/currency_display_policy.dart';
import 'package:nitido/core/services/rate_providers/rate_refresh_service.dart';

/// Phase 4.5 of `currency-modes-rework`: the rate refresher derives its
/// pair set from the active [CurrencyDisplayPolicy] plus any
/// foreign-currency account the user has. This test pins the resolution
/// table for the pure helper [RateRefreshService.derivePairsToRefresh],
/// which is the only piece of the service that lives without I/O.
///
/// The actual refresh job (`_runJob`) is integration-level — it talks to
/// `RateProviderManager` (DolarApi) + `RateProviderChain` (Frankfurter) +
/// `ExchangeRateService` (Drift), so its happy path is tested by the
/// existing `frankfurter_provider_test.dart` and
/// `rate_provider_chain_test.dart` suites.
void main() {
  group('RateRefreshService.derivePairsToRefresh', () {
    test('single_usd with no foreign accounts → no pairs', () {
      final pairs = RateRefreshService.derivePairsToRefresh(
        policy: const SingleMode(code: 'USD'),
        preferredCurrency: 'USD',
        accountCurrencies: const [],
      );
      expect(pairs, isEmpty);
    });

    test('single_usd with USD-only accounts → no pairs', () {
      final pairs = RateRefreshService.derivePairsToRefresh(
        policy: const SingleMode(code: 'USD'),
        preferredCurrency: 'USD',
        accountCurrencies: const ['USD', 'usd'],
      );
      expect(pairs, isEmpty);
    });

    test('single_bs with one VES account → no pairs (preferred is base)', () {
      final pairs = RateRefreshService.derivePairsToRefresh(
        policy: const SingleMode(code: 'VES'),
        preferredCurrency: 'VES',
        accountCurrencies: const ['VES'],
      );
      expect(pairs, isEmpty);
    });

    test('single_bs with USD and VES accounts → USD→VES pair', () {
      final pairs = RateRefreshService.derivePairsToRefresh(
        policy: const SingleMode(code: 'VES'),
        preferredCurrency: 'VES',
        accountCurrencies: const ['USD', 'VES'],
      );
      expect(pairs, equals({(from: 'USD', to: 'VES')}));
    });

    test('dual(USD, VES) with USD+VES accounts → VES pair only', () {
      // Preferred = USD, secondary = VES. The pair is VES→USD, since
      // the preferred currency is the storage base.
      final pairs = RateRefreshService.derivePairsToRefresh(
        policy: const DualMode(primary: 'USD', secondary: 'VES'),
        preferredCurrency: 'USD',
        accountCurrencies: const ['USD', 'VES'],
      );
      expect(pairs, equals({(from: 'VES', to: 'USD')}));
    });

    test('dual(USD, VES) with EUR account too → VES + EUR pairs', () {
      final pairs = RateRefreshService.derivePairsToRefresh(
        policy: const DualMode(primary: 'USD', secondary: 'VES'),
        preferredCurrency: 'USD',
        accountCurrencies: const ['USD', 'VES', 'EUR'],
      );
      expect(
        pairs,
        equals({
          (from: 'VES', to: 'USD'),
          (from: 'EUR', to: 'USD'),
        }),
      );
    });

    test('dual(EUR, ARS) preferred=EUR with no extra accounts → ARS pair', () {
      final pairs = RateRefreshService.derivePairsToRefresh(
        policy: const DualMode(primary: 'EUR', secondary: 'ARS'),
        preferredCurrency: 'EUR',
        accountCurrencies: const ['EUR', 'ARS'],
      );
      expect(pairs, equals({(from: 'ARS', to: 'EUR')}));
    });

    test('dual(EUR, GBP) preferred=EUR with USD account → GBP + USD', () {
      final pairs = RateRefreshService.derivePairsToRefresh(
        policy: const DualMode(primary: 'EUR', secondary: 'GBP'),
        preferredCurrency: 'EUR',
        accountCurrencies: const ['EUR', 'GBP', 'USD'],
      );
      expect(
        pairs,
        equals({
          (from: 'GBP', to: 'EUR'),
          (from: 'USD', to: 'EUR'),
        }),
      );
    });

    test('lowercase account codes uppercased', () {
      final pairs = RateRefreshService.derivePairsToRefresh(
        policy: const SingleMode(code: 'USD'),
        preferredCurrency: 'USD',
        accountCurrencies: const ['eur', 'jpy'],
      );
      expect(
        pairs,
        equals({
          (from: 'EUR', to: 'USD'),
          (from: 'JPY', to: 'USD'),
        }),
      );
    });

    test('duplicate account codes deduplicated', () {
      final pairs = RateRefreshService.derivePairsToRefresh(
        policy: const SingleMode(code: 'USD'),
        preferredCurrency: 'USD',
        accountCurrencies: const ['EUR', 'EUR', 'eur'],
      );
      expect(pairs, equals({(from: 'EUR', to: 'USD')}));
    });
  });
}
