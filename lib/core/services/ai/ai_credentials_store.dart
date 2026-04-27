import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:wallex/core/database/services/user-setting/user_setting_service.dart';
import 'package:wallex/core/services/ai/ai_credentials.dart';
import 'package:wallex/core/services/ai/ai_provider_type.dart';

/// Per-provider secure credential store backing the BYOK setup.
///
/// Storage layout in [FlutterSecureStorage]:
///   - `ai_credentials_<providerType>` → JSON `{apiKey, model?, baseUrl?}`
///
/// The "active" provider is persisted in [UserSettingService] under
/// [SettingKey.activeAiProvider] so it can ride along with the existing
/// settings sync. Default is `'nexus'` to preserve the pre-BYOK behaviour.
class AiCredentialsStore {
  AiCredentialsStore._();
  static final AiCredentialsStore instance = AiCredentialsStore._();

  /// Test-only constructor that lets callers swap the secure storage backend.
  @visibleForTesting
  AiCredentialsStore.forTesting(FlutterSecureStorage storage)
      : _storage = storage;

  FlutterSecureStorage _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static const _kKeyPrefix = 'ai_credentials_';

  // Legacy keys from the pre-BYOK NexusCredentialsStore. Kept here so the
  // one-time migration can read the old data and clean it up.
  static const _kLegacyApiKey = 'nexus_ai_api_key';
  static const _kLegacyModel = 'nexus_ai_model';

  static String _storageKey(AiProviderType type) =>
      '$_kKeyPrefix${type.storageId}';

  /// Strips zero-width characters and whitespace from a credential string.
  /// Mirrors the normalization the legacy store applied to API keys.
  static String _normalizeCredential(String value) {
    return value
        .replaceAll(RegExp(r'[​-‍﻿]'), '')
        .replaceAll(RegExp(r'\s+'), '');
  }

  /// Persists [creds] for `creds.providerType`. Overwrites any existing
  /// entry for the same provider.
  Future<void> saveCredentials(AiCredentials creds) async {
    final normalized = creds.copyWith(
      apiKey: _normalizeCredential(creds.apiKey),
    );
    await _storage.write(
      key: _storageKey(creds.providerType),
      value: normalized.toJsonString(),
    );
  }

  /// Loads credentials for [type], or `null` if no entry exists.
  Future<AiCredentials?> loadCredentials(AiProviderType type) async {
    final raw = await _storage.read(key: _storageKey(type));
    if (raw == null || raw.isEmpty) return null;
    return AiCredentials.fromJsonString(type, raw);
  }

  /// Loads credentials for the currently active provider. Returns `null`
  /// when no provider is active or the active provider has no key stored.
  Future<AiCredentials?> loadActiveCredentials() async {
    final active = activeProvider();
    if (active == null) return null;
    return loadCredentials(active);
  }

  /// Returns the active provider read from [SettingKey.activeAiProvider],
  /// defaulting to [AiProviderType.nexus] when the setting is missing or
  /// holds an unknown value.
  AiProviderType? activeProvider() {
    final raw = appStateSettings[SettingKey.activeAiProvider];
    return AiProviderType.fromString(raw) ?? AiProviderType.nexus;
  }

  /// Persists [type] as the active provider. The change is immediately
  /// reflected in [appStateSettings] so subsequent dispatches pick it up.
  Future<void> setActiveProvider(AiProviderType type) async {
    await UserSettingService.instance
        .setItem(SettingKey.activeAiProvider, type.storageId);
  }

  /// Returns the providers that currently have an entry in storage.
  Future<List<AiProviderType>> listConfiguredProviders() async {
    final configured = <AiProviderType>[];
    for (final t in AiProviderType.values) {
      final raw = await _storage.read(key: _storageKey(t));
      if (raw != null && raw.isNotEmpty) configured.add(t);
    }
    return configured;
  }

  /// Removes the credential entry for [type]. Idempotent.
  Future<void> deleteCredentials(AiProviderType type) async {
    await _storage.delete(key: _storageKey(type));
  }

  /// One-time migration from the legacy [NexusCredentialsStore] keys to the
  /// new per-provider layout.
  ///
  /// Behaviour:
  ///   - If a Nexus credential already exists in the new store, do nothing.
  ///   - Otherwise, if the legacy `nexus_ai_api_key` exists, copy it (and
  ///     the legacy model, if any) into a fresh [AiCredentials] for Nexus,
  ///     mark Nexus as active, and delete the legacy entries.
  ///   - The function is idempotent and silently no-ops on errors.
  Future<bool> migrateFromLegacyStore() async {
    try {
      final existing = await loadCredentials(AiProviderType.nexus);
      if (existing != null) {
        // Already migrated — make sure the legacy entries are gone.
        await _storage.delete(key: _kLegacyApiKey);
        await _storage.delete(key: _kLegacyModel);
        return false;
      }

      final legacyKey = await _storage.read(key: _kLegacyApiKey);
      if (legacyKey == null || legacyKey.trim().isEmpty) return false;

      final legacyModelRaw = await _storage.read(key: _kLegacyModel);
      final legacyModel =
          (legacyModelRaw != null && legacyModelRaw.trim().isNotEmpty)
              ? legacyModelRaw.trim()
              : null;

      await saveCredentials(AiCredentials(
        providerType: AiProviderType.nexus,
        apiKey: legacyKey,
        model: legacyModel,
      ));
      // The active-provider write goes through UserSettingService → Drift,
      // which can be unavailable in unit tests. Best-effort: swallow the
      // error so the storage migration still completes.
      try {
        await setActiveProvider(AiProviderType.nexus);
      } catch (e) {
        debugPrint('AiCredentialsStore: setActiveProvider failed during '
            'migration (likely DB unavailable in tests): $e');
      }

      await _storage.delete(key: _kLegacyApiKey);
      await _storage.delete(key: _kLegacyModel);
      debugPrint('AiCredentialsStore: migrated legacy Nexus key to BYOK store');
      return true;
    } catch (e) {
      debugPrint('AiCredentialsStore.migrateFromLegacyStore error: $e');
      return false;
    }
  }
}
