/// Exception thrown when the Binance API returns an error response.
class BinanceApiException implements Exception {
  /// Binance error code (e.g. -2014 for invalid API key format).
  final int code;

  /// Binance error message.
  final String message;

  const BinanceApiException({required this.code, required this.message});

  @override
  String toString() => 'BinanceApiException(code: $code, msg: $message)';
}
