import 'package:bolsio/core/services/ai/ai_provider_type.dart';

/// Common interface implemented by every concrete BYOK provider.
///
/// The shape mirrors the OpenAI chat-completion API because every consumer
/// in bolsio already speaks that dialect. Concrete implementations are
/// responsible for translating into their native request body (Anthropic's
/// `system` field, Gemini's `contents`, etc.).
abstract class AiProvider {
  /// Identifies which provider this is. Mostly used for diagnostics and
  /// error messages.
  AiProviderType get type;

  /// Sends [messages] to the provider and returns the assistant text or
  /// `null` on any failure. Implementations swallow non-2xx responses and
  /// network errors and translate them to `null` — callers already guard
  /// against `null` (this matches the historical [NexusAiService.complete]
  /// contract that all current callers depend on).
  Future<String?> complete({
    required List<Map<String, String>> messages,
    double? temperature,
    int? maxTokens,
    String? model,
  });

  /// Lightweight reachability check. Sends a minimal `ping` prompt and
  /// returns `null` when the API responded successfully, or a short
  /// human-readable error message otherwise.
  Future<String?> testConnection();
}
