import 'package:flutter_test/flutter_test.dart';
import 'package:bolsio/core/services/rate_providers/rate_provider_chain.dart';
import 'package:bolsio/core/services/rate_providers/rate_source.dart';

/// Unit tests for [RateProviderChain] dispatch decisions.
///
/// Covers the pure-function decision logic — the actual I/O paths
/// (Frankfurter network, manual DB read) are exercised in
/// `frankfurter_provider_test.dart` and via integration tests; here we
/// only verify the routing tree, which is the load-bearing logic of
/// Phase 4.5 (fallback chain) and Phase 4.6 (crypto → manual default).
void main() {
  group('RateProviderChain.sourceForPair', () {
    test('identity returns null (no conversion needed)', () {
      expect(
        RateProviderChain.sourceForPair(from: 'USD', to: 'USD'),
        isNull,
      );
      expect(
        RateProviderChain.sourceForPair(from: 'BTC', to: 'BTC'),
        isNull,
      );
    });

    test('USD↔VES routes to BCV by default (no preference)', () {
      expect(
        RateProviderChain.sourceForPair(from: 'USD', to: 'VES'),
        RateSource.bcv,
      );
      expect(
        RateProviderChain.sourceForPair(from: 'VES', to: 'USD'),
        RateSource.bcv,
      );
    });

    test('USD↔VES respects preferredVesSource', () {
      expect(
        RateProviderChain.sourceForPair(
          from: 'USD',
          to: 'VES',
          preferredVesSource: RateSource.paralelo,
        ),
        RateSource.paralelo,
      );
    });

    test('VES paired with non-USD routes to manual', () {
      expect(
        RateProviderChain.sourceForPair(from: 'VES', to: 'EUR'),
        RateSource.manual,
      );
      expect(
        RateProviderChain.sourceForPair(from: 'BRL', to: 'VES'),
        RateSource.manual,
      );
    });

    test('fiat-fiat (non-VES) routes to auto_frankfurter', () {
      expect(
        RateProviderChain.sourceForPair(from: 'USD', to: 'EUR'),
        RateSource.autoFrankfurter,
      );
      expect(
        RateProviderChain.sourceForPair(from: 'EUR', to: 'GBP'),
        RateSource.autoFrankfurter,
      );
      expect(
        RateProviderChain.sourceForPair(from: 'JPY', to: 'CHF'),
        RateSource.autoFrankfurter,
      );
    });

    test('crypto pairs route to manual (Phase 4.6)', () {
      expect(
        RateProviderChain.sourceForPair(from: 'USD', to: 'BTC'),
        RateSource.manual,
      );
      expect(
        RateProviderChain.sourceForPair(from: 'BTC', to: 'USD'),
        RateSource.manual,
      );
      expect(
        RateProviderChain.sourceForPair(from: 'EUR', to: 'ETH'),
        RateSource.manual,
      );
    });

    test('unsupported LATAM fiat routes to manual', () {
      // ARS / COP / PEN are absent from Frankfurter → must NOT route auto.
      expect(
        RateProviderChain.sourceForPair(from: 'USD', to: 'ARS'),
        RateSource.manual,
      );
      expect(
        RateProviderChain.sourceForPair(from: 'EUR', to: 'COP'),
        RateSource.manual,
      );
    });

    test('case-insensitive', () {
      expect(
        RateProviderChain.sourceForPair(from: 'usd', to: 'eur'),
        RateSource.autoFrankfurter,
      );
      expect(
        RateProviderChain.sourceForPair(from: 'btc', to: 'usd'),
        RateSource.manual,
      );
    });
  });

  group('RateProviderChain.isCryptoOrUnsupported', () {
    test('crypto pairs are flagged unsupported', () {
      expect(
        RateProviderChain.isCryptoOrUnsupported('USD', 'BTC'),
        isTrue,
      );
      expect(
        RateProviderChain.isCryptoOrUnsupported('ETH', 'EUR'),
        isTrue,
      );
    });

    test('VES pairs are flagged unsupported (frankfurter does not cover it)',
        () {
      expect(
        RateProviderChain.isCryptoOrUnsupported('USD', 'VES'),
        isTrue,
      );
    });

    test('vanilla fiat pairs are supported', () {
      expect(
        RateProviderChain.isCryptoOrUnsupported('USD', 'EUR'),
        isFalse,
      );
      expect(
        RateProviderChain.isCryptoOrUnsupported('GBP', 'JPY'),
        isFalse,
      );
    });
  });
}
