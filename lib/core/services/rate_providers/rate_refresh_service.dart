import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wallex/core/database/app_db.dart';
import 'package:wallex/core/database/services/exchange-rate/exchange_rate_service.dart';
import 'package:wallex/core/database/services/user-setting/user_setting_service.dart';
import 'package:wallex/core/services/dolar_api_service.dart';
import 'package:wallex/core/services/rate_providers/rate_provider_manager.dart';
import 'package:wallex/core/utils/uuid.dart';

/// Result summary of a rate-refresh cycle.
class RateRefreshResult {
  final int usdSuccessCount;
  final int usdFailureCount;
  final int eurSuccessCount;
  final int eurFailureCount;
  final bool gateUpdated;

  const RateRefreshResult({
    required this.usdSuccessCount,
    required this.usdFailureCount,
    required this.eurSuccessCount,
    required this.eurFailureCount,
    required this.gateUpdated,
  });

  int get totalSuccess => usdSuccessCount + eurSuccessCount;
  int get totalFailure => usdFailureCount + eurFailureCount;
}

/// Service wrapping the rate auto-update job so it can be invoked from both
/// the cold-start path (with a 12h cooldown gate) and a manual UI "refresh now"
/// button (no gate).
///
/// Mirrors the original `_checkAndAutoUpdateCurrencyRate` in `main.dart`.
class RateRefreshService {
  RateRefreshService._();
  static final RateRefreshService instance = RateRefreshService._();

  static const String _gateKey = 'last_currency_auto_update_v4';
  static const List<String> _sources = ['bcv', 'paralelo'];

  /// Force-refresh rates immediately, bypassing the 12h cooldown gate.
  ///
  /// Also clears the gate so callers can then invoke [runWithGate] and observe
  /// the update path cleanly on the next cold start if desired.
  Future<RateRefreshResult> refreshNow({bool clearGate = true}) async {
    if (clearGate) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_gateKey);
      debugPrint('[RateRefresh] Gate cleared by manual refresh');
    }
    return _runJob(bypassGate: true);
  }

  /// Run the auto-update job with the 12h cooldown gate honored.
  ///
  /// Used by the cold-start path in `main.dart`.
  Future<RateRefreshResult> runWithGate() async {
    final prefs = await SharedPreferences.getInstance();
    final lastUpdateStr = prefs.getString(_gateKey);
    final now = DateTime.now();

    final preferredCurrency =
        appStateSettings[SettingKey.preferredCurrency] ?? 'USD';

    // Task 2 (original): Force update if no VES rate exists yet.
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

    // Task 3: Diagnostic logging — cooldown state + decision.
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

  Future<RateRefreshResult> _runJob({required bool bypassGate}) async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    final preferredCurrency =
        appStateSettings[SettingKey.preferredCurrency] ?? 'USD';

    final Map<String, bool> usdRateSuccess = {
      for (final s in _sources) s: false,
    };
    int eurSuccessCount = 0;
    int eurFailureCount = 0;

    // Delete bad currencyCode='USD' rows when preferred currency is USD.
    if (preferredCurrency == 'USD') {
      await ExchangeRateService.instance.deleteExchangeRates(
        currencyCode: 'USD',
      );
    }

    for (final source in _sources) {
      // Yield between sources so the UI thread gets a chance to paint.
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

          // Yield between persistence steps to avoid long frame freezes.
          await Future<void>.delayed(Duration.zero);

          if (source == 'bcv') {
            await ExchangeRateService.instance.insertOrUpdateExchangeRate(
              ExchangeRateInDB(
                id: generateUUID(),
                date: now,
                currencyCode: storeCurrencyCode,
                exchangeRate: storeRate,
              ),
            );
            await Future<void>.delayed(Duration.zero);
          }

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

    // EUR rates
    for (final source in _sources) {
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
        debugPrint('[init] RateProvider EUR ${source.toUpperCase()}: ERROR $e');
        eurFailureCount++;
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
    if (allUsdSucceeded) {
      await prefs.setString(_gateKey, now.toIso8601String());
      gateUpdated = true;
      debugPrint(
        '[init] Rate gate updated (all USD rates persisted: $usdRateSuccess)',
      );
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
      gateUpdated: gateUpdated,
    );
  }
}
