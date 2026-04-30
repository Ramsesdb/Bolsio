import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:bolsio/app/onboarding/theme/v3_tokens.dart';
import 'package:bolsio/app/settings/pages/ai/wizard/ai_wizard.page.dart';
import 'package:bolsio/core/database/services/user-setting/user_setting_service.dart';
import 'package:bolsio/core/routes/route_utils.dart';
import 'package:bolsio/core/services/ai/ai_credentials.dart';
import 'package:bolsio/core/services/ai/ai_credentials_store.dart';
import 'package:bolsio/core/services/ai/ai_key_validator.dart';
import 'package:bolsio/core/services/ai/ai_provider_type.dart';
import 'package:bolsio/core/services/ai/ai_service.dart';
import 'package:bolsio/i18n/generated/translations.g.dart';

class AiSettingsPage extends StatefulWidget {
  const AiSettingsPage({super.key});

  @override
  State<AiSettingsPage> createState() => _AiSettingsPageState();
}

class _AiSettingsPageState extends State<AiSettingsPage> {
  final _apiKeyController = TextEditingController();
  final _baseUrlController = TextEditingController();

  bool _aiEnabled = false;
  bool _categorizationEnabled = false;
  bool _chatEnabled = false;
  bool _insightsEnabled = false;
  bool _budgetPredictionEnabled = false;
  bool _receiptAiEnabled = true;
  bool _voiceEnabled = true;

  bool _isSavingKey = false;
  bool _isTestingConnection = false;
  bool _showApiKey = false;

  /// Provider currently rendered in the editor card. Defaults to the active
  /// provider on first load.
  AiProviderType _editingProvider = AiProviderType.nexus;

  /// Provider selected as "active" — used by [AiService] to dispatch.
  AiProviderType _activeProvider = AiProviderType.nexus;

  /// Model selected in the dropdown for the editing provider.
  String? _selectedModel;

  /// Existing credentials per provider (loaded once, refreshed on save).
  final Map<AiProviderType, AiCredentials> _storedCreds = {};

  /// Last validation warning shown under the API key input.
  String? _keyWarning;

  /// Last connection test result. `null` = idle, empty string = OK,
  /// non-empty = error message.
  String? _testResult;

  @override
  void initState() {
    super.initState();
    _loadState();
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    _baseUrlController.dispose();
    super.dispose();
  }

  Future<void> _loadState() async {
    _aiEnabled = appStateSettings[SettingKey.nexusAiEnabled] == '1';
    _categorizationEnabled =
        appStateSettings[SettingKey.aiCategorizationEnabled] == '1';
    _chatEnabled = appStateSettings[SettingKey.aiChatEnabled] == '1';
    _insightsEnabled = appStateSettings[SettingKey.aiInsightsEnabled] == '1';
    _budgetPredictionEnabled =
        appStateSettings[SettingKey.aiBudgetPredictionEnabled] == '1';
    _receiptAiEnabled = appStateSettings[SettingKey.receiptAiEnabled] != '0';
    _voiceEnabled = appStateSettings[SettingKey.aiVoiceEnabled] != '0';

    _activeProvider = AiCredentialsStore.instance.activeProvider() ??
        AiProviderType.nexus;
    _editingProvider = _activeProvider;

    _storedCreds.clear();
    for (final t in AiProviderType.values) {
      final c = await AiCredentialsStore.instance.loadCredentials(t);
      if (c != null) _storedCreds[t] = c;
    }

    _hydrateEditorFromStored();
    if (mounted) setState(() {});
  }

  void _hydrateEditorFromStored() {
    final c = _storedCreds[_editingProvider];
    _apiKeyController.text = '';
    _baseUrlController.text = c?.baseUrl ?? '';
    _selectedModel = c?.model ?? _editingProvider.defaultModel;
    if (!_editingProvider.allowsFreeTextModel &&
        !_editingProvider.models.contains(_selectedModel)) {
      _selectedModel = _editingProvider.defaultModel;
    }
    _keyWarning = null;
    _testResult = null;
  }

