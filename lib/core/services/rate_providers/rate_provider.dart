import 'package:flutter/foundation.dart';

@immutable
class RateResult {
  final double rate;
  final DateTime fetchedAt;
  final String providerName;
  final String source; // 'bcv' | 'paralelo'

  const RateResult({
    required this.rate,
    required this.fetchedAt,
    required this.providerName,
    required this.source,
  });
}

abstract class RateProvider {
  String get name;
  bool get supportsHistorical;

  /// `source` is 'bcv' or 'paralelo'.
  /// `currencyCode` is 'USD' or 'EUR'.
  /// Returns null if rate cannot be fetched (network error, no data, etc).
  Future<RateResult?> fetchRate({
    required DateTime date,
    required String source,
    String currencyCode = 'USD',
  });
}
