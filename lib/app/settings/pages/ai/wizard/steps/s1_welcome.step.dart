import 'package:flutter/material.dart';
import 'package:bolsio/app/onboarding/theme/v3_tokens.dart';
import 'package:bolsio/app/settings/pages/ai/wizard/widgets/wizard_scaffold.dart';

/// Step 1 of the AI setup wizard — welcome screen with a value pitch and
/// the "Empezar" / "Después" CTA pair.
class S1WelcomeStep extends StatelessWidget {
  const S1WelcomeStep({
    super.key,
    required this.currentStep,
    required this.totalSteps,
    required this.onStart,
    required this.onLater,
  });

  final int currentStep;
  final int totalSteps;
  final VoidCallback onStart;
  final VoidCallback onLater;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final width = MediaQuery.of(context).size.width;
    final double computed = width * 0.18;
    final double heroSize = computed.clamp(48.0, 72.0).toDouble();

    return WizardScaffold(
      currentStep: currentStep,
      totalSteps: totalSteps,
      // First step has no back affordance — `onLater` is the only escape
      // hatch and lives on the secondary CTA.
      showBack: false,
      primaryLabel: 'Empezar',
      onPrimary: onStart,
      secondaryLabel: 'Después',
      onSecondary: onLater,
      // Keep the secondary's leading icon symmetric with the rest of the
      // wizard — `Icons.close` reads as "dismiss" without committing to
      // the harsher `cancel` semantic.
      secondaryLeadingIcon: Icons.close,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: V3Tokens.space16),
          Text(
            'Configurá\ntu IA',
            style: V3Tokens.displayStyle(
              size: heroSize,
              letterSpacing: -3.0,
              height: 0.95,
              color: scheme.onSurface,
            ),
          ),
          const SizedBox(height: V3Tokens.space16),
          // Accent underline bar — same as s11_ready uses below the hero.
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
            'Conectá un proveedor de IA en menos de un minuto y desbloqueá las funciones inteligentes de bolsio.',
            style: V3Tokens.uiStyle(
              size: 14,
              weight: FontWeight.w500,
              color: scheme.onSurfaceVariant,
              height: 1.45,
            ),
          ),
          const SizedBox(height: V3Tokens.space24),
          const _Feature(
            icon: Icons.label_outline,
            title: 'Categorización automática',
            body:
                'Sugiere la categoría exacta para cada movimiento que importes.',
          ),
          const SizedBox(height: V3Tokens.space16),
          const _Feature(
            icon: Icons.notifications_active_outlined,
            title: 'Parser de notificaciones',
            body:
                'Lee notificaciones de bancos y crea transacciones por vos.',
          ),
          const SizedBox(height: V3Tokens.space16),
          const _Feature(
            icon: Icons.chat_bubble_outline,
            title: 'Chat de finanzas',
            body:
                'Hacé preguntas como "¿cuánto gasté en comida este mes?" y obtené respuestas al instante.',
          ),
          const SizedBox(height: V3Tokens.space24),
          // Small reassurance row mirroring s06_privacy's "datos en tu
          // dispositivo" framing — keeps the BYOK story honest.
          _Reassurance(
            text:
                'Tu API key se guarda cifrada en tu dispositivo. Nunca la enviamos a nuestros servidores.',
          ),
        ],
      ),
    );
  }
}

class _Feature extends StatelessWidget {
  const _Feature({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: V3Tokens.accent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(V3Tokens.radiusMd),
          ),
          alignment: Alignment.center,
          child: Icon(icon, color: V3Tokens.accent, size: 20),
        ),
        const SizedBox(width: V3Tokens.space16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 2),
              Text(
                body,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Reassurance extends StatelessWidget {
  const _Reassurance({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(V3Tokens.space16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(V3Tokens.radiusMd),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lock_outline, color: scheme.onSurfaceVariant, size: 18),
          const SizedBox(width: V3Tokens.spaceMd),
          Expanded(
            child: Text(
              text,
              style: V3Tokens.uiStyle(
                size: 12,
                weight: FontWeight.w500,
                color: scheme.onSurfaceVariant,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
