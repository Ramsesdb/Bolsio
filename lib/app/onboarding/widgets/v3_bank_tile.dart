import 'package:flutter/material.dart';
import 'package:wallex/app/onboarding/theme/v3_tokens.dart';

/// Geometric placeholder tile for bank logos. Used both in slide 4
/// (selectable) and slide 8 (toggleable). When [onChanged] is provided,
/// the tile renders a Switch; otherwise it's a tappable selection card.
class V3BankTile extends StatelessWidget {
  const V3BankTile({
    super.key,
    required this.name,
    required this.brandColor,
    required this.icon,
    required this.selected,
    required this.onTap,
    this.onChanged,
  });

  final String name;
  final Color brandColor;
  final IconData icon;
  final bool selected;
  final VoidCallback? onTap;

  /// If non-null, a Switch is rendered instead of a selection check.
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onChanged == null ? onTap : null,
      borderRadius: BorderRadius.circular(V3Tokens.radiusMd),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(
          horizontal: V3Tokens.spaceMd,
          vertical: V3Tokens.spaceSm,
        ),
        decoration: BoxDecoration(
          color: selected && onChanged == null
              ? V3Tokens.accent.withValues(alpha: 0.08)
              : scheme.surface,
          borderRadius: BorderRadius.circular(V3Tokens.radiusMd),
          border: Border.all(
            color: selected && onChanged == null
                ? V3Tokens.accent
                : scheme.outlineVariant,
            width: selected && onChanged == null ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: brandColor,
                borderRadius: BorderRadius.circular(V3Tokens.radiusSm),
              ),
              alignment: Alignment.center,
              child: Icon(icon, color: Colors.white, size: 20),
            ),
            const SizedBox(width: V3Tokens.spaceMd),
            Expanded(
              child: Text(
                name,
                style: const TextStyle(fontWeight: FontWeight.w500),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (onChanged != null)
              Switch(value: selected, onChanged: onChanged)
            else
              Icon(
                selected ? Icons.check_circle : Icons.radio_button_off,
                color: selected ? V3Tokens.accent : scheme.outline,
              ),
          ],
        ),
      ),
    );
  }
}
