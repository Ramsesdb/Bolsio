import 'dart:convert';
import 'dart:developer' as developer;

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import 'binance_api_exception.dart';
import 'binance_credentials_store.dart';

/// HTTP client for Binance REST API with HMAC-SHA256 request signing.
///
/// Handles:
/// - Server time synchronization (to compensate for device clock drift).
/// - Signed requests with `X-MBX-APIKEY` header.
/// - Error mapping to [BinanceApiException].
/// - Exponential backoff on 429 (rate limit) responses, up to 3 retries.
class BinanceApiClient {
  final String _baseUrl;
  final BinanceCredentialsStore _credentialsStore;
  final http.Client _http;

  /// Difference in milliseconds: `serverTime - deviceTime`.
  /// Applied to every signed request timestamp.
  int? _serverTimeOffsetMs;

  BinanceApiClient({
    BinanceCredentialsStore? credentialsStore,
    http.Client? httpClient,
    String baseUrl = 'https://api.binance.com',
  })  : _credentialsStore = credentialsStore ?? BinanceCredentialsStore.instance,
        _http = httpClient ?? http.Client(),
        _baseUrl = baseUrl;

  // ─── Public endpoints ───────────────────────────────────────────

  /// C2C / P2P order history.
  ///
  /// Returns a list of order maps. Key fields: `orderNumber`, `tradeType`,
  /// `asset`, `fiat`, `amount`, `totalPrice`, `unitPrice`,
  /// `counterPartNickName`, `createTime`, `orderStatus`.
  Future<List<Map<String, dynamic>>> getC2cOrderHistory({
    DateTime? since,
    int rows = 100,
  }) async {
    final params = <String, String>{
      'rows': rows.toString(),
    };
    if (since != null) {
      params['startTimestamp'] = since.millisecondsSinceEpoch.toString();
    }
    final resp = await _signedGet('/sapi/v1/c2c/orderMatch/listUserOrderHistory', params);
    return List<Map<String, dynamic>>.from(resp['data'] ?? []);
  }

  /// Fiat deposit/withdraw orders.
  ///
  /// [transactionType]: `'0'` for deposits, `'1'` for withdrawals.
  Future<List<Map<String, dynamic>>> getFiatOrders({
    DateTime? since,
    String transactionType = '0',
  }) async {
    final params = <String, String>{
      'transactionType': transactionType,
    };
    if (since != null) {
      params['beginTime'] = since.millisecondsSinceEpoch.toString();
    }
    final resp = await _signedGet('/sapi/v1/fiat/orders', params);
    return List<Map<String, dynamic>>.from(resp['data'] ?? []);
  }

  /// Fiat payment orders (card purchases of crypto).
  ///
  /// [transactionType]: `'0'` for buy, `'1'` for sell.
  Future<List<Map<String, dynamic>>> getFiatPayments({
    DateTime? since,
    String transactionType = '0',
  }) async {
    final params = <String, String>{
      'transactionType': transactionType,
    };
    if (since != null) {
      params['beginTime'] = since.millisecondsSinceEpoch.toString();
    }
    final resp = await _signedGet('/sapi/v1/fiat/payments', params);
    return List<Map<String, dynamic>>.from(resp['data'] ?? []);
  }

  /// Binance Pay transaction history.
  Future<List<Map<String, dynamic>>> getPayTransactions({
    DateTime? since,
  }) async {
    final params = <String, String>{};
    if (since != null) {
      params['startTime'] = since.millisecondsSinceEpoch.toString();
    }
    final resp = await _signedGet('/sapi/v1/pay/transactions', params);
    return List<Map<String, dynamic>>.from(resp['data'] ?? []);
  }

  /// Capital deposit history (crypto deposits).
  Future<List<Map<String, dynamic>>> getCapitalDeposits({
    DateTime? since,
  }) async {
    final params = <String, String>{};
    if (since != null) {
      params['startTime'] = since.millisecondsSinceEpoch.toString();
    }
    final resp = await _signedGet('/sapi/v1/capital/deposit/hisrec', params);
    // This endpoint returns a direct list, not wrapped in { "data": [...] }
    if (resp.containsKey('_list')) {
      return List<Map<String, dynamic>>.from(resp['_list']);
    }
    return [];
  }

  /// Capital withdrawal history (crypto withdrawals).
  Future<List<Map<String, dynamic>>> getCapitalWithdrawals({
    DateTime? since,
  }) async {
    final params = <String, String>{};
    if (since != null) {
      params['startTime'] = since.millisecondsSinceEpoch.toString();
    }
    final resp = await _signedGet('/sapi/v1/capital/withdraw/history', params);
    // This endpoint returns a direct list, not wrapped in { "data": [...] }
    if (resp.containsKey('_list')) {
      return List<Map<String, dynamic>>.from(resp['_list']);
    }
    return [];
  }

  /// Spot account balances.
  Future<Map<String, dynamic>> getSpotAccount() async {
    return _signedGet('/api/v3/account', {});
  }

  /// Funding wallet asset balances.
  Future<List<Map<String, dynamic>>> getFundingAsset() async {
    final resp = await _signedPost('/sapi/v1/asset/get-funding-asset', {});
    if (resp.containsKey('_list')) {
      return List<Map<String, dynamic>>.from(resp['_list']);
    }
    return [];
  }

