import 'package:flutter/material.dart';

import 'package:bolsio/core/services/rate_providers/rate_provider.dart';
import 'package:bolsio/core/services/rate_providers/dolar_api_provider.dart';

/// Manages a fallback chain of rate providers.
///
/// Note: As of 2026-04, ve.dolarapi.com is the only working public Venezuelan
/// rate API. PyDolarVenezuela's hosted deployment (pydolarvenezuela-api.vercel.app)
/// returned DEPLOYMENT_NOT_FOUND when probed; the docs domain (docs.pydolarve.org)
/// also doesn't resolve. ve.dolarapi.com has no historical endpoint, so historical
/// rates depend on local accumulation in the exchangeRates table (each app start
/// fetches today's BCV + paralelo into the table — over time builds local history).
class RateProviderManager {
  static final RateProviderManager instance = RateProviderManager._();
  RateProviderManager._();

  final List<RateProvider> _providers = [
    DolarApiProvider(),
  ];

  /// Fetch a rate with automatic fallback through the provider chain.
  ///
  /// [date] - the date for which to fetch the rate.
  /// [source] - 'bcv' or 'paralelo'.
  /// [currencyCode] - 'USD' or 'EUR'.
  ///
  /// Returns `null` immediately for non-today dates because the only active
  /// provider (DolarApiProvider) does not support historical lookups.
  Future<RateResult?> fetchRate({
    required DateTime date,
    required String source,
    String currencyCode = 'USD',
  }) async {
    final isToday = DateUtils.isSameDay(date, DateTime.now());

    // No provider currently supports historical rates.
    // Return null early to avoid unnecessary network calls.
    if (!isToday) {
      debugPrint('[$_tag] No historical provider available; returning null for $date');
      return null;
    }

    for (final p in _providers) {
      try {
        final r = await p.fetchRate(date: date, source: source, currencyCode: currencyCode);
        if (r != null) return r;
      } catch (e) {
        debugPrint('[$_tag] ${p.name} failed: $e');
        // continue to next provider
      }
    }
    return null;
  }

  static const _tag = 'RateProviderManager';
}
