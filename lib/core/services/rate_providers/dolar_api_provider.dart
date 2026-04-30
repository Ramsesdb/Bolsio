import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:kilatex/core/services/rate_providers/rate_provider.dart';

/// RateProvider implementation using ve.dolarapi.com.
/// Only supports today's rate (no historical data).
///
/// As of 2026-04, this is the only working public Venezuelan rate API.
/// ve.dolarapi.com /oficial and /paralelo return HTTP 200 with current BCV and
/// parallel market rates. The /historico endpoint returns 404 and query params
/// like ?fecha= are silently ignored (always returns today's rate).
/// Historical rates therefore depend on local accumulation in the
/// exchangeRates table — each app start fetches today's rates, building
/// local history over time.
class DolarApiProvider extends RateProvider {
  static const String _baseUrl = 'https://ve.dolarapi.com/v1';

  @override
  String get name => 'DolarApi';

  @override
  bool get supportsHistorical => false;

  @override
  Future<RateResult?> fetchRate({
    required DateTime date,
    required String source,
    String currencyCode = 'USD',
  }) async {
    // This API only serves today's rate
    if (!DateUtils.isSameDay(date, DateTime.now())) {
      return null;
    }

    final currencyPath = currencyCode == 'EUR' ? 'euros' : 'dolares';
    final String endpoint;
    switch (source) {
      case 'bcv':
        endpoint = '$_baseUrl/$currencyPath/oficial';
        break;
      case 'paralelo':
        endpoint = '$_baseUrl/$currencyPath/paralelo';
        break;
      default:
        return null;
    }

    try {
      final response = await http
          .get(
            Uri.parse(endpoint),
            headers: {'Accept': 'application/json'},
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final promedio = (json['promedio'] as num?)?.toDouble();

        if (promedio == null || promedio <= 0) return null;

        return RateResult(
          rate: promedio,
          fetchedAt: DateTime.now(),
          providerName: name,
          source: source,
        );
      }
    } catch (e) {
      debugPrint('[DolarApiProvider] Error fetching $source rate: $e');
    }

    return null;
  }
}
