import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:bolsio/app/onboarding/theme/v3_tokens.dart';
import 'package:bolsio/app/settings/pages/ai/wizard/widgets/wizard_scaffold.dart';
import 'package:bolsio/core/services/ai/ai_key_validator.dart';
import 'package:bolsio/core/services/ai/ai_provider_type.dart';

/// Heuristic — looser than [AiKeyValidator.validate]. Used to decide
/// whether a clipboard snippet is "probably a key" worth auto-pasting.
///
/// We deliberately keep this permissive: a false positive just means we
/// pre-fill the input with a banner the user can dismiss. A false negative
/// would miss legitimate keys (especially Gemini, whose prefix rotates).
bool looksLikeKeyFor(AiProviderType provider, String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty || trimmed.length < 16) return false;
  // Reject anything with whitespace in the middle — keys never contain it.
  if (trimmed.contains(RegExp(r'\s'))) return false;
  switch (provider) {
    case AiProviderType.openai:
      return trimmed.startsWith('sk-') && trimmed.length > 20;
    case AiProviderType.anthropic:
      return trimmed.startsWith('sk-ant-');
    case AiProviderType.nexus:
      return trimmed.startsWith('sk-') || trimmed.startsWith('tk_');
    case AiProviderType.gemini:
      // Google rotates the prefix every few months. Accept any reasonably
      // long alphanumeric+dash+underscore string.
      return RegExp(r'^[A-Za-z0-9_\-]{30,}$').hasMatch(trimmed);
  }
}

/// Step 4 — paste the API key, with a clipboard auto-detection banner.
///
/// Behaviour:
/// - On `initState` and on `AppLifecycleState.resumed` we peek at the
///   clipboard. If the contents `looksLikeKeyFor(provider, …)` AND the
///   user hasn't typed anything yet, we pre-fill the input and surface a
///   dismissable banner ("Detectamos una key en tu portapapeles, ¿es esta?").
/// - The user can manually paste with the trailing icon button.
/// - The model selector below the input adapts to the provider — dropdown
///   for fixed catalogs (OpenAI/Anthropic/Gemini), free-text for Nexus.
/// - Nexus also gets an "Avanzado" expansion with an optional Base URL
///   field.
/// - Validation is non-blocking: a wrong-prefix key shows a yellow warning
///   but the "Continuar" button is only disabled when the input is empty.
class S4PasteKeyStep extends StatefulWidget {
  const S4PasteKeyStep({
    super.key,
    required this.currentStep,
    required this.totalSteps,
    required this.provider,
    required this.initialApiKey,
    required this.initialModel,
    required this.initialBaseUrl,
    required this.onSubmit,
    required this.onBack,
  });

  final int currentStep;
  final int totalSteps;
  final AiProviderType provider;
  final String? initialApiKey;
  final String? initialModel;
  final String? initialBaseUrl;

  /// Called when the user taps "Continuar" with a non-empty key.
  /// `model` may be `null` (the dispatcher falls back to the provider
  /// default). `baseUrl` is only meaningful for Nexus and is `null` for
  /// every other provider.
  final void Function({
    required String apiKey,
    String? model,
    String? baseUrl,
  }) onSubmit;

  final VoidCallback onBack;

  @override
  State<S4PasteKeyStep> createState() => _S4PasteKeyStepState();
}

