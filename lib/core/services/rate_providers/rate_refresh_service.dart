import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bolsio/core/database/app_db.dart';
import 'package:bolsio/core/database/services/account/account_service.dart';
import 'package:bolsio/core/database/services/exchange-rate/exchange_rate_service.dart';
import 'package:bolsio/core/database/services/user-setting/user_setting_service.dart';
import 'package:bolsio/core/models/currency/currency_display_policy.dart';
import 'package:bolsio/core/models/currency/currency_display_policy_resolver.dart';
import 'package:bolsio/core/services/dolar_api_service.dart';
import 'package:bolsio/core/services/rate_providers/frankfurter_provider.dart';
import 'package:bolsio/core/services/rate_providers/rate_provider_chain.dart';
import 'package:bolsio/core/services/rate_providers/rate_provider_manager.dart';
import 'package:bolsio/core/services/rate_providers/rate_source.dart';

/// Result summary of a rate-refresh cycle.
class RateRefreshResult {
  final int usdSuccessCount;
  final int usdFailureCount;
  final int eurSuccessCount;
  final int eurFailureCount;
  final int frankfurterSuccessCount;
  final int frankfurterFailureCount;
  final bool gateUpdated;

  const RateRefreshResult({
    required this.usdSuccessCount,
    required this.usdFailureCount,
    required this.eurSuccessCount,
    required this.eurFailureCount,
    this.frankfurterSuccessCount = 0,
    this.frankfurterFailureCount = 0,
    required this.gateUpdated,
  });

  int get totalSuccess =>
      usdSuccessCount + eurSuccessCount + frankfurterSuccessCount;
  int get totalFailure =>
      usdFailureCount + eurFailureCount + frankfurterFailureCount;
}

/// Service wrapping the rate auto-update job so it can be invoked from both
/// the cold-start path (with a 12h cooldown gate) and a manual UI "refresh now"
/// button (no gate).
///
/// Phase 4.5 / 4.6 of `currency-modes-rework`:
///
/// - The refresher derives its pair set from the active
///   [CurrencyDisplayPolicy] (NOT a hardcoded `['bcv', 'paralelo']` for
///   USD/EUR).
/// - For the canonical `dual(USD, VES)` mode the legacy DolarApi BCV +
///   Paralelo path stays in place — this is what 99% of beta users will
///   hit and the existing pipeline is battle-tested.
/// - For non-VES dual modes (e.g. `dual(EUR, GBP)`) and `single_other`
///   modes that have foreign-currency accounts, the refresher invokes
///   [RateProviderChain.fetchRate] for each derived pair, which routes
///   through Frankfurter for fiat-fiat or manual for crypto.
/// - The 24h scheduler tick is implemented as an explicit
///   [maybeRunDailyTick] entry point: callers (typically the app's
///   resumed lifecycle hook) invoke it, and the service skips when the
///   last successful run is younger than the 24h window. No timers, no
///   isolates — keeps it simple for the 3-beta scope.
class RateRefreshService {
  RateRefreshService._();
  static final RateRefreshService instance = RateRefreshService._();

  static const String _gateKey = 'last_currency_auto_update_v4';
  static const String _dailyTickGateKey = 'rate_refresh_last_daily_tick';
  static const List<String> _vesSources = ['bcv', 'paralelo'];

  /// 24h minimum window between automatic refreshes triggered by
  /// [maybeRunDailyTick]. Manual refreshes always bypass this.
  static const Duration _dailyTickInterval = Duration(hours: 24);

