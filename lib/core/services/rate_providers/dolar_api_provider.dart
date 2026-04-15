import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:wallex/core/services/rate_providers/rate_provider.dart';

/// RateProvider implementation using ve.dolarapi.com.
/// Only supports today's rate (no historical data).
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
  }) async {
    // This API only serves today's rate
    if (!DateUtils.isSameDay(date, DateTime.now())) {
      return null;
    }

    final String endpoint;
    switch (source) {
      case 'bcv':
        endpoint = '$_baseUrl/dolares/oficial';
        break;
      case 'paralelo':
        endpoint = '$_baseUrl/dolares/paralelo';
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
