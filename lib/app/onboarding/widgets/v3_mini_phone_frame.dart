import 'package:flutter/material.dart';
import 'package:kilatex/app/onboarding/theme/v3_tokens.dart';

/// Stylised mini-phone mockup used in slides 5 and 7 of the v3 onboarding
/// flow. Renders a fixed-width 300px phone shell (bezel + inner AMOLED
/// surface + status bar) and exposes a [child] slot for the screen content.
///
/// The frame is intentionally not responsive — the v3 spec uses the same
/// fixed dimensions across breakpoints and centers the device horizontally.
/// Wrap the result in `Align(alignment: Alignment.topCenter)` (or similar)
/// when embedding in a wider parent.
class V3MiniPhoneFrame extends StatelessWidget {
  const V3MiniPhoneFrame({
    super.key,
    this.child,
    this.height = 260,
    this.dark,
  });

  final Widget? child;
  final double height;

  /// Force dark/light bezel. When `null`, derives from the ambient
  /// [Theme.brightness].
  final bool? dark;

  static const double _width = 300;

  @override
  Widget build(BuildContext context) {
    final isDark = dark ?? Theme.of(context).brightness == Brightness.dark;
    final bezel = isDark ? V3Tokens.bezelDark : V3Tokens.bezelLight;
    final bezelInner =
        isDark ? V3Tokens.bezelInnerDark : V3Tokens.bezelInnerLight;
    // boxShadow varies by mode — dark uses a thin inner stroke, light uses
    // a soft drop shadow + hairline border, matching the v3 HTML.
    final shadows = isDark
        ? <BoxShadow>[
            // 1px inner stroke approximated by a 0-blur outset shadow.
            BoxShadow(
              color: Colors.white.withValues(alpha: 0.08),
              blurRadius: 0,
              spreadRadius: 1,
            ),
          ]
        : <BoxShadow>[
            BoxShadow(
              color: const Color(0xFF1E160C).withValues(alpha: 0.12),
              blurRadius: 40,
              offset: const Offset(0, 20),
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 0,
              spreadRadius: 1,
            ),
          ];

    return Container(
      width: _width,
      height: height,
      decoration: BoxDecoration(
        color: bezel,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(48)),
        boxShadow: shadows,
      ),
      // padding: 8 8 0 8 — bottom is 0 because the bezel is "open" at the
      // bottom (the phone visually merges with the slide background).
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      clipBehavior: Clip.antiAlias,
      child: Container(
        decoration: BoxDecoration(
          color: bezelInner,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(42)),
        ),
        padding: const EdgeInsets.fromLTRB(12, 14, 12, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _StatusBar(isDark: isDark),
            const SizedBox(height: 14),
            if (child != null) Expanded(child: child!),
          ],
        ),
      ),
    );
  }
}

/// Mini status bar — "09:41" left, central notch dot, wifi + battery right.
class _StatusBar extends StatelessWidget {
  const _StatusBar({required this.isDark});

  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final muted = isDark ? V3Tokens.mutedDark : V3Tokens.mutedLight;
    final notchColor = isDark ? Colors.black : const Color(0xFF555555);

    return SizedBox(
      height: 12,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Left: "09:41"
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '09:41',
              style: V3Tokens.uiStyle(
                size: 10,
                weight: FontWeight.w600,
                color: muted,
              ),
            ),
          ),
          // Right: wifi bars + battery
          Align(
            alignment: Alignment.centerRight,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(Icons.wifi, size: 10, color: muted),
                const SizedBox(width: 4),
                _BatteryGlyph(color: muted),
              ],
            ),
          ),
          // Center top: notch dot. Top:6 in HTML, centered horizontally.
          Positioned(
            top: -8,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: notchColor,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Tiny battery icon: 16x8 rounded rectangle with a 1px border + small nub.
class _BatteryGlyph extends StatelessWidget {
  const _BatteryGlyph({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 16,
          height: 8,
          decoration: BoxDecoration(
            border: Border.all(color: color, width: 1),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        Container(
          width: 1.5,
          height: 4,
          margin: const EdgeInsets.only(left: 1),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(0.5),
          ),
        ),
      ],
    );
  }
}
