import 'package:flutter/material.dart';
import 'package:bolsio/app/onboarding/theme/v3_tokens.dart';
import 'package:bolsio/app/settings/pages/ai/wizard/widgets/wizard_scaffold.dart';
import 'package:bolsio/core/services/ai/ai_credentials.dart';

/// Step 6 — success screen confirming the active provider + model.
///
/// Visuals match `s11_ready` from the onboarding flow: large display
/// title, accent underline bar, summary blurb, then a feature list. The
/// final action pair lets the user either close the wizard or go back to
/// step 2 to configure another provider.
class S6DoneStep extends StatelessWidget {
  const S6DoneStep({
    super.key,
    required this.currentStep,
    required this.totalSteps,
    required this.credentials,
    required this.effectiveModel,
    required this.onFinish,
    required this.onConfigureAnother,
  });

  final int currentStep;
  final int totalSteps;
  final AiCredentials credentials;

  /// The model id that the dispatcher will actually use — resolved through
  /// `AiService.resolveEffectiveModel` so the user sees the same value the
  /// API will see (handles "free-text Nexus" + "stale dropdown fallback").
  final String effectiveModel;

  final VoidCallback onFinish;
  final VoidCallback onConfigureAnother;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final width = MediaQuery.of(context).size.width;
    final double computed = width * 0.18;
    final double heroSize = computed.clamp(56.0, 80.0).toDouble();

    return WizardScaffold(
      currentStep: currentStep,
      totalSteps: totalSteps,
      // Last step has nothing useful to go back to (re-running the test
      // step would be confusing). The "Configurar otro" CTA gives the
      // user an explicit return path to step 2 if they want.
      showBack: false,
      primaryLabel: 'Empezar a usar bolsio',
      onPrimary: onFinish,
      secondaryLabel: 'Otro proveedor',
      onSecondary: onConfigureAnother,
      secondaryLeadingIcon: Icons.add_circle_outline,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: V3Tokens.space16),
          Text(
            'Tu IA\nestá lista',
            style: V3Tokens.displayStyle(
              size: heroSize,
              letterSpacing: -3.5,
              height: 0.95,
              color: scheme.onSurface,
            ),
          ),
          const SizedBox(height: V3Tokens.space16),
          Container(
            width: 64,
            height: 3,
            decoration: BoxDecoration(
              color: V3Tokens.accent,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const SizedBox(height: V3Tokens.space24),
          Text(
            'Vamos a usar ${credentials.providerType.displayName} con el modelo $effectiveModel para todas las funciones de IA.',
            style: V3Tokens.uiStyle(
              size: 14,
              weight: FontWeight.w500,
              color: scheme.onSurfaceVariant,
              height: 1.45,
            ),
          ),
          const SizedBox(height: V3Tokens.space24),

          // Visual summary card — provider + model + active pill.
          _SummaryCard(
            providerName: credentials.providerType.displayName,
            model: effectiveModel,
          ),

          const SizedBox(height: V3Tokens.space24),
          const _Feature(
            icon: Icons.label_outline,
            text: 'Categorización automática activada',
          ),
          const SizedBox(height: V3Tokens.spaceMd),
          const _Feature(
            icon: Icons.notifications_active_outlined,
            text: 'Parser de notificaciones disponible',
          ),
          const SizedBox(height: V3Tokens.spaceMd),
          const _Feature(
            icon: Icons.chat_bubble_outline,
            text: 'Chat de finanzas listo en el dashboard',
          ),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.providerName,
    required this.model,
  });

  final String providerName;
  final String model;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(V3Tokens.space16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(V3Tokens.radiusMd),
        border: Border.all(
          color: V3Tokens.accent.withValues(alpha: 0.35),
          width: 1,
        ),
      ),
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
          const SizedBox(width: V3Tokens.space16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  providerName,
                  style: V3Tokens.uiStyle(
                    size: 15,
                    weight: FontWeight.w700,
                    color: scheme.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  model,
                  style: V3Tokens.uiStyle(
                    size: 13,
                    weight: FontWeight.w500,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: V3Tokens.accent,
              borderRadius: BorderRadius.circular(V3Tokens.radiusPill),
            ),
            child: Text(
              'Activo',
              style: V3Tokens.uiStyle(
                size: 11,
                weight: FontWeight.w800,
                color: const Color(0xFF0A0A0A),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Feature extends StatelessWidget {
  const _Feature({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: V3Tokens.accent, size: 22),
        const SizedBox(width: V3Tokens.spaceMd),
        Expanded(child: Text(text)),
      ],
    );
  }
}
