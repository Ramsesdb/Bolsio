import 'package:flutter/material.dart';
import 'package:kilatex/app/onboarding/theme/v3_tokens.dart';
import 'package:kilatex/core/services/ai/ai_provider_type.dart';

/// Selectable radio-style card for an AI provider in the wizard.
///
/// Visuals match the `_GoalRow` from `s01_goals.dart` (selected → accent
/// border @ 0.4 alpha, surfaceContainerHighest fill; unselected → faint
/// border, transparent fill) but with a richer body: leading icon tile,
/// provider name, short description, default-model badge, and an
/// "already configured" pill when applicable.
class WizardProviderCard extends StatelessWidget {
  const WizardProviderCard({
    super.key,
    required this.provider,
    required this.description,
    required this.selected,
    required this.onTap,
    this.recommended = false,
    this.alreadyConfigured = false,
  });

  final AiProviderType provider;
  final String description;
  final bool selected;
  final VoidCallback onTap;

  /// Adds a "Recomendado" pill next to the provider name. Used by the wizard
  /// to nudge new users toward the Nexus gateway when they have a token.
  final bool recommended;

  /// Adds a "Ya configurado" indicator when the user already has a key
  /// stored for this provider.
  final bool alreadyConfigured;

  /// Maps a provider to a representative Material icon. Avoids external
  /// asset downloads (per the task brief) — emoji would clash with the
  /// monochrome aesthetic of the onboarding tiles.
  IconData get _icon {
    switch (provider) {
      case AiProviderType.nexus:
        return Icons.hub_outlined;
      case AiProviderType.openai:
        return Icons.bolt_outlined;
      case AiProviderType.anthropic:
        return Icons.psychology_outlined;
      case AiProviderType.gemini:
        return Icons.auto_awesome;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final Color borderColor = selected
        ? V3Tokens.accent.withValues(alpha: 0.4)
        : (isDark
            ? const Color(0x0FFFFFFF)
            : const Color(0x0F000000));
    final Color bg =
        selected ? scheme.surfaceContainerHighest : Colors.transparent;
    final Color fg = scheme.onSurface;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(V3Tokens.radiusMd),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(V3Tokens.radiusMd),
          border: Border.all(color: borderColor, width: 1),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Leading icon tile — same accent-tinted square the privacy
            // bullets in s06 use.
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: V3Tokens.accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(V3Tokens.radiusMd),
              ),
              alignment: Alignment.center,
              child: Icon(_icon, color: V3Tokens.accent, size: 20),
            ),
            const SizedBox(width: V3Tokens.space16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          provider.displayName,
                          style: V3Tokens.uiStyle(
                            size: 15,
                            weight: selected
                                ? FontWeight.w700
                                : FontWeight.w600,
                            color: fg,
                          ),
                        ),
                      ),
                      if (recommended) ...[
                        const SizedBox(width: V3Tokens.spaceXs),
                        const _Pill(label: 'Recomendado'),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: V3Tokens.uiStyle(
                      size: 13,
                      weight: FontWeight.w500,
                      color: scheme.onSurfaceVariant,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        Icons.bolt,
                        size: 14,
                        color: scheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          provider.defaultModel,
                          style: V3Tokens.uiStyle(
                            size: 12,
                            weight: FontWeight.w500,
                            color: scheme.onSurfaceVariant,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (alreadyConfigured) ...[
                        const SizedBox(width: V3Tokens.spaceSm),
                        Icon(
                          Icons.check_circle,
                          size: 14,
                          color: V3Tokens.accent,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Ya configurado',
                          style: V3Tokens.uiStyle(
                            size: 12,
                            weight: FontWeight.w600,
                            color: V3Tokens.accent,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: V3Tokens.spaceSm),
            _Radio(selected: selected),
          ],
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: V3Tokens.accent.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(V3Tokens.radiusPill),
      ),
      child: Text(
        label,
        style: V3Tokens.uiStyle(
          size: 11,
          weight: FontWeight.w700,
          color: V3Tokens.accent,
        ),
      ),
    );
  }
}

class _Radio extends StatelessWidget {
  const _Radio({required this.selected});
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final Color uncheckedBorder = isDark
        ? const Color(0x24FFFFFF)
        : const Color(0x24000000);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? V3Tokens.accent : Colors.transparent,
        border: Border.all(
          color: selected ? V3Tokens.accent : uncheckedBorder,
          width: 1,
        ),
      ),
      alignment: Alignment.center,
      child: selected
          ? const Icon(
              Icons.check_rounded,
              size: 14,
              color: Color(0xFF0A0A0A),
            )
          : null,
    );
  }
}
