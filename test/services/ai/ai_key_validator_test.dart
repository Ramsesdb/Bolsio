import 'package:flutter_test/flutter_test.dart';
import 'package:nitido/core/services/ai/ai_key_validator.dart';
import 'package:nitido/core/services/ai/ai_provider_type.dart';

void main() {
  group('AiKeyValidator', () {
    test('empty key always rejected', () {
      for (final t in AiProviderType.values) {
        expect(AiKeyValidator.validate(t, ''), isNotNull);
        expect(AiKeyValidator.validate(t, '   '), isNotNull);
      }
    });

    test('OpenAI requires sk- prefix', () {
      expect(AiKeyValidator.validate(AiProviderType.openai, 'sk-abc123'), isNull);
      expect(AiKeyValidator.validate(AiProviderType.openai, 'pk-abc'), isNotNull);
    });

    test('Anthropic requires sk-ant- prefix', () {
      expect(
        AiKeyValidator.validate(AiProviderType.anthropic, 'sk-ant-xyz'),
        isNull,
      );
      expect(
        AiKeyValidator.validate(AiProviderType.anthropic, 'sk-xyz'),
        isNotNull,
      );
    });

    test('Nexus accepts sk- and tk_ prefixes', () {
      expect(AiKeyValidator.validate(AiProviderType.nexus, 'sk-abc'), isNull);
      expect(AiKeyValidator.validate(AiProviderType.nexus, 'tk_abc'), isNull);
      expect(AiKeyValidator.validate(AiProviderType.nexus, 'foo'), isNotNull);
    });

    test('Gemini does not validate prefix', () {
      expect(
        AiKeyValidator.validate(AiProviderType.gemini, 'AIzaSy_anything'),
        isNull,
      );
      expect(
        AiKeyValidator.validate(AiProviderType.gemini, 'literally-anything'),
        isNull,
      );
    });
  });
}
