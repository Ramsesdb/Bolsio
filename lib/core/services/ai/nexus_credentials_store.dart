import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Secure credential store for Nexus AI API key.
class NexusCredentialsStore {
  static final instance = NexusCredentialsStore._();
  NexusCredentialsStore._();

  /// Constructor for testing with a custom storage instance.
  NexusCredentialsStore.forTesting(FlutterSecureStorage storage)
    : _storage = storage;

  FlutterSecureStorage _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static const _kApiKey = 'nexus_ai_api_key';

  static String _normalizeCredential(String value) {
    return value
        .replaceAll(RegExp(r'[\u200B-\u200D\uFEFF]'), '')
        .replaceAll(RegExp(r'\s+'), '');
  }

  Future<void> saveApiKey(String apiKey) async {
    final normalized = _normalizeCredential(apiKey);
    await _storage.write(key: _kApiKey, value: normalized);
  }

  Future<String?> loadApiKey() async {
    return _storage.read(key: _kApiKey);
  }

  Future<bool> hasApiKey() async {
    final key = await loadApiKey();
    return key != null && key.trim().isNotEmpty;
  }

  Future<void> clear() async {
    await _storage.delete(key: _kApiKey);
  }
}
