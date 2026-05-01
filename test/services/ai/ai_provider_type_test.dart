import 'package:flutter_test/flutter_test.dart';
import 'package:nitido/core/services/ai/ai_provider_type.dart';

void main() {
  group('AiProviderType metadata', () {
    test('every provider has a non-empty displayName and defaultModel', () {
      for (final t in AiProviderType.values) {
        expect(t.displayName, isNotEmpty,
            reason: '${t.name} should have displayName');
        expect(t.defaultModel, isNotEmpty,
            reason: '${t.name} should have defaultModel');
      }
    });

    test('default model is contained in models for non free-text providers',
        () {
      for (final t in AiProviderType.values) {
        if (t.allowsFreeTextModel) continue;
        expect(t.models, contains(t.defaultModel),
            reason: '${t.name} default must appear in catalog');
      }
    });

    test('user-pinned defaults match the spec', () {
      expect(AiProviderType.openai.defaultModel, 'gpt-4o-mini');
      expect(AiProviderType.anthropic.defaultModel, 'claude-haiku-4-5');
      expect(AiProviderType.gemini.defaultModel, 'gemini-2.5-flash');
      expect(AiProviderType.nexus.defaultModel, 'auto');
    });

    test('Anthropic catalog includes the three 2026 aliases', () {
      expect(
        AiProviderType.anthropic.models,
        containsAll(['claude-haiku-4-5', 'claude-sonnet-4-6', 'claude-opus-4-7']),
      );
    });

    test('Nexus is the only free-text provider', () {
      for (final t in AiProviderType.values) {
        expect(t.allowsFreeTextModel, t == AiProviderType.nexus);
      }
    });

    test('fromString resolves names and falls back to null on bad input', () {
      expect(AiProviderType.fromString('openai'), AiProviderType.openai);
      expect(AiProviderType.fromString('anthropic'), AiProviderType.anthropic);
      expect(AiProviderType.fromString(null), isNull);
      expect(AiProviderType.fromString(''), isNull);
      expect(AiProviderType.fromString('not-a-provider'), isNull);
    });
  });
}
