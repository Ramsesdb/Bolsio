import 'package:flutter/material.dart';
import 'package:bolsio/app/onboarding/theme/v3_tokens.dart';
import 'package:bolsio/app/onboarding/widgets/v3_switch.dart';

/// Geometric placeholder tile for bank logos. Used both in slide 4
/// (selectable, single-column layout) and slide 8 (toggleable). When
/// [onChanged] is provided, the tile renders a [V3Switch]; otherwise it's a
/// tappable selection card with a check/radio indicator.
///
/// Layout follows the official v3 HTML spec:
/// - Card padding: 14h × 11v
/// - Card border-radius: 14
/// - Logo: 32×32, border-radius 9, brand color background
/// - Gap logo↔text: 12
/// - Name: Inter weight 700, size 13.5, letter-spacing -0.2
class V3BankTile extends StatelessWidget {
  const V3BankTile({
    super.key,
    required this.name,
    required this.brandColor,
    required this.icon,
    required this.selected,
    required this.onTap,
    this.onChanged,
    this.onRemove,
    this.badgeLabel,
  });

  final String name;
  final Color brandColor;
  final IconData icon;
  final bool selected;
  final VoidCallback? onTap;

  /// If non-null, a V3Switch is rendered instead of a selection check.
  /// Pass `null` here while [onChanged] is still expected by callers to
  /// disable the switch visually (Opacity 0.4, no taps). Used for tiles
  /// shown with a "Próximamente" badge — they're acknowledged but the
  /// underlying parser doesn't exist yet.
  final ValueChanged<bool>? onChanged;

  /// If non-null, a small muted close (×) button is rendered after the
  /// trailing switch / check, inside the tile's border. Tapping it invokes
  /// the callback. The button is intentionally low-contrast (secondary
  /// affordance), so it does not compete visually with the switch.
  final VoidCallback? onRemove;

  /// Optional small uppercase pill rendered between the name and the
  /// trailing switch. Used to mark tiles whose parser is not implemented
  /// yet (e.g. "Próximamente"). Style follows V3Tokens.accent at alpha
  /// 0.14 with the accent color as foreground.
  final String? badgeLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = scheme.onSurface;
    final mutedColor = isDark ? V3Tokens.mutedDark : V3Tokens.mutedLight;
    // Slide 4 (selectable card) mode: no toggle widget AND no badge.
    // The card uses the accent-tinted look when [selected].
    final bool selectionMode = onChanged == null && badgeLabel == null;
    return InkWell(
      onTap: selectionMode ? onTap : null,
      borderRadius: BorderRadius.circular(V3Tokens.radiusMd),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 11,
        ),
        decoration: BoxDecoration(
          color: selected && selectionMode
              ? V3Tokens.accent.withValues(alpha: 0.08)
              : scheme.surface,
          borderRadius: BorderRadius.circular(V3Tokens.radiusMd),
          border: Border.all(
            color: selected && selectionMode
                ? V3Tokens.accent
                : scheme.outlineVariant,
            width: selected && selectionMode ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: brandColor,
                borderRadius: BorderRadius.circular(9),
              ),
              alignment: Alignment.center,
              child: Icon(icon, color: Colors.white, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                name,
                style: V3Tokens.uiStyle(
                  size: 13.5,
                  weight: FontWeight.w700,
                  letterSpacing: -0.2,
                  color: textColor,
                ),
                maxLines: 2,
                softWrap: true,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (badgeLabel != null) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: V3Tokens.accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(V3Tokens.radiusPill),
                ),
                child: Text(
                  badgeLabel!.toUpperCase(),
                  style: V3Tokens.uiStyle(
                    size: 9,
                    weight: FontWeight.w600,
                    letterSpacing: 0.6,
                    color: V3Tokens.accent,
                  ),
                ),
              ),
              const SizedBox(width: 8),
            ],
            if (onChanged != null || badgeLabel != null)
              V3Switch(
                value: selected,
                onChanged: onChanged,
              )
            else
              Icon(
                selected ? Icons.check_circle : Icons.radio_button_off,
                color: selected ? V3Tokens.accent : scheme.outline,
              ),
            if (onRemove != null) ...[
              const SizedBox(width: 8),
              InkWell(
                onTap: onRemove,
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  width: 32,
                  height: 32,
                  alignment: Alignment.center,
                  child: Icon(
                    Icons.close,
                    size: 18,
                    color: mutedColor,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
