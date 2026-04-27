import 'package:flutter/material.dart';
import 'package:wallex/app/onboarding/theme/v3_tokens.dart';
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
  GoalOption(id: 'track_expenses', label: 'Organizar mis gastos', icon: Icons.receipt_long),
  GoalOption(id: 'save_usd', label: 'Ahorrar en dólares', icon: Icons.attach_money),
  GoalOption(id: 'reduce_debt', label: 'Pagar mis deudas', icon: Icons.trending_down),
  GoalOption(id: 'budget', label: 'Crear un presupuesto', icon: Icons.pie_chart),
  GoalOption(id: 'analyze', label: 'Finanzas en pareja o negocio', icon: Icons.groups_outlined),
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
            '¿Qué deseas lograr?',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: V3Tokens.spaceMd),
          Text(
            'Selecciona uno o más. Personalizamos tu pantalla principal.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: V3Tokens.space24),
          Column(
            children: [
              for (final g in kOnboardingGoals) ...[
                _GoalRow(
                  label: g.label,
                  icon: g.icon,
                  selected: selectedGoals.contains(g.id),
                  onTap: () => onToggle(g.id),
                ),
                const SizedBox(height: V3Tokens.spaceSm),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _GoalRow extends StatelessWidget {
  const _GoalRow({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final Color borderColor = selected
        ? V3Tokens.accent.withValues(alpha: 0.4)
        : (isDark
            ? const Color(0x0FFFFFFF) // ~0.06 alpha white
            : const Color(0x0F000000)); // ~0.06 alpha black
    final Color bg = selected ? scheme.surfaceContainerHighest : Colors.transparent;
    final Color fg = scheme.onSurface;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(V3Tokens.radiusMd),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 16,
        ),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(V3Tokens.radiusMd),
          border: Border.all(color: borderColor, width: 1),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: selected ? V3Tokens.accent : fg),
            const SizedBox(width: V3Tokens.spaceMd),
            Expanded(
              child: Text(
                label,
                style: V3Tokens.uiStyle(
                  size: 14,
                  weight: selected ? FontWeight.w600 : FontWeight.w500,
                  color: fg,
                ),
              ),
            ),
            _GoalCheckbox(selected: selected),
          ],
        ),
      ),
    );
  }
}

class _GoalCheckbox extends StatelessWidget {
  const _GoalCheckbox({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final Color uncheckedBorder = isDark
        ? const Color(0x24FFFFFF) // ~0.14 alpha white
        : const Color(0x24000000); // ~0.14 alpha black

    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        color: selected ? V3Tokens.accent : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: selected ? V3Tokens.accent : uncheckedBorder,
          width: 1,
        ),
      ),
      alignment: Alignment.center,
      child: selected
          ? const Icon(
              Icons.check_rounded,
              size: 16,
              color: Color(0xFF0A0A0A),
            )
          : null,
    );
  }
}