  /// Force-refresh rates immediately, bypassing the 12h cooldown gate.
  Future<RateRefreshResult> refreshNow({bool clearGate = true}) async {
    if (clearGate) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_gateKey);
      debugPrint('[RateRefresh] Gate cleared by manual refresh');
    }
    return _runJob(bypassGate: true);
  }

  /// Run the auto-update job with the 12h cooldown gate honored.
  Future<RateRefreshResult> runWithGate() async {
    final prefs = await SharedPreferences.getInstance();
    final lastUpdateStr = prefs.getString(_gateKey);
    final now = DateTime.now();

    final preferredCurrency =
        appStateSettings[SettingKey.preferredCurrency] ?? 'USD';

    bool forceUpdate = false;
    if (preferredCurrency != 'VES') {
      final db = AppDB.instance;
      final vesRates = await db.customSelect(
        "SELECT COUNT(*) AS cnt FROM exchangeRates WHERE currencyCode = 'VES'",
      ).getSingle();
      final vesCount = vesRates.read<int>('cnt');
      if (vesCount == 0) {
        forceUpdate = true;
        debugPrint('[RateRefresh] No VES exchange rates found — forcing update');
      }
    }

    if (lastUpdateStr != null) {
      final lastUpdate = DateTime.tryParse(lastUpdateStr);
      if (lastUpdate != null) {
        final deltaHours = now.difference(lastUpdate).inHours;
        final deltaMinutes = now.difference(lastUpdate).inMinutes;
        final willSkip = !forceUpdate && deltaHours < 12;
        debugPrint(
          '[RateRefresh][gate] last=$lastUpdateStr '
          'delta=${deltaHours}h${deltaMinutes % 60}m '
          'forceUpdate=$forceUpdate decision=${willSkip ? "SKIP" : "RUN"}',
        );
        if (willSkip) {
          return const RateRefreshResult(
            usdSuccessCount: 0,
            usdFailureCount: 0,
            eurSuccessCount: 0,
            eurFailureCount: 0,
            gateUpdated: false,
          );
        }
      }
    } else {
      debugPrint(
        '[RateRefresh][gate] last=<null> forceUpdate=$forceUpdate decision=RUN',
      );
    }

    return _runJob(bypassGate: false);
  }

  /// Phase 4.6 — 24h scheduler tick. Designed to be invoked from the app's
  /// `AppLifecycleState.resumed` hook (no background isolate). Skips when
  /// the last successful run is younger than [_dailyTickInterval]. Pairs
  /// are derived from the active policy via [_derivePairsToRefresh] so
  /// non-VES users get their own pairs refreshed too.
  Future<RateRefreshResult?> maybeRunDailyTick() async {
    final prefs = await SharedPreferences.getInstance();
    final lastStr = prefs.getString(_dailyTickGateKey);
    final now = DateTime.now();
    if (lastStr != null) {
      final last = DateTime.tryParse(lastStr);
      if (last != null && now.difference(last) < _dailyTickInterval) {
        debugPrint(
          '[RateRefresh][daily] skipped — last=$lastStr delta='
          '${now.difference(last).inHours}h',
        );
        return null;
      }
    }
    final result = await _runJob(bypassGate: true);
    // Gate the daily tick only on a fully-successful run — partial
    // failures retry on the next foreground resume.
    if (result.totalFailure == 0 && result.totalSuccess > 0) {
      await prefs.setString(_dailyTickGateKey, now.toIso8601String());
    }
    return result;
  }

  /// Phase 4.5 — derive the pair set that needs refreshing from the
  /// active [CurrencyDisplayPolicy] plus any foreign-currency account
  /// the user has.
  ///
  /// Returns a set of pairs `(from, to)` where `from` is the foreign
  /// currency and `to` is the storage base (preferred currency). Visible
  /// for testing.
  @visibleForTesting
  static Set<({String from, String to})> derivePairsToRefresh({
    required CurrencyDisplayPolicy policy,
    required String preferredCurrency,
    required Iterable<String> accountCurrencies,
  }) {
    final pairs = <({String from, String to})>{};
    final base = preferredCurrency.toUpperCase();

    // Policy-driven pairs.
    if (policy is DualMode) {
      final p = policy.primary.toUpperCase();
      final s = policy.secondary.toUpperCase();
      if (p != base) pairs.add((from: p, to: base));
      if (s != base) pairs.add((from: s, to: base));
    } else if (policy is SingleMode) {
      final c = policy.code.toUpperCase();
      if (c != base) pairs.add((from: c, to: base));
    }

    // Account-driven pairs — every non-base account currency gets a pair
    // even if the user is on a single mode (the equivalence may be hidden
    // but the underlying account balances still need a rate to convert).
    for (final acc in accountCurrencies) {
      final code = acc.toUpperCase();
      if (code != base) pairs.add((from: code, to: base));
    }
    return pairs;
  }

  Future<RateRefreshResult> _runJob({required bool bypassGate}) async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    final preferredCurrency =
        appStateSettings[SettingKey.preferredCurrency] ?? 'USD';

    // ── Resolve which pairs to refresh ─────────────────────────────────
    final policy = await CurrencyDisplayPolicyResolver.instance.watch().first;
    final accountCurrencies = await _accountCurrencyCodes();
    final pairs = derivePairsToRefresh(
      policy: policy,
      preferredCurrency: preferredCurrency,
      accountCurrencies: accountCurrencies,
    );

    // For the canonical USD↔VES path we keep using DolarApi (BCV +
    // Paralelo) — that's what the legacy rate gate tracks and it's what
    // the dashboard chip surfaces. Other pairs go through Frankfurter
    // via [RateProviderChain].
    final involvesVes =
        preferredCurrency == 'VES' || pairs.any((p) => p.from == 'VES');
    final hasUsdVesPair = preferredCurrency == 'VES' ||
        pairs.any((p) => p.from == 'USD' || p.from == 'VES');
    final hasEurVesPair = pairs.any((p) => p.from == 'EUR');

    final Map<String, bool> usdRateSuccess = {
      for (final s in _vesSources) s: false,
    };
    int eurSuccessCount = 0;
    int eurFailureCount = 0;
    int frankfurterSuccessCount = 0;
    int frankfurterFailureCount = 0;

    if (preferredCurrency == 'USD') {
      await ExchangeRateService.instance.deleteExchangeRates(
        currencyCode: 'USD',
      );
    }

    // ── DolarApi-driven pairs (USD↔VES, EUR↔VES) ───────────────────────
    if (involvesVes && hasUsdVesPair) {
      for (final source in _vesSources) {
        await Future<void>.delayed(Duration.zero);
        try {
          final result = await RateProviderManager.instance.fetchRate(
            date: now,
            source: source,
          );
          if (result != null) {
            final String storeCurrencyCode;
            final double storeRate;
            if (preferredCurrency == 'VES') {
              storeCurrencyCode = 'USD';
              storeRate = result.rate;
            } else {
              storeCurrencyCode = 'VES';
              storeRate = 1.0 / result.rate;
            }
            await ExchangeRateService.instance
                .insertOrUpdateExchangeRateWithSource(
                  currencyCode: storeCurrencyCode,
                  date: now,
                  rate: storeRate,
                  source: source,
                );
            debugPrint(
              '[init] RateProvider ${source.toUpperCase()}: $storeRate '
              '$storeCurrencyCode via ${result.providerName}',
            );
            usdRateSuccess[source] = true;
          } else {
            debugPrint(
              '[init] RateProvider ${source.toUpperCase()}: FAILED (null result)',
            );
          }
        } catch (e) {
          debugPrint('[init] RateProvider ${source.toUpperCase()}: ERROR $e');
        }
      }
    }

    if (involvesVes && hasEurVesPair) {
      for (final source in _vesSources) {
        await Future<void>.delayed(Duration.zero);
        try {
          final result = await RateProviderManager.instance.fetchRate(
            date: now,
            source: source,
            currencyCode: 'EUR',
          );
          if (result != null) {
            const String storeCurrencyCode = 'EUR';
            double storeRate;
            if (preferredCurrency == 'VES') {
              storeRate = result.rate;
            } else {
              final usdResult = await RateProviderManager.instance.fetchRate(
                date: now,
                source: source,
              );
              if (usdResult != null && usdResult.rate > 0) {
                storeRate = result.rate / usdResult.rate;
              } else {
                storeRate = result.rate;
              }
            }
            await ExchangeRateService.instance
                .insertOrUpdateExchangeRateWithSource(
                  currencyCode: storeCurrencyCode,
                  date: now,
                  rate: storeRate,
                  source: source,
                );
            await Future<void>.delayed(Duration.zero);
            debugPrint(
              '[init] RateProvider EUR ${source.toUpperCase()}: $storeRate '
              '$storeCurrencyCode via ${result.providerName}',
            );
            eurSuccessCount++;
          } else {
            debugPrint(
              '[init] RateProvider EUR ${source.toUpperCase()}: FAILED (null result)',
            );
            eurFailureCount++;
          }
        } catch (e) {
          debugPrint(
            '[init] RateProvider EUR ${source.toUpperCase()}: ERROR $e',
          );
          eurFailureCount++;
        }
      }
    }

    // ── Frankfurter-driven pairs (non-VES fiat-fiat) ───────────────────
    final preferredVesSource = RateSource.fromDb(
      appStateSettings[SettingKey.preferredRateSource],
    );
    final foreignFiatPairs = pairs.where(
      (p) =>
          p.from != 'USD' &&
          p.from != 'EUR' &&
          p.from != 'VES' &&
          FrankfurterRateProvider.supportsPair(p.from, p.to),
    );
    for (final pair in foreignFiatPairs) {
      await Future<void>.delayed(Duration.zero);
      try {
        final result = await RateProviderChain.instance.fetchRate(
          from: pair.from,
          to: pair.to,
          date: now,
          preferredVesSource: preferredVesSource,
          force: bypassGate,
        );
        if (result != null) {
          frankfurterSuccessCount++;
          debugPrint(
            '[init] Frankfurter ${pair.from}->${pair.to}: ${result.rate}',
          );
        } else {
          frankfurterFailureCount++;
          debugPrint('[init] Frankfurter ${pair.from}->${pair.to}: FAILED');
        }
      } catch (e) {
        frankfurterFailureCount++;
        debugPrint('[init] Frankfurter ${pair.from}->${pair.to}: ERROR $e');
      }
    }

    // Legacy DolarApi cache (best-effort; used by some callers).
    try {
      await DolarApiService.instance.fetchAllRates();
    } catch (_) {}

    final usdSuccessCount = usdRateSuccess.values.where((v) => v).length;
    final usdFailureCount = usdRateSuccess.length - usdSuccessCount;
    final allUsdSucceeded = usdFailureCount == 0;

    bool gateUpdated = false;
    if (allUsdSucceeded && involvesVes && hasUsdVesPair) {
      await prefs.setString(_gateKey, now.toIso8601String());
      gateUpdated = true;
      debugPrint(
        '[init] Rate gate updated (all USD rates persisted: $usdRateSuccess)',
      );
    } else if (!involvesVes) {
      // Pure non-VES users — gate flips on Frankfurter success.
      if (frankfurterFailureCount == 0 && frankfurterSuccessCount > 0) {
        await prefs.setString(_gateKey, now.toIso8601String());
        gateUpdated = true;
      }
    } else {
      debugPrint(
        '[init] Rate gate NOT updated (partial failures: $usdRateSuccess); '
        'next ${bypassGate ? "manual refresh" : "cold start"} will retry',
      );
    }

    return RateRefreshResult(
      usdSuccessCount: usdSuccessCount,
      usdFailureCount: usdFailureCount,
      eurSuccessCount: eurSuccessCount,
      eurFailureCount: eurFailureCount,
      frankfurterSuccessCount: frankfurterSuccessCount,
      frankfurterFailureCount: frankfurterFailureCount,
      gateUpdated: gateUpdated,
    );
  }

  Future<List<String>> _accountCurrencyCodes() async {
    try {
      final accounts = await AccountService.instance
          .getAccounts(predicate: (acc, curr) => acc.closingDate.isNull())
          .first;
      final codes = <String>{
        for (final a in accounts) a.currencyId.toUpperCase(),
      };
      return codes.toList(growable: false);
    } catch (e) {
      debugPrint('[RateRefresh] failed to read account currencies: $e');
      return const <String>[];
    }
  }
}
