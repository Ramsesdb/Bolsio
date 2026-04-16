import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Secure credential store for Binance API keys.
///
/// Uses [FlutterSecureStorage] which encrypts data at rest:
/// - Android: Android KeyStore via EncryptedSharedPreferences
/// - iOS: Keychain
///
/// Credentials are NEVER written to code, logs, or any non-encrypted storage.
class BinanceCredentialsStore {
  static final instance = BinanceCredentialsStore._();
  BinanceCredentialsStore._();

  /// Constructor for testing with a custom [FlutterSecureStorage] instance.
  BinanceCredentialsStore.forTesting(FlutterSecureStorage storage)
      : _storage = storage;

  FlutterSecureStorage _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static const _kApiKey = 'binance_api_key';
  static const _kApiSecret = 'binance_api_secret';

  // Removes whitespace and invisible unicode markers often introduced by copy/paste.
  static String _normalizeCredential(String value) {
    return value
        .replaceAll(RegExp(r'[\u200B-\u200D\uFEFF]'), '')
        .replaceAll(RegExp(r'\s+'), '');
  }

  /// Save Binance API credentials securely.
  Future<void> save({
    required String apiKey,
    required String apiSecret,
  }) async {
    final normalizedApiKey = _normalizeCredential(apiKey);
    final normalizedApiSecret = _normalizeCredential(apiSecret);

    await _storage.write(key: _kApiKey, value: normalizedApiKey);
    await _storage.write(key: _kApiSecret, value: normalizedApiSecret);
  }

  /// Load stored credentials.
  ///
  /// Returns `null` if either key or secret is missing.
  Future<({String apiKey, String apiSecret})?> load() async {
    final apiKey = await _storage.read(key: _kApiKey);
    final apiSecret = await _storage.read(key: _kApiSecret);

    if (apiKey == null || apiSecret == null) return null;

    return (apiKey: apiKey, apiSecret: apiSecret);
  }

  /// Whether both API key and secret are present in secure storage.
  Future<bool> hasCredentials() async {
    final creds = await load();
    return creds != null;
  }

  /// Remove all Binance credentials from secure storage.
  Future<void> clear() async {
    await _storage.delete(key: _kApiKey);
    await _storage.delete(key: _kApiSecret);
  }
}
