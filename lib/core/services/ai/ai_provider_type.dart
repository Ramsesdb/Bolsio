/// Supported AI providers in the BYOK (Bring Your Own Key) architecture.
///
/// Each entry carries the metadata the dispatcher and the settings UI need:
/// a human-readable label, the catalog of model IDs the user can pick, the
/// default model used when nothing is stored, and an optional URL where the
/// user can grab their key.
///
/// `nexus` keeps `'auto'` as both the default and only catalog entry — Nexus
/// routes models internally and the user can still type any model in the
/// settings page (the field is treated as free-text for that provider).
enum AiProviderType {
  nexus(
    displayName: 'Nexus AI',
    defaultModel: 'auto',
    models: <String>['auto'],
    helpUrl: null,
  ),
  openai(
    displayName: 'OpenAI',
    defaultModel: 'gpt-4o-mini',
    models: <String>[
      'gpt-4o',
      'gpt-4o-mini',
      'gpt-4.1',
      'gpt-4.1-mini',
    ],
    helpUrl: 'https://platform.openai.com/api-keys',
  ),
  anthropic(
    displayName: 'Anthropic',
    defaultModel: 'claude-haiku-4-5',
    models: <String>[
      'claude-haiku-4-5',
      'claude-sonnet-4-6',
      'claude-opus-4-7',
    ],
    helpUrl: 'https://console.anthropic.com/settings/keys',
  ),
  gemini(
    displayName: 'Google Gemini',
    defaultModel: 'gemini-2.5-flash',
    models: <String>[
      'gemini-2.5-flash',
      'gemini-2.5-pro',
      'gemini-2.0-flash',
    ],
    helpUrl: 'https://aistudio.google.com/apikey',
  );

  const AiProviderType({
    required this.displayName,
    required this.defaultModel,
    required this.models,
    required this.helpUrl,
  });

  /// Label shown in the provider picker dropdown.
  final String displayName;

  /// Model used when the credentials object has no `model` set, or when the
  /// stored value is not in [models] (and the provider is not free-text).
  final String defaultModel;

  /// Catalog of allowed model IDs. For `nexus` this is informational only —
  /// the settings UI accepts free-text and the dispatcher does not validate.
  final List<String> models;

  /// Where the user can create or copy their API key. `null` for Nexus
  /// because the provisioning flow lives outside the app.
  final String? helpUrl;

  /// Whether the user can type any model name (instead of picking from
  /// [models]). Currently only Nexus.
  bool get allowsFreeTextModel => this == AiProviderType.nexus;

  /// Stable storage key fragment for this provider. Used by the credential
  /// store and Firebase sync — keep stable to avoid breaking restored data.
  String get storageId => name;

  /// Resolves a stored string back to a provider value. Returns `null` for
  /// `null`/empty input so callers can distinguish "no provider configured"
  /// from "provider configured but unknown".
  static AiProviderType? fromString(String? value) {
    if (value == null) return null;
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    for (final t in AiProviderType.values) {
      if (t.name == trimmed) return t;
    }
    return null;
  }
}