  Future<void> _saveSetting(SettingKey key, bool value) async {
    await UserSettingService.instance.setItem(key, value ? '1' : '0');
    if (mounted) {
      setState(() {
        _aiEnabled = appStateSettings[SettingKey.nexusAiEnabled] == '1';
        _categorizationEnabled =
            appStateSettings[SettingKey.aiCategorizationEnabled] == '1';
        _chatEnabled = appStateSettings[SettingKey.aiChatEnabled] == '1';
        _insightsEnabled = appStateSettings[SettingKey.aiInsightsEnabled] == '1';
        _budgetPredictionEnabled =
            appStateSettings[SettingKey.aiBudgetPredictionEnabled] == '1';
        _receiptAiEnabled = appStateSettings[SettingKey.receiptAiEnabled] != '0';
        _voiceEnabled = appStateSettings[SettingKey.aiVoiceEnabled] != '0';
      });
    }
  }

  String _maskKey(String key) {
    if (key.length <= 4) return '****';
    return '${'*' * (key.length - 4)}${key.substring(key.length - 4)}';
  }

  Future<void> _onActiveProviderChanged(AiProviderType type) async {
    setState(() {
      _activeProvider = type;
      _editingProvider = type;
      _hydrateEditorFromStored();
    });
    await AiCredentialsStore.instance.setActiveProvider(type);
  }

  void _onEditingProviderChanged(AiProviderType type) {
    setState(() {
      _editingProvider = type;
      _hydrateEditorFromStored();
    });
  }

  void _onApiKeyChanged(String value) {
    setState(() {
      _keyWarning = value.isEmpty
          ? null
          : AiKeyValidator.validate(_editingProvider, value);
    });
  }

  Future<void> _saveCredentials() async {
    final key = _apiKeyController.text.trim();
    final existing = _storedCreds[_editingProvider];
    final effectiveKey = key.isEmpty ? (existing?.apiKey ?? '') : key;

    if (effectiveKey.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ingresa una API key válida.')),
      );
      return;
    }

