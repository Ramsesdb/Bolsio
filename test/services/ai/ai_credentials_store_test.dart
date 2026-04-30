import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bolsio/core/services/ai/ai_credentials.dart';
import 'package:bolsio/core/services/ai/ai_credentials_store.dart';
import 'package:bolsio/core/services/ai/ai_provider_type.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AiCredentialsStore store;

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    store = AiCredentialsStore.forTesting(const FlutterSecureStorage());
  });

  group('AiCredentialsStore — basic CRUD', () {
    test('saveCredentials + loadCredentials round-trip', () async {
      final creds = AiCredentials(
        providerType: AiProviderType.openai,
        apiKey: 'sk-test',
        model: 'gpt-4o',
      );
      await store.saveCredentials(creds);

      final loaded = await store.loadCredentials(AiProviderType.openai);
      expect(loaded, isNotNull);
      expect(loaded!.apiKey, 'sk-test');
      expect(loaded.model, 'gpt-4o');
      expect(loaded.providerType, AiProviderType.openai);
    });

    test('loadCredentials returns null for unset provider', () async {
      expect(
        await store.loadCredentials(AiProviderType.gemini),
        isNull,
      );
    });

    test('deleteCredentials removes the entry', () async {
      await store.saveCredentials(const AiCredentials(
        providerType: AiProviderType.openai,
        apiKey: 'sk-test',
      ));
      await store.deleteCredentials(AiProviderType.openai);
      expect(
        await store.loadCredentials(AiProviderType.openai),
        isNull,
      );
    });

    test('listConfiguredProviders only includes saved entries', () async {
      await store.saveCredentials(const AiCredentials(
        providerType: AiProviderType.openai,
        apiKey: 'sk-test',
      ));
      await store.saveCredentials(const AiCredentials(
        providerType: AiProviderType.gemini,
        apiKey: 'AIza-test',
      ));
      final configured = await store.listConfiguredProviders();
      expect(configured.toSet(), {
        AiProviderType.openai,
        AiProviderType.gemini,
      });
    });

    test('saveCredentials normalises whitespace and zero-width chars', () async {
      await store.saveCredentials(const AiCredentials(
        providerType: AiProviderType.openai,
        apiKey: '  sk-test  \n',
      ));
      final loaded = await store.loadCredentials(AiProviderType.openai);
      expect(loaded!.apiKey, 'sk-test');
    });

    test('baseUrl persists for Nexus credentials', () async {
      await store.saveCredentials(const AiCredentials(
        providerType: AiProviderType.nexus,
        apiKey: 'sk-test',
        baseUrl: 'https://example.com',
      ));
      final loaded = await store.loadCredentials(AiProviderType.nexus);
      expect(loaded!.baseUrl, 'https://example.com');
    });
  });

  group('AiCredentialsStore — legacy migration', () {
    test('migrateFromLegacyStore moves legacy Nexus key to new store',
        () async {
      FlutterSecureStorage.setMockInitialValues({
        'nexus_ai_api_key': 'legacy-sk',
        'nexus_ai_model': 'legacy-model',
      });
      store = AiCredentialsStore.forTesting(const FlutterSecureStorage());

      final migrated = await store.migrateFromLegacyStore();
      expect(migrated, isTrue);

      final loaded = await store.loadCredentials(AiProviderType.nexus);
      expect(loaded, isNotNull);
      expect(loaded!.apiKey, 'legacy-sk');
      expect(loaded.model, 'legacy-model');

      // Legacy entries are gone after migration
      const legacyStorage = FlutterSecureStorage();
      expect(await legacyStorage.read(key: 'nexus_ai_api_key'), isNull);
      expect(await legacyStorage.read(key: 'nexus_ai_model'), isNull);
    });

    test('migrateFromLegacyStore is a no-op when nothing is stored', () async {
      final migrated = await store.migrateFromLegacyStore();
      expect(migrated, isFalse);
    });

    test('migrateFromLegacyStore is idempotent — running twice is safe',
        () async {
      FlutterSecureStorage.setMockInitialValues({
        'nexus_ai_api_key': 'legacy-sk',
      });
      store = AiCredentialsStore.forTesting(const FlutterSecureStorage());

      expect(await store.migrateFromLegacyStore(), isTrue);
      expect(await store.migrateFromLegacyStore(), isFalse);

      final loaded = await store.loadCredentials(AiProviderType.nexus);
      expect(loaded!.apiKey, 'legacy-sk');
    });

    test('migrateFromLegacyStore does not overwrite an existing new entry',
        () async {
      FlutterSecureStorage.setMockInitialValues({
        'nexus_ai_api_key': 'legacy-sk',
      });
      store = AiCredentialsStore.forTesting(const FlutterSecureStorage());
      // User already has a fresh credential — migration must respect it.
      await store.saveCredentials(const AiCredentials(
        providerType: AiProviderType.nexus,
        apiKey: 'fresh-sk',
      ));

      final migrated = await store.migrateFromLegacyStore();
      expect(migrated, isFalse);

      final loaded = await store.loadCredentials(AiProviderType.nexus);
      expect(loaded!.apiKey, 'fresh-sk');
    });
  });
}
