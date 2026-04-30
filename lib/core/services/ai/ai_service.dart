import 'package:kilatex/core/services/ai/ai_credentials.dart';
import 'package:kilatex/core/services/ai/ai_credentials_store.dart';
import 'package:kilatex/core/services/ai/ai_provider.dart';
import 'package:kilatex/core/services/ai/ai_provider_type.dart';
import 'package:kilatex/core/services/ai/providers/anthropic_provider.dart';
import 'package:kilatex/core/services/ai/providers/gemini_provider.dart';
import 'package:kilatex/core/services/ai/providers/nexus_provider.dart';
import 'package:kilatex/core/services/ai/providers/openai_provider.dart';

/// Singleton dispatcher in front of every BYOK provider.
///
/// Looks up the active credentials from [AiCredentialsStore], builds the
/// matching [AiProvider] implementation, and forwards the request. The
/// public surface (`complete`) intentionally mirrors the historical
/// `NexusAiService.complete` signature so existing callers can switch
/// over with zero behaviour change for users that stay on Nexus.
class AiService {
  AiService._({AiCredentialsStore? credentialsStore})
      : _credentialsStore = credentialsStore ?? AiCredentialsStore.instance;

  static final AiService instance = AiService._();

  /// Test-only constructor — accepts a custom credentials store.
  AiService.forTesting({required AiCredentialsStore credentialsStore})
      : _credentialsStore = credentialsStore;

  final AiCredentialsStore _credentialsStore;

  /// Provider-agnostic chat completion.
  ///
  /// Returns the assistant text, or `null` if no provider is configured /
  /// the request fails. The contract intentionally matches the legacy
  /// [NexusAiService.complete] so existing callers keep working without
  /// special-casing the BYOK migration.
  Future<String?> complete({
    required List<Map<String, String>> messages,
    double? temperature,
    int? maxTokens,
  }) async {
    final creds = await _credentialsStore.loadActiveCredentials();
    if (creds == null) return null;
    final provider = buildProvider(creds);
    return provider.complete(
      messages: messages,
      temperature: temperature,
      maxTokens: maxTokens,
      model: resolveEffectiveModel(creds),
    );
  }

  /// Returns `true` when an active provider is configured AND has a non
  /// empty API key. Cheap shortcut for callers that want to short-circuit
  /// before building prompts.
  Future<bool> isConfigured() async {
    final creds = await _credentialsStore.loadActiveCredentials();
    return creds != null && creds.apiKey.trim().isNotEmpty;
  }

  /// Tests reachability of the active provider. Returns `null` on success
  /// and a short Spanish error message on failure (no provider, network,
  /// HTTP status, etc.).
  Future<String?> testActiveProviderConnection() async {
    final creds = await _credentialsStore.loadActiveCredentials();
    if (creds == null) return 'No hay proveedor configurado';
    return buildProvider(creds).testConnection();
  }

  /// Tests reachability of the supplied [creds] without persisting them as
  /// the active provider. Used by the setup wizard to validate the key the
  /// user is currently typing before committing it to secure storage.
  ///
  /// Returns `null` on success and a short Spanish error message otherwise.
  /// Empty/whitespace API keys short-circuit to a friendly error message
  /// instead of forwarding the empty string to the provider.
  Future<String?> testCredentials(AiCredentials creds) async {
    if (creds.apiKey.trim().isEmpty) return 'La API key está vacía';
    return buildProvider(creds).testConnection();
  }

  /// Picks the right concrete provider for [creds].
  AiProvider buildProvider(AiCredentials creds) {
    final effectiveModel = resolveEffectiveModel(creds);
    switch (creds.providerType) {
      case AiProviderType.nexus:
        return NexusProvider(
          apiKey: creds.apiKey,
          baseUrl: creds.baseUrl,
          model: effectiveModel,
        );
      case AiProviderType.openai:
        return OpenAiProvider(
          apiKey: creds.apiKey,
          model: effectiveModel,
        );
      case AiProviderType.anthropic:
        return AnthropicProvider(
          apiKey: creds.apiKey,
          model: effectiveModel,
        );
      case AiProviderType.gemini:
        return GeminiProvider(
          apiKey: creds.apiKey,
          model: effectiveModel,
        );
    }
  }

  /// Resolves which model id to send to the provider.
  ///
  /// Rules:
  ///   - If `creds.model` is null/empty → return `defaultModel` for the type.
  ///   - For free-text providers (Nexus) → return the stored value verbatim.
  ///   - Otherwise, only return the stored value if it is in the catalog;
  ///     fall back to the default when the user picked something stale.
  String resolveEffectiveModel(AiCredentials creds) {
    final stored = creds.model;
    if (stored == null || stored.isEmpty) return creds.providerType.defaultModel;
    if (creds.providerType.allowsFreeTextModel) return stored;
    return creds.providerType.models.contains(stored)
        ? stored
        : creds.providerType.defaultModel;
  }
}
