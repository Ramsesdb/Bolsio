import 'package:flutter/material.dart';
import 'package:wallex/app/onboarding/theme/v3_tokens.dart';
import 'package:wallex/app/onboarding/widgets/v3_goal_chip.dart';
import 'package:wallex/app/onboarding/widgets/v3_slide_template.dart';

class GoalOption {
  const GoalOption({
    required this.id,
    required this.label,
    required this.icon,
  });
  final String id;
  final String label;
  final IconData icon;
}

const kOnboardingGoals = <GoalOption>[
  GoalOption(id: 'track_expenses', label: 'Controlar gastos', icon: Icons.receipt_long),
  GoalOption(id: 'save_usd', label: 'Ahorrar en USD', icon: Icons.attach_money),
  GoalOption(id: 'reduce_debt', label: 'Reducir deudas', icon: Icons.trending_down),
  GoalOption(id: 'budget', label: 'Presupuestar', icon: Icons.pie_chart),
  GoalOption(id: 'analyze', label: 'Analizar finanzas', icon: Icons.insights),
];

class Slide01Goals extends StatelessWidget {
  const Slide01Goals({
    super.key,
    required this.selectedGoals,
    required this.onToggle,
    required this.onNext,
  });

  final Set<String> selectedGoals;
  final void Function(String id) onToggle;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return V3SlideTemplate(
      primaryLabel: 'Siguiente',
      onPrimary: onNext,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '¿Qué quieres lograr?',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: V3Tokens.spaceMd),
          Text(
            'Selecciona todos los objetivos que apliquen. Puedes cambiarlos luego.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: V3Tokens.space24),
          Wrap(
            spacing: V3Tokens.spaceMd,
            runSpacing: V3Tokens.spaceMd,
            children: [
              for (final g in kOnboardingGoals)
                V3GoalChip(
                  label: g.label,
                  icon: g.icon,
                  selected: selectedGoals.contains(g.id),
                  onTap: () => onToggle(g.id),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