    setState(() => _isSavingKey = true);
    try {
      final baseUrl = _editingProvider == AiProviderType.nexus
          ? _baseUrlController.text.trim()
          : null;

      final creds = AiCredentials(
        providerType: _editingProvider,
        apiKey: effectiveKey,
        model: _selectedModel,
        baseUrl: (baseUrl == null || baseUrl.isEmpty) ? null : baseUrl,
      );
      await AiCredentialsStore.instance.saveCredentials(creds);

      // First time we save credentials, also mark this provider as active
      // so testActiveProviderConnection picks it up immediately.
      if (existing == null) {
        await AiCredentialsStore.instance.setActiveProvider(_editingProvider);
        _activeProvider = _editingProvider;
      }

      _storedCreds[_editingProvider] = creds;
      _apiKeyController.clear();
      _testResult = null;

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Credenciales guardadas de forma segura.')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSavingKey = false);
    }
  }

  Future<void> _deleteCredentials() async {
    final type = _editingProvider;
    await AiCredentialsStore.instance.deleteCredentials(type);
    _storedCreds.remove(type);

    // If the active provider had its key removed, pick another configured
    // provider (or fall back to Nexus) so the dispatcher does not blow up.
    if (_activeProvider == type) {
      final remaining = _storedCreds.keys.toList();
      final next = remaining.isNotEmpty ? remaining.first : AiProviderType.nexus;
      await AiCredentialsStore.instance.setActiveProvider(next);
      _activeProvider = next;
    }

    if (!mounted) return;
    setState(() {
      _hydrateEditorFromStored();
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('API key eliminada.')),
    );
  }

  Future<void> _testConnection() async {
    setState(() {
      _isTestingConnection = true;
      _testResult = null;
    });
    try {
      final result = await AiService.instance.testActiveProviderConnection();
      if (!mounted) return;
      setState(() {
        _testResult = result ?? '';
      });
    } finally {
      if (mounted) setState(() => _isTestingConnection = false);
    }
  }

  Future<void> _openHelpUrl() async {
    final url = _editingProvider.helpUrl;
    if (url == null || url.isEmpty) return;
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final activeCreds = _storedCreds[_activeProvider];
    final configuredOthers = _storedCreds.keys
        .where((k) => k != _activeProvider)
        .map((k) => k.displayName)
        .toList();
    final editingCreds = _storedCreds[_editingProvider];

    return Scaffold(
      appBar: AppBar(title: const Text('Bolsi')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ─── Setup wizard entry banner ─────────────────────────
          // Friendly entry-point above the manual config cards. Power
          // users can ignore it; first-timers get a guided flow.
          _WizardEntryBanner(
            onTap: () async {
              await RouteUtils.pushRoute(const AiWizardPage());
              // Refresh settings page when wizard returns — the user may
              // have just configured a new active provider.
              if (mounted) await _loadState();
            },
          ),
          const SizedBox(height: 16),

          // ─── Active provider card ──────────────────────────────
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Proveedor activo',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<AiProviderType>(
                    initialValue: _activeProvider,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'Proveedor',
                    ),
                    items: AiProviderType.values
                        .map((t) => DropdownMenuItem<AiProviderType>(
                              value: t,
                              child: Text(t.displayName),
                            ))
                        .toList(),
                    onChanged: (v) {
                      if (v != null) _onActiveProviderChanged(v);
                    },
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        activeCreds == null
                            ? Icons.warning_amber_rounded
                            : Icons.check_circle_outline,
                        size: 18,
                        color: activeCreds == null
                            ? Colors.orange
                            : Colors.green,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          activeCreds == null
                              ? 'Sin configurar'
                              : 'Configurado (${_maskKey(activeCreds.apiKey)})',
                        ),
                      ),
                    ],
                  ),
                  if (configuredOthers.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      'También tenés keys para: ${configuredOthers.join(', ')}',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ─── Credentials editor card ──────────────────────────
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Configurar credenciales',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      DropdownButton<AiProviderType>(
                        value: _editingProvider,
                        items: AiProviderType.values
                            .map((t) => DropdownMenuItem<AiProviderType>(
                                  value: t,
                                  child: Text(t.displayName),
                                ))
                            .toList(),
                        onChanged: (v) {
                          if (v != null) _onEditingProviderChanged(v);
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _apiKeyController,
                    obscureText: !_showApiKey,
                    onChanged: _onApiKeyChanged,
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      labelText: editingCreds == null
                          ? 'API Key'
                          : 'Nueva API Key (opcional)',
                      hintText: editingCreds == null
                          ? null
                          : 'Actual: ${_maskKey(editingCreds.apiKey)}',
                      suffixIcon: IconButton(
                        icon: Icon(_showApiKey
                            ? Icons.visibility_off
                            : Icons.visibility),
                        onPressed: () {
                          setState(() => _showApiKey = !_showApiKey);
                        },
                      ),
                    ),
                  ),
                  if (_keyWarning != null) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(
                          Icons.warning_amber_rounded,
                          size: 16,
                          color: Colors.orange,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            _keyWarning!,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.orange,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 12),

                  // Model selector
                  if (_editingProvider.allowsFreeTextModel)
                    TextFormField(
                      key: ValueKey('model_freetext_${_editingProvider.name}'),
                      initialValue:
                          _selectedModel ?? _editingProvider.defaultModel,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        labelText: 'Modelo',
                        helperText:
                            'Texto libre — Nexus enruta el modelo internamente.',
                      ),
                      onChanged: (v) {
                        _selectedModel = v.trim().isEmpty ? null : v.trim();
                      },
                    )
                  else
                    DropdownButtonFormField<String>(
                      key: ValueKey('model_dropdown_${_editingProvider.name}'),
                      initialValue:
                          _editingProvider.models.contains(_selectedModel)
                              ? _selectedModel
                              : _editingProvider.defaultModel,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        labelText: 'Modelo',
                      ),
                      items: _editingProvider.models
                          .map((m) => DropdownMenuItem<String>(
                                value: m,
                                child: Text(m),
                              ))
                          .toList(),
                      onChanged: (v) {
                        setState(() => _selectedModel = v);
                      },
                    ),

                  // Base URL is only relevant for Nexus
                  if (_editingProvider == AiProviderType.nexus) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: _baseUrlController,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        labelText: 'Base URL (opcional)',
                        hintText: 'https://api.ramsesdb.tech',
                      ),
                    ),
                  ],

                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _isSavingKey ? null : _saveCredentials,
                          icon: _isSavingKey
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.save),
                          label: const Text('Guardar'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      OutlinedButton.icon(
                        onPressed:
                            editingCreds == null ? null : _deleteCredentials,
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('Eliminar'),
                      ),
                    ],
                  ),
                  if (_editingProvider.helpUrl != null) ...[
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: _openHelpUrl,
                        icon: const Icon(Icons.open_in_new, size: 16),
                        label: const Text('¿Dónde consigo mi API key?'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ─── Test connection card ─────────────────────────────
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Probar conexión',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Envía un ping al proveedor activo. Esto consume ~10 tokens de tu cuota.',
                    style: TextStyle(fontSize: 12),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      FilledButton.icon(
                        onPressed:
                            _isTestingConnection ? null : _testConnection,
                        icon: _isTestingConnection
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.bolt),
                        label: const Text('Probar'),
                      ),
                      const SizedBox(width: 12),
                      if (_testResult != null)
                        Expanded(
                          child: Row(
                            children: [
                              Icon(
                                _testResult!.isEmpty
                                    ? Icons.check_circle
                                    : Icons.error,
                                size: 18,
                                color: _testResult!.isEmpty
                                    ? Colors.green
                                    : Colors.red,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  _testResult!.isEmpty
                                      ? 'Conexión OK'
                                      : _testResult!,
                                  style: TextStyle(
                                    color: _testResult!.isEmpty
                                        ? Colors.green
                                        : Colors.red,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ─── Existing feature toggles (unchanged) ─────────────
          SwitchListTile(
            value: _aiEnabled,
            onChanged: (v) => _saveSetting(SettingKey.nexusAiEnabled, v),
            title: const Text('Habilitar IA'),
            subtitle: const Text('Activa las funciones de Bolsi'),
          ),
          const Divider(),
          SwitchListTile(
            value: _categorizationEnabled,
            onChanged: _aiEnabled
                ? (v) => _saveSetting(SettingKey.aiCategorizationEnabled, v)
                : null,
            title: const Text('Categorización automática'),
            subtitle: const Text('Sugiere categoría en importaciones'),
          ),
          SwitchListTile(
            value: _chatEnabled,
            onChanged: _aiEnabled
                ? (v) => _saveSetting(SettingKey.aiChatEnabled, v)
                : null,
            title: const Text('Chat financiero'),
            subtitle: const Text('Asistente conversacional en dashboard'),
          ),
          SwitchListTile(
            value: _insightsEnabled,
            onChanged: _aiEnabled
                ? (v) => _saveSetting(SettingKey.aiInsightsEnabled, v)
                : null,
            title: const Text('Insights de gastos'),
            subtitle: const Text('Análisis de variación por categorías'),
          ),
          SwitchListTile(
            value: _budgetPredictionEnabled,
            onChanged: _aiEnabled
                ? (v) => _saveSetting(SettingKey.aiBudgetPredictionEnabled, v)
                : null,
            title: const Text('Predicción de presupuesto'),
            subtitle: const Text('Estimación de consumo por budget'),
          ),
          SwitchListTile(
            value: _receiptAiEnabled,
            onChanged: _aiEnabled
                ? (v) => _saveSetting(SettingKey.receiptAiEnabled, v)
                : null,
            title: const Text('IA en importación de comprobantes'),
            subtitle: const Text(
              'Usa análisis multimodal para enriquecer OCR de recibos',
            ),
          ),
          SwitchListTile(
            value: _aiEnabled && _voiceEnabled,
            onChanged: _aiEnabled
                ? (v) => _saveSetting(SettingKey.aiVoiceEnabled, v)
                : null,
            title: Text(t.bolsio_ai.voice_settings_title),
            subtitle: Text(t.bolsio_ai.voice_settings_subtitle),
          ),
        ],
      ),
    );
  }
}

/// Top-of-page entry banner that opens the [AiWizardPage].
///
/// Visuals borrow the accent-tinted bullet pattern used by the privacy
/// slide (s06) and the welcome step — accent leading icon, headline +
/// subtitle, trailing chevron. Tap calls back into the parent so the
/// settings page can refresh state when the wizard pops.
class _WizardEntryBanner extends StatelessWidget {
  const _WizardEntryBanner({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(V3Tokens.radiusMd),
        child: Ink(
          decoration: BoxDecoration(
            color: V3Tokens.accent.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(V3Tokens.radiusMd),
            border: Border.all(
              color: V3Tokens.accent.withValues(alpha: 0.35),
              width: 1,
            ),
          ),
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: V3Tokens.accent.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(V3Tokens.radiusMd),
                ),
                alignment: Alignment.center,
                child: const Icon(
                  Icons.auto_awesome,
                  color: V3Tokens.accent,
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Setup guiado',
                      style: V3Tokens.uiStyle(
                        size: 15,
                        weight: FontWeight.w700,
                        color: scheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Configurá tu IA paso a paso en menos de un minuto.',
                      style: V3Tokens.uiStyle(
                        size: 12,
                        weight: FontWeight.w500,
                        color: scheme.onSurfaceVariant,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.arrow_forward_ios,
                size: 14,
                color: V3Tokens.accent,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
