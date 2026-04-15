import 'package:flutter/material.dart';

import 'package:wallex/core/services/rate_providers/rate_provider.dart';
import 'package:wallex/core/services/rate_providers/dolar_api_provider.dart';
import 'package:wallex/core/services/rate_providers/pydolar_vzla_provider.dart';

/// Manages a fallback chain of rate providers.
///
/// - For today's rate: DolarApi first (faster, more reliable for current day),
///   PyDolarVzla as fallback.
/// - For historical rate: PyDolarVzla first (only one that supports it).
class RateProviderManager {
  static final RateProviderManager instance = RateProviderManager._();
  RateProviderManager._();

  final List<RateProvider> _providers = [
    DolarApiProvider(),
    PyDolarVzlaProvider(),
  ];

  /// Fetch a rate with automatic fallback through the provider chain.
  ///
  /// [date] - the date for which to fetch the rate.
  /// [source] - 'bcv' or 'paralelo'.
  Future<RateResult?> fetchRate({
    required DateTime date,
    required String source,
  }) async {
    final isToday = DateUtils.isSameDay(date, DateTime.now());
    final ordered = isToday
        ? _providers
        : _providers.where((p) => p.supportsHistorical).toList();

    for (final p in ordered) {
      try {
        final r = await p.fetchRate(date: date, source: source);
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
