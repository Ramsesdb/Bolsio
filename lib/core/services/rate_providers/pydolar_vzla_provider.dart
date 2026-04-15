import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:wallex/core/services/rate_providers/rate_provider.dart';

/// RateProvider implementation using pydolarvenezuela-api.vercel.app.
/// Supports both current and historical rates.
class PyDolarVzlaProvider extends RateProvider {
  static const String _baseUrl =
      'https://pydolarvenezuela-api.vercel.app/api/v1';

  @override
  String get name => 'PyDolarVzla';

  @override
  bool get supportsHistorical => true;

  /// Maps our source names to pydolarvenezuela monitor names
  String? _monitorForSource(String source) {
    switch (source) {
      case 'bcv':
        return 'bcv';
      case 'paralelo':
        return 'enparalelovzla';
      default:
        return null;
    }
  }

  @override
  Future<RateResult?> fetchRate({
    required DateTime date,
    required String source,
  }) async {
    final monitor = _monitorForSource(source);
    if (monitor == null) return null;

    final isToday = DateUtils.isSameDay(date, DateTime.now());

    try {
      if (isToday) {
        return await _fetchCurrentRate(monitor: monitor, source: source);
      } else {
        return await _fetchHistoricalRate(
          monitor: monitor,
          source: source,
          date: date,
        );
      }
    } catch (e) {
      debugPrint('[PyDolarVzlaProvider] Error fetching $source rate: $e');
      return null;
    }
  }

  Future<RateResult?> _fetchCurrentRate({
    required String monitor,
    required String source,
  }) async {
    // TODO: verify endpoint with actual API docs once available
    // Likely: /api/v1/dollar?monitor=bcv or /api/v1/dollar?page=bcv
    final uri = Uri.parse('$_baseUrl/dollar').replace(
      queryParameters: {'monitor': monitor},
    );

    final response = await http
        .get(uri, headers: {'Accept': 'application/json'})
        .timeout(const Duration(seconds: 10));

    if (response.statusCode == 200) {
      final json = jsonDecode(response.body);
      return _parseRate(json, source);
    }

    return null;
  }

  Future<RateResult?> _fetchHistoricalRate({
    required String monitor,
    required String source,
    required DateTime date,
  }) async {
    // TODO: verify endpoint with actual API docs once available
    final dateStr =
        '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    final uri = Uri.parse('$_baseUrl/dollar/history').replace(
      queryParameters: {
        'monitor': monitor,
        'start_date': dateStr,
        'end_date': dateStr,
      },
    );

    final response = await http
        .get(uri, headers: {'Accept': 'application/json'})
        .timeout(const Duration(seconds: 10));

    if (response.statusCode == 200) {
      final json = jsonDecode(response.body);
      return _parseRate(json, source);
    }

    return null;
  }

  /// Attempt to parse a rate from the JSON response.
  /// The API response structure may vary; we try multiple common shapes.
  RateResult? _parseRate(dynamic json, String source) {
    double? rate;

    if (json is Map<String, dynamic>) {
      // Try direct price field
      rate ??= (json['price'] as num?)?.toDouble();
      // Try promedio field
      rate ??= (json['promedio'] as num?)?.toDouble();

      // Nested under 'data' or 'result'
      final nested = json['data'] ?? json['result'];
      if (nested is Map<String, dynamic>) {
        rate ??= (nested['price'] as num?)?.toDouble();
        rate ??= (nested['promedio'] as num?)?.toDouble();
      }

      // History response might be a list under 'history' or 'data'
      final historyList = json['history'] ?? json['data'];
      if (historyList is List && historyList.isNotEmpty) {
        final first = historyList.first;
        if (first is Map<String, dynamic>) {
          rate ??= (first['price'] as num?)?.toDouble();
          rate ??= (first['promedio'] as num?)?.toDouble();
        }
      }
    }

    if (rate == null || rate <= 0) return null;

    return RateResult(
      rate: rate,
      fetchedAt: DateTime.now(),
      providerName: name,
      source: source,
    );
  }
}
