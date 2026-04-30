import 'package:kilatex/core/services/ai/ai_provider_type.dart';

/// Best-effort syntactic validator for API keys.
///
/// Returns `null` when the key looks fine, or a short Spanish warning
/// message that the settings UI can render below the input as a non-blocking
/// hint. The validator never refuses to save — providers occasionally
/// reshape their key prefixes and we would rather let the user save and
/// see the actual API error than hard-block on a stale rule.
class AiKeyValidator {
  /// Returns `null` if the key passes validation, or a warning message
  /// (Spanish) when the format looks suspicious. Empty input always
  /// returns the "key vacía" message.
  static String? validate(AiProviderType type, String key) {
    final trimmed = key.trim();
    if (trimmed.isEmpty) return 'La key no puede estar vacía';
    switch (type) {
      case AiProviderType.openai:
        if (!trimmed.startsWith('sk-')) {
          return 'Las keys de OpenAI suelen empezar con sk-';
        }
        break;
      case AiProviderType.anthropic:
        if (!trimmed.startsWith('sk-ant-')) {
          return 'Las keys de Anthropic suelen empezar con sk-ant-';
        }
        break;
      case AiProviderType.nexus:
        if (!trimmed.startsWith('sk-') && !trimmed.startsWith('tk_')) {
          return 'Las keys de Nexus empiezan con sk- (master) o tk_ (token usuario)';
        }
        break;
      case AiProviderType.gemini:
        // Google rotates the key shape every few months; skip validation.
        break;
    }
    return null;
  }
}
