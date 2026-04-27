import 'package:flutter/material.dart';
import 'package:wallex/app/onboarding/theme/v3_tokens.dart';
import 'package:wallex/app/settings/pages/ai/wizard/widgets/provider_card.dart';
import 'package:wallex/app/settings/pages/ai/wizard/widgets/wizard_scaffold.dart';
import 'package:wallex/core/services/ai/ai_provider_type.dart';

/// Step 2 of the AI setup wizard — provider selector.
///
/// Layout:
/// - Title + body text (matches the privacy slide's intro pattern).
/// - Stack of [WizardProviderCard]s, one per [AiProviderType].
/// - When the user picks a provider that already has stored credentials
///   the wizard offers a one-tap shortcut to skip ahead to the test step
///   (`onUseExisting`) instead of forcing a re-paste.
class S2ChooseProviderStep extends StatelessWidget {
  const S2ChooseProviderStep({
    super.key,
    required this.currentStep,
    required this.totalSteps,
    required this.selected,
    required this.configuredProviders,
    required this.onSelect,
    required this.onContinue,
    required this.onBack,
    required this.onUseExisting,
  });

  final int currentStep;
  final int totalSteps;
  final AiProviderType? selected;

  /// Set of providers the user already has credentials for. Used to render
  /// the "Ya configurado" badge and to gate the `onUseExisting` shortcut.
  final Set<AiProviderType> configuredProviders;

  final ValueChanged<AiProviderType> onSelect;
  final VoidCallback onContinue;
  final VoidCallback onBack;

  /// Shortcut called when the user picks a provider that already has a key
  /// stored. The wizard host jumps straight to the test step without
  /// asking the user to paste a key again.
  final VoidCallback onUseExisting;

  static const _descriptions = <AiProviderType, String>{
    AiProviderType.nexus:
        'Gateway propio compartido. Pedile al admin un token de usuario.',
    AiProviderType.openai:
        'GPT-4o-mini y derivados. Necesitás una cuenta en platform.openai.com.',
    AiProviderType.anthropic:
        'Claude (Haiku/Sonnet). Necesitás una cuenta en console.anthropic.com.',
    AiProviderType.gemini:
        'Gemini 2.5 Flash gratuito. Necesitás una cuenta en aistudio.google.com.',
  };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final selectedAlreadyConfigured =
        selected != null && configuredProviders.contains(selected);

    return WizardScaffold(
      currentStep: currentStep,
      totalSteps: totalSteps,
      onBack: onBack,
      primaryLabel: 'Continuar',
      onPrimary: selected == null ? null : onContinue,
      primaryEnabled: selected != null,
      // Show the "use existing" shortcut as a secondary CTA only when it
      // actually does something — otherwise we keep a single full-width
      // primary button (mirrors V3SlideTemplate's no-secondary layout).
      secondaryLabel: selectedAlreadyConfigured ? 'Usar la guardada' : null,
      onSecondary: selectedAlreadyConfigured ? onUseExisting : null,
      secondaryLeadingIcon:
          selectedAlreadyConfigured ? Icons.check_circle_outline : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '¿Qué proveedor querés usar?',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: V3Tokens.spaceMd),
          Text(
            'Cada proveedor tiene sus tarifas y modelos. Si tu equipo administra un Nexus, esa es la opción más simple.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: V3Tokens.space24),
          for (final provider in AiProviderType.values) ...[
            WizardProviderCard(
              provider: provider,
              description: _descriptions[provider] ?? '',
              selected: provider == selected,
              recommended: provider == AiProviderType.nexus,
              alreadyConfigured: configuredProviders.contains(provider),
              onTap: () => onSelect(provider),
            ),
            const SizedBox(height: V3Tokens.spaceSm),
          ],
        ],
      ),
    );
  }
}
