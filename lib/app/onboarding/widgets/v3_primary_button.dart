import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/v3_tokens.dart';

/// Primary "Continue / Next" pill button for the v3 onboarding.
///
/// Visuals follow the official Anthropic v3 design HTML:
/// - Dark mode: bg `surfaceFrameDark`, fg `accent`, 1px border `accent` @ alpha 0.4
/// - Light mode: bg `accent`, fg black, no border
/// - Pill (radius 999), padding 26h × 15v, Gabarito 700 / 14 / letterSpacing -0.2
/// - Optional [leadingIcon] with an 8px gap (rendered before the label)
/// - Optional [trailingIcon] with an 8px gap (rendered after the label)
/// - [loading] swaps the trailing area for a small progress indicator and
///   disables tap.
class V3PrimaryButton extends StatelessWidget {
  const V3PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.leadingIcon,
    this.trailingIcon,
    this.loading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? leadingIcon;
  final IconData? trailingIcon;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final isDark = brightness == Brightness.dark;
    final bool disabled = onPressed == null || loading;

    final Color bg;
    final Color fg;
    final BoxBorder? border;

    if (isDark) {
      bg = V3Tokens.surfaceFrameDark;
      fg = V3Tokens.accent;
      border = Border.all(
        color: V3Tokens.accent.withAlpha(0x66), // ~0.4
        width: 1,
      );
    } else {
      bg = V3Tokens.accent;
      fg = Colors.black;
      border = null;
    }

    final double opacity = disabled ? 0.4 : 1.0;

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
      if (loading) ...[
        const SizedBox(width: 8),
        SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(fg),
          ),
        ),
      ] else if (trailingIcon != null) ...[
        const SizedBox(width: 8),
        Icon(trailingIcon, size: 16, color: fg),
      ],
    ];

    return Opacity(
      opacity: opacity,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: disabled ? null : onPressed,
          borderRadius: BorderRadius.circular(V3Tokens.radiusPill),
          child: Ink(
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(V3Tokens.radiusPill),
              border: border,
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
