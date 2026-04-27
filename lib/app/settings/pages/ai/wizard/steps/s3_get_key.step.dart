import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wallex/app/onboarding/theme/v3_tokens.dart';
import 'package:wallex/app/onboarding/widgets/v3_primary_button.dart';
import 'package:wallex/app/settings/pages/ai/wizard/widgets/wizard_scaffold.dart';
import 'package:wallex/core/services/ai/ai_provider_type.dart';

/// Step 3 of the AI setup wizard — provider-specific instructions for
/// fetching an API key.
///
/// Renders a numbered list of steps tailored to [provider], a primary
/// "open browser" button that launches the provider's `helpUrl`, and a
/// secondary "Continuar" CTA the user taps after returning from the
/// browser with the key on the clipboard.
///
/// Nexus is special-cased — it has no `helpUrl` (the provisioning flow is
/// out-of-band) so the body shows a plain-text instruction instead of a
/// numbered list and the "open browser" button is hidden.
class S3GetKeyStep extends StatelessWidget {
  const S3GetKeyStep({
    super.key,
    required this.currentStep,
    required this.totalSteps,
    required this.provider,
    required this.onContinue,
    required this.onBack,
  });

  final int currentStep;
  final int totalSteps;
  final AiProviderType provider;
  final VoidCallback onContinue;
  final VoidCallback onBack;

  /// Numbered instructions per provider. Order matters — these are
  /// rendered as a numbered list so the indices in the leading badge
  /// always increase.
  List<String> _stepsForProvider() {
    switch (provider) {
      case AiProviderType.nexus:
        return const [
          'Pedile al admin de tu Nexus que te genere un token de usuario (`tk_...`).',
          'Si tenés acceso de admin del gateway, también podés usar una key Nexus (`sk-...`).',
          'Copiá la key al portapapeles.',
        ];
      case AiProviderType.openai:
        return const [
          'Andá a platform.openai.com/api-keys',
          'Iniciá sesión o creá una cuenta nueva.',
          'Click en "Create new secret key".',
          'Copiá la key (empieza con `sk-`).',
        ];
      case AiProviderType.anthropic:
        return const [
          'Andá a console.anthropic.com/settings/keys',
          'Iniciá sesión o creá una cuenta nueva.',
          'Click en "Create Key".',
          'Copiá la key (empieza con `sk-ant-`).',
        ];
      case AiProviderType.gemini:
        return const [
          'Andá a aistudio.google.com/apikey',
          'Iniciá sesión con tu cuenta de Google.',
          'Click en "Create API key" y elegí un proyecto.',
          'Copiá la key (empieza con `AIza`).',
        ];
    }
  }

  Future<void> _openHelpUrl(BuildContext context) async {
    final url = provider.helpUrl;
    if (url == null || url.isEmpty) return;
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No pude abrir el navegador. Probá copiar la URL.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final steps = _stepsForProvider();
    final hasHelpUrl = provider.helpUrl != null && provider.helpUrl!.isNotEmpty;

    return WizardScaffold(
      currentStep: currentStep,
      totalSteps: totalSteps,
      onBack: onBack,
      primaryLabel: 'Ya copié la key',
      onPrimary: onContinue,
      primaryLeadingIcon: Icons.arrow_forward,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Conseguí tu API key de ${provider.displayName}',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: V3Tokens.spaceMd),
          Text(
            provider == AiProviderType.nexus
                ? 'Tu admin tiene que generar el token desde el panel de Nexus.'
                : 'Seguí estos pasos en el sitio del proveedor:',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: V3Tokens.space24),
          for (int i = 0; i < steps.length; i++) ...[
            _NumberedStep(index: i + 1, text: steps[i]),
            if (i < steps.length - 1) const SizedBox(height: V3Tokens.spaceMd),
          ],
          const SizedBox(height: V3Tokens.space24),
          if (hasHelpUrl) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: V3PrimaryButton(
                label: 'Abrir ${provider.displayName}',
                leadingIcon: Icons.open_in_new,
                onPressed: () => _openHelpUrl(context),
              ),
            ),
            const SizedBox(height: V3Tokens.space16),
          ],
          // Reassurance: tell the user we WILL detect the key from the
          // clipboard automatically when they come back. This matches the
          // behaviour wired into S4PasteKeyStep via WidgetsBindingObserver.
          Container(
            padding: const EdgeInsets.all(V3Tokens.space16),
            decoration: BoxDecoration(
              color: V3Tokens.accent.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(V3Tokens.radiusMd),
              border: Border.all(
                color: V3Tokens.accent.withValues(alpha: 0.25),
                width: 1,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.content_paste_go,
                  color: V3Tokens.accent,
                  size: 18,
                ),
                const SizedBox(width: V3Tokens.spaceMd),
                Expanded(
                  child: Text(
                    'Volvé a wallex después de copiar la key — la voy a detectar automáticamente del portapapeles.',
                    style: V3Tokens.uiStyle(
                      size: 13,
                      weight: FontWeight.w500,
                      color: scheme.onSurface,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NumberedStep extends StatelessWidget {
  const _NumberedStep({required this.index, required this.text});
  final int index;
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: V3Tokens.accent,
            borderRadius: BorderRadius.circular(V3Tokens.radiusPill),
          ),
          alignment: Alignment.center,
          child: Text(
            '$index',
            style: V3Tokens.uiStyle(
              size: 13,
              weight: FontWeight.w800,
              color: const Color(0xFF0A0A0A),
            ),
          ),
        ),
        const SizedBox(width: V3Tokens.spaceMd),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              text,
              style: V3Tokens.uiStyle(
                size: 14,
                weight: FontWeight.w500,
                color: scheme.onSurface,
                height: 1.45,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
