import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/v3_tokens.dart';

/// Secondary "Skip / Back" pill button for the v3 onboarding.
///
/// Visuals follow the official Anthropic v3 design HTML:
/// - Dark mode: bg `pillBgDark`, fg `mutedDark` (rgba 255,255,255,0.55)
/// - Light mode: bg `pillBgLight`, fg `mutedLight` (rgba 20,20,20,0.55)
/// - Pill (radius 999), padding 26h × 15v, Gabarito 700 / 14 / letterSpacing -0.2.
class V3SecondaryButton extends StatelessWidget {
  const V3SecondaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.leadingIcon,
    this.trailingIcon,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? leadingIcon;
  final IconData? trailingIcon;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bool disabled = onPressed == null;

    final Color bg = isDark ? V3Tokens.pillBgDark : V3Tokens.pillBgLight;
    final Color fg = isDark ? V3Tokens.mutedDark : V3Tokens.mutedLight;

    final TextStyle labelStyle = GoogleFonts.gabarito(
      fontSize: 14,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.2,
      color: fg,
    );

    final children = <Widget>[
      if (leadingIcon != null) ...[
        Icon(leadingIcon, size: 16, color: fg),
        const SizedBox(width: 8),
      ],
      Flexible(
        child: Text(
          label,
          style: labelStyle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      if (trailingIcon != null) ...[
        const SizedBox(width: 8),
        Icon(trailingIcon, size: 16, color: fg),
      ],
    ];

    return Opacity(
      opacity: disabled ? 0.4 : 1.0,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: disabled ? null : onPressed,
          borderRadius: BorderRadius.circular(V3Tokens.radiusPill),
          child: Ink(
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(V3Tokens.radiusPill),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 26,
                vertical: 15,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: children,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
