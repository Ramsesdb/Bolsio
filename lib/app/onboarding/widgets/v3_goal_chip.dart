import 'package:flutter/material.dart';
import 'package:kilatex/app/onboarding/theme/v3_tokens.dart';

class V3GoalChip extends StatelessWidget {
  const V3GoalChip({
    super.key,
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
    final bg = selected
        ? V3Tokens.accent.withValues(alpha: 0.15)
        : scheme.surfaceContainerHighest;
    final fg = selected ? V3Tokens.accent : scheme.onSurface;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(V3Tokens.radiusPill),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(
          horizontal: V3Tokens.space16,
          vertical: V3Tokens.spaceMd,
        ),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(V3Tokens.radiusPill),
          border: Border.all(
            color: selected ? V3Tokens.accent : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: fg),
            const SizedBox(width: V3Tokens.spaceXs),
            Text(
              label,
              style: TextStyle(
                color: fg,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