class _S4PasteKeyStepState extends State<S4PasteKeyStep>
    with WidgetsBindingObserver {
  late final TextEditingController _keyController;
  late final TextEditingController _baseUrlController;

  String? _selectedModel;
  bool _showKey = false;
  bool _userTypedManually = false;
  bool _autoDetectedBannerVisible = false;
  bool _showAdvanced = false;

  @override
  void initState() {
    super.initState();
    _keyController = TextEditingController(text: widget.initialApiKey ?? '');
    _baseUrlController =
        TextEditingController(text: widget.initialBaseUrl ?? '');
    _selectedModel = widget.initialModel ?? widget.provider.defaultModel;
    if (!widget.provider.allowsFreeTextModel &&
        !widget.provider.models.contains(_selectedModel)) {
      _selectedModel = widget.provider.defaultModel;
    }

    WidgetsBinding.instance.addObserver(this);
    // Peek the clipboard once on first mount so the user gets the auto-
    // detect banner if they pasted just before opening the step.
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeAutoPaste());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _keyController.dispose();
    _baseUrlController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // Re-check clipboard when the app comes back to foreground (the user
    // probably went to the browser to copy the key).
    if (state == AppLifecycleState.resumed) {
      _maybeAutoPaste();
    }
  }

  Future<void> _maybeAutoPaste() async {
    // Don't stomp the field if the user has already typed something.
    if (_userTypedManually) return;
    if (_keyController.text.trim().isNotEmpty) return;
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text == null || text.isEmpty) return;
    if (!looksLikeKeyFor(widget.provider, text)) return;
    if (!mounted) return;
    setState(() {
      _keyController.text = text;
      _autoDetectedBannerVisible = true;
    });
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text == null || text.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('El portapapeles está vacío.')),
      );
      return;
    }
    if (!mounted) return;
    setState(() {
      _keyController.text = text;
      _userTypedManually = false;
      _autoDetectedBannerVisible = false;
    });
  }

  void _onKeyChanged(String value) {
    setState(() {
      _userTypedManually = true;
      _autoDetectedBannerVisible = false;
    });
  }

  void _submit() {
    final key = _keyController.text.trim();
    if (key.isEmpty) return;
    final baseUrl = widget.provider == AiProviderType.nexus
        ? _baseUrlController.text.trim()
        : '';
    widget.onSubmit(
      apiKey: key,
      model: (_selectedModel == null || _selectedModel!.isEmpty)
          ? null
          : _selectedModel,
      baseUrl: baseUrl.isEmpty ? null : baseUrl,
    );
  }

  String _hintForProvider() {
    switch (widget.provider) {
      case AiProviderType.openai:
        return 'sk-...';
      case AiProviderType.anthropic:
        return 'sk-ant-...';
      case AiProviderType.nexus:
        return 'sk-... o tk_...';
      case AiProviderType.gemini:
        return 'AIza...';
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final keyText = _keyController.text;
    final keyTrimmed = keyText.trim();
    final formatWarning = keyTrimmed.isEmpty
        ? null
        : AiKeyValidator.validate(widget.provider, keyTrimmed);
    final canContinue = keyTrimmed.isNotEmpty;

    return WizardScaffold(
      currentStep: widget.currentStep,
      totalSteps: widget.totalSteps,
      onBack: widget.onBack,
      primaryLabel: 'Continuar',
      onPrimary: canContinue ? _submit : null,
      primaryEnabled: canContinue,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Pegá tu API key',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: V3Tokens.spaceMd),
          Text(
            'Tu key se guarda cifrada en este dispositivo. Podés cambiarla cuando quieras desde Settings.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: V3Tokens.space24),

          // Auto-detected banner — collapses cleanly when dismissed.
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeInOut,
            child: _autoDetectedBannerVisible
                ? _AutoDetectedBanner(
                    onDismiss: () {
                      setState(() {
                        _autoDetectedBannerVisible = false;
                      });
                    },
                  )
                : const SizedBox.shrink(),
          ),

          if (_autoDetectedBannerVisible)
            const SizedBox(height: V3Tokens.spaceMd),

          // API key input with toggleable visibility + paste affordance.
          TextField(
            controller: _keyController,
            obscureText: !_showKey,
            onChanged: _onKeyChanged,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              labelText: 'API Key',
              hintText: _hintForProvider(),
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Pegar del portapapeles',
                    icon: const Icon(Icons.content_paste),
                    onPressed: _pasteFromClipboard,
                  ),
                  IconButton(
                    tooltip: _showKey ? 'Ocultar' : 'Mostrar',
                    icon: Icon(
                      _showKey ? Icons.visibility_off : Icons.visibility,
                    ),
                    onPressed: () {
                      setState(() => _showKey = !_showKey);
                    },
                  ),
                ],
              ),
            ),
          ),
          if (formatWarning != null) ...[
            const SizedBox(height: V3Tokens.spaceXs),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.warning_amber_rounded,
                  size: 16,
                  color: Colors.orange,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    formatWarning,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.orange,
                    ),
                  ),
                ),
              ],
            ),
          ],

          const SizedBox(height: V3Tokens.space16),

          // Model selector — dropdown for fixed catalogs, free-text for Nexus.
          Text(
            'Modelo',
            style: V3Tokens.uiStyle(
              size: 13,
              weight: FontWeight.w600,
              color: scheme.onSurface,
            ),
          ),
          const SizedBox(height: V3Tokens.spaceXs),
          if (widget.provider.allowsFreeTextModel)
            TextFormField(
              key: ValueKey('wizard_model_freetext_${widget.provider.name}'),
              initialValue: _selectedModel ?? widget.provider.defaultModel,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                helperText:
                    'Texto libre — Nexus enruta el modelo internamente.',
              ),
              onChanged: (v) {
                _selectedModel = v.trim().isEmpty ? null : v.trim();
              },
            )
          else
            DropdownButtonFormField<String>(
              key: ValueKey('wizard_model_dropdown_${widget.provider.name}'),
              initialValue:
                  widget.provider.models.contains(_selectedModel)
                      ? _selectedModel
                      : widget.provider.defaultModel,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
              ),
              items: widget.provider.models
                  .map((m) => DropdownMenuItem<String>(
                        value: m,
                        child: Text(m),
                      ))
                  .toList(),
              onChanged: (v) {
                setState(() => _selectedModel = v);
              },
            ),

          // "Avanzado" — Nexus-only Base URL toggle.
          if (widget.provider == AiProviderType.nexus) ...[
            const SizedBox(height: V3Tokens.spaceMd),
            InkWell(
              onTap: () => setState(() => _showAdvanced = !_showAdvanced),
              borderRadius: BorderRadius.circular(V3Tokens.radiusSm),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Icon(
                      _showAdvanced
                          ? Icons.keyboard_arrow_down
                          : Icons.keyboard_arrow_right,
                      size: 18,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Avanzado',
                      style: V3Tokens.uiStyle(
                        size: 13,
                        weight: FontWeight.w600,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeInOut,
              child: _showAdvanced
                  ? Padding(
                      padding: const EdgeInsets.only(top: V3Tokens.spaceXs),
                      child: TextField(
                        controller: _baseUrlController,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          labelText: 'Base URL (opcional)',
                          hintText: 'https://api.ramsesdb.tech',
                          helperText:
                              'Solo cambialo si tu Nexus corre en otro dominio.',
                        ),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ],
      ),
    );
  }
}

class _AutoDetectedBanner extends StatelessWidget {
  const _AutoDetectedBanner({required this.onDismiss});
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(V3Tokens.space16),
      decoration: BoxDecoration(
        color: V3Tokens.accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(V3Tokens.radiusMd),
        border: Border.all(
          color: V3Tokens.accent.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.check_circle_outline,
            color: V3Tokens.accent,
            size: 18,
          ),
          const SizedBox(width: V3Tokens.spaceMd),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Detectamos una key en tu portapapeles',
                  style: V3Tokens.uiStyle(
                    size: 13,
                    weight: FontWeight.w700,
                    color: scheme.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'La pre-cargamos abajo. Si no es la correcta, borrala y pegá la tuya.',
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
          IconButton(
            tooltip: 'Cerrar',
            icon: const Icon(Icons.close, size: 18),
            onPressed: onDismiss,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
        ],
      ),
    );
  }
}