  /// Get latest asset price quoted in USDT from public ticker endpoint.
  ///
  /// Returns `null` when the symbol is not tradable against USDT or when
  /// Binance does not return a valid price.
  Future<double?> getAssetPriceInUsdt(String asset) async {
    final upperAsset = asset.toUpperCase();
    final symbol = '${upperAsset}USDT';
    final uri = Uri.parse('$_baseUrl/api/v3/ticker/price?symbol=$symbol');

    try {
      final response = await _http.get(uri);
      if (response.statusCode != 200) {
        return null;
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final price = double.tryParse('${data['price']}');
      return price;
    } catch (_) {
      return null;
    }
  }

  // ─── Server time sync ──────────────────────────────────────────

  /// Synchronize with Binance server clock.
  ///
  /// Must be called once before making signed requests to compensate for
  /// device clock drift. The offset is cached for the session.
  Future<void> syncServerTime() async {
    final uri = Uri.parse('$_baseUrl/api/v3/time');
    final response = await _http.get(uri);
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final serverTime = data['serverTime'] as int;
      _serverTimeOffsetMs = serverTime - DateTime.now().millisecondsSinceEpoch;
      developer.log(
        'Binance server time offset: ${_serverTimeOffsetMs}ms',
        name: 'BinanceApiClient',
      );
    } else {
      developer.log(
        'Failed to sync server time: ${response.statusCode}',
        name: 'BinanceApiClient',
      );
      _serverTimeOffsetMs = 0;
    }
  }

  // ─── Signing ───────────────────────────────────────────────────

  /// Compute HMAC-SHA256 signature of [queryString] using [secret].
  ///
  /// Returns lowercase hex string (64 chars).
  static String sign(String queryString, String secret) {
    final hmacSha256 = Hmac(sha256, utf8.encode(secret));
    final digest = hmacSha256.convert(utf8.encode(queryString));
    return digest.toString();
  }

  // ─── Internal HTTP helpers ─────────────────────────────────────

  Future<Map<String, dynamic>> _signedGet(
    String path,
    Map<String, String> params,
  ) async {
    final creds = await _credentialsStore.load();
    if (creds == null) {
      throw const BinanceApiException(
        code: -1,
        message: 'No Binance credentials configured',
      );
    }

    final timestamp =
        DateTime.now().millisecondsSinceEpoch + (_serverTimeOffsetMs ?? 0);
    params['timestamp'] = timestamp.toString();
    params['recvWindow'] = '5000';

    final queryString =
        params.entries.map((e) => '${e.key}=${e.value}').join('&');
    final signature = sign(queryString, creds.apiSecret);
    final fullQuery = '$queryString&signature=$signature';

    final uri = Uri.parse('$_baseUrl$path?$fullQuery');

    return _executeWithRetry(
      () => _http.get(uri, headers: {'X-MBX-APIKEY': creds.apiKey}),
    );
  }

  Future<Map<String, dynamic>> _signedPost(
    String path,
    Map<String, String> params,
  ) async {
    final creds = await _credentialsStore.load();
    if (creds == null) {
      throw const BinanceApiException(
        code: -1,
        message: 'No Binance credentials configured',
      );
    }

    final timestamp =
        DateTime.now().millisecondsSinceEpoch + (_serverTimeOffsetMs ?? 0);
    params['timestamp'] = timestamp.toString();
    params['recvWindow'] = '5000';

    final queryString =
        params.entries.map((e) => '${e.key}=${e.value}').join('&');
    final signature = sign(queryString, creds.apiSecret);

    final uri = Uri.parse('$_baseUrl$path');

    return _executeWithRetry(
      () => _http.post(
        uri,
        headers: {'X-MBX-APIKEY': creds.apiKey},
        body: '$queryString&signature=$signature',
      ),
    );
  }

  /// Execute an HTTP request with exponential backoff on 429 responses.
  Future<Map<String, dynamic>> _executeWithRetry(
    Future<http.Response> Function() request, {
    int maxRetries = 3,
  }) async {
    int attempt = 0;
    while (true) {
      final response = await request();
      if (response.statusCode == 200) {
        return _parseResponse(response.body);
      }

      if (response.statusCode == 429 && attempt < maxRetries) {
        attempt++;
        final delay = Duration(seconds: 1 << attempt); // 2s, 4s, 8s
        developer.log(
          'Rate limited (429), retrying in ${delay.inSeconds}s (attempt $attempt/$maxRetries)',
          name: 'BinanceApiClient',
        );
        await Future.delayed(delay);
        continue;
      }

      // Parse error body
      final Map<String, dynamic> errorBody;
      try {
        errorBody = jsonDecode(response.body) as Map<String, dynamic>;
      } catch (_) {
        throw BinanceApiException(
          code: response.statusCode,
          message: 'HTTP ${response.statusCode}: ${response.body}',
        );
      }

      final code = errorBody['code'] as int? ?? response.statusCode;
      final msg = errorBody['msg'] as String? ?? response.body;

      if (response.statusCode == 401 || response.statusCode == 403) {
        throw BinanceApiException(
          code: code,
          message: 'Authentication failed ($code): $msg',
        );
      }

      throw BinanceApiException(code: code, message: msg);
    }
  }

  /// Parse a response body that may be a JSON object or a JSON array.
  ///
  /// If the body is a list (e.g. from capital/deposit), it is wrapped in
  /// `{'_list': [...]}` so all callers can expect a Map.
  Map<String, dynamic> _parseResponse(String body) {
    final decoded = jsonDecode(body);
    if (decoded is List) {
      return {'_list': decoded};
    }
    return decoded as Map<String, dynamic>;
  }
}
