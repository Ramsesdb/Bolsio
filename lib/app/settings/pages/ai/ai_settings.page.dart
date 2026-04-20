import 'package:flutter/material.dart';
import 'package:wallex/core/database/services/user-setting/user_setting_service.dart';
import 'package:wallex/core/services/ai/nexus_credentials_store.dart';
import 'package:wallex/i18n/generated/translations.g.dart';

class AiSettingsPage extends StatefulWidget {
  const AiSettingsPage({super.key});

  @override
  State<AiSettingsPage> createState() => _AiSettingsPageState();
}

class _AiSettingsPageState extends State<AiSettingsPage> {
  final _apiKeyController = TextEditingController();

  bool _aiEnabled = false;
  bool _categorizationEnabled = false;
  bool _chatEnabled = false;
  bool _insightsEnabled = false;
  bool _budgetPredictionEnabled = false;
  bool _receiptAiEnabled = true;
  bool _voiceEnabled = true;
  bool _isSavingKey = false;

  String? _maskedApiKey;

  @override
  void initState() {
    super.initState();
    _loadState();
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
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

    final apiKey = await NexusCredentialsStore.instance.loadApiKey();
    _maskedApiKey = apiKey == null ? null : _maskKey(apiKey);

    if (mounted) setState(() {});
  }

  String _maskKey(String key) {
    if (key.length <= 4) return key;
    return '${'*' * (key.length - 4)}${key.substring(key.length - 4)}';
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

  Future<void> _saveApiKey() async {
    final key = _apiKeyController.text.trim();
    if (key.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ingresa una API key valida.')),
      );
      return;
    }

    setState(() => _isSavingKey = true);

    try {
      await NexusCredentialsStore.instance.saveApiKey(key);
      _apiKeyController.clear();
      _maskedApiKey = _maskKey(key);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('API key guardada de forma segura.')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSavingKey = false);
    }
  }

  Future<void> _clearApiKey() async {
    await NexusCredentialsStore.instance.clear();
    if (!mounted) return;

    setState(() {
      _maskedApiKey = null;
      _apiKeyController.clear();
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('API key eliminada.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Wallex AI')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'API Key de Nexus',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Text(_maskedApiKey == null
                      ? 'Estado: no configurada'
                      : 'Estado: configurada ($_maskedApiKey)'),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _apiKeyController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'Nueva API key',
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _isSavingKey ? null : _saveApiKey,
                          icon: _isSavingKey
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.save),
                          label: const Text('Guardar key'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      OutlinedButton.icon(
                        onPressed: _maskedApiKey == null ? null : _clearApiKey,
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('Eliminar'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          SwitchListTile(
            value: _aiEnabled,
            onChanged: (v) => _saveSetting(SettingKey.nexusAiEnabled, v),
            title: const Text('Habilitar IA'),
            subtitle: const Text('Activa las funciones de Wallex AI'),
          ),
          const Divider(),
          SwitchListTile(
            value: _categorizationEnabled,
            onChanged: _aiEnabled
                ? (v) => _saveSetting(SettingKey.aiCategorizationEnabled, v)
                : null,
            title: const Text('Categorizacion automatica'),
            subtitle: const Text('Sugiere categoria en importaciones'),
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
            subtitle: const Text('Analisis de variacion por categorias'),
          ),
          SwitchListTile(
            value: _budgetPredictionEnabled,
            onChanged: _aiEnabled
                ? (v) => _saveSetting(SettingKey.aiBudgetPredictionEnabled, v)
                : null,
            title: const Text('Prediccion de presupuesto'),
            subtitle: const Text('Estimacion de consumo por budget'),
          ),
          SwitchListTile(
            value: _receiptAiEnabled,
            onChanged: _aiEnabled
                ? (v) => _saveSetting(SettingKey.receiptAiEnabled, v)
                : null,
            title: const Text('IA en importacion de comprobantes'),
            subtitle: const Text(
              'Usa analisis multimodal para enriquecer OCR de recibos',
            ),
          ),
          SwitchListTile(
            value: _aiEnabled && _voiceEnabled,
            onChanged: _aiEnabled
                ? (v) => _saveSetting(SettingKey.aiVoiceEnabled, v)
                : null,
            title: Text(t.wallex_ai.voice_settings_title),
            subtitle: Text(t.wallex_ai.voice_settings_subtitle),
          ),
        ],
      ),
    );
  }
}
