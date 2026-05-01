import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nitido/core/database/services/user-setting/user_setting_service.dart';
import 'package:nitido/core/services/ai/ai_credentials.dart';
import 'package:nitido/core/services/ai/ai_credentials_store.dart';
import 'package:nitido/core/services/ai/ai_provider_type.dart';
import 'package:nitido/core/services/ai/ai_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AiCredentialsStore store;
  late AiService service;

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    appStateSettings.remove(SettingKey.activeAiProvider);
    store = AiCredentialsStore.forTesting(const FlutterSecureStorage());
    service = AiService.forTesting(credentialsStore: store);
  });

  group('AiService.resolveEffectiveModel', () {
    test('returns provider default when stored model is null', () {
      const creds = AiCredentials(
        providerType: AiProviderType.openai,
        apiKey: 'sk-test',
      );
      expect(service.resolveEffectiveModel(creds), 'gpt-4o-mini');
    });

    test('returns provider default when stored model is unknown', () {
      const creds = AiCredentials(
        providerType: AiProviderType.openai,
        apiKey: 'sk-test',
        model: 'gpt-2-imaginary',
      );
      expect(service.resolveEffectiveModel(creds), 'gpt-4o-mini');
    });

    test('returns stored model verbatim when in catalog', () {
      const creds = AiCredentials(
        providerType: AiProviderType.openai,
        apiKey: 'sk-test',
        model: 'gpt-4o',
      );
      expect(service.resolveEffectiveModel(creds), 'gpt-4o');
    });

    test('Nexus accepts free-text model', () {
      const creds = AiCredentials(
        providerType: AiProviderType.nexus,
        apiKey: 'sk-test',
        model: 'anything/i-want',
      );
      expect(service.resolveEffectiveModel(creds), 'anything/i-want');
    });
  });

  group('AiService.buildProvider', () {
    test('returns the matching provider implementation', () {
      const openaiCreds = AiCredentials(
        providerType: AiProviderType.openai,
        apiKey: 'sk-test',
      );
      expect(
        service.buildProvider(openaiCreds).type,
        AiProviderType.openai,
      );

      const anthropicCreds = AiCredentials(
        providerType: AiProviderType.anthropic,
        apiKey: 'sk-ant-test',
      );
      expect(
        service.buildProvider(anthropicCreds).type,
        AiProviderType.anthropic,
      );

      const geminiCreds = AiCredentials(
        providerType: AiProviderType.gemini,
        apiKey: 'AIza-test',
      );
      expect(
        service.buildProvider(geminiCreds).type,
        AiProviderType.gemini,
      );

      const nexusCreds = AiCredentials(
        providerType: AiProviderType.nexus,
        apiKey: 'sk-nexus',
      );
      expect(
        service.buildProvider(nexusCreds).type,
        AiProviderType.nexus,
      );
    });
  });

  group('AiService.complete short-circuits', () {
    test('returns null when no credentials are configured', () async {
      // No active provider, no stored creds → dispatcher should bail.
      appStateSettings[SettingKey.activeAiProvider] = AiProviderType.openai.name;
      final result = await service.complete(messages: [
        {'role': 'user', 'content': 'hi'},
      ]);
      expect(result, isNull);
    });
  });

  group('AiService.isConfigured', () {
    test('false when no provider has credentials', () async {
      expect(await service.isConfigured(), isFalse);
    });

    test('true once active provider has a credential', () async {
      appStateSettings[SettingKey.activeAiProvider] =
          AiProviderType.openai.name;
      await store.saveCredentials(const AiCredentials(
        providerType: AiProviderType.openai,
        apiKey: 'sk-test',
        model: 'gpt-4o',
      ));
      expect(await service.isConfigured(), isTrue);
    });
  });
}
