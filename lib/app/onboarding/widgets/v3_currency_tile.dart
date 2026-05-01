import 'package:flutter/material.dart';
import 'package:nitido/app/onboarding/theme/v3_tokens.dart';

class V3CurrencyTile extends StatelessWidget {
  const V3CurrencyTile({
    super.key,
    required this.code,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final String code;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final borderColor = selected ? V3Tokens.accent : scheme.outlineVariant;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(V3Tokens.radiusLg),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(V3Tokens.space16),
        decoration: BoxDecoration(
          color: selected
              ? V3Tokens.accent.withValues(alpha: 0.08)
              : scheme.surface,
          borderRadius: BorderRadius.circular(V3Tokens.radiusLg),
          border: Border.all(color: borderColor, width: selected ? 2 : 1),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: V3Tokens.accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(V3Tokens.radiusMd),
              ),
              alignment: Alignment.center,
              child: Text(
                code,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: V3Tokens.accent,
                ),
              ),
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
                    subtitle,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: selected ? V3Tokens.accent : scheme.outline,
            ),
          ],
        ),
      ),
    );
  }
}
