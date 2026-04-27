import 'package:flutter/material.dart';

import '../theme/v3_tokens.dart';

/// Custom switch matching the v3 Anthropic design HTML.
///
/// - Track: 36 × 22, radius 999.
///   - ON: `V3Tokens.accent` (#C8B560)
///   - OFF: `borderStrongDark` (rgba 255,255,255,0.14) on dark,
///          `borderStrongLight` (rgba 0,0,0,0.12) on light.
/// - Thumb: 18 × 18, radius 50%, white. Position left:2 (OFF) or left:16 (ON).
/// - Transition: 200ms standard easing.
///
/// `onChanged == null` disables the control (lower opacity, no taps).
class V3Switch extends StatelessWidget {
  const V3Switch({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;

  static const double _trackWidth = 36;
  static const double _trackHeight = 22;
  static const double _thumbSize = 18;
  static const double _thumbInset = 2;
  static const Duration _duration = Duration(milliseconds: 200);
  static const Curve _curve = Curves.easeInOut;

  @override
  Widget build(BuildContext context) {
    final bool disabled = onChanged == null;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    final Color offTrack =
        isDark ? V3Tokens.borderStrongDark : V3Tokens.borderStrongLight;
    final Color trackColor = value ? V3Tokens.accent : offTrack;

    final double thumbLeft =
        value ? (_trackWidth - _thumbSize - _thumbInset) : _thumbInset;

    return Opacity(
      opacity: disabled ? 0.4 : 1.0,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: disabled ? null : () => onChanged!(!value),
        child: SizedBox(
          width: _trackWidth,
          height: _trackHeight,
          child: Stack(
            children: [
              AnimatedContainer(
                duration: _duration,
                curve: _curve,
                width: _trackWidth,
                height: _trackHeight,
                decoration: BoxDecoration(
                  color: trackColor,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              AnimatedPositioned(
                duration: _duration,
                curve: _curve,
                top: _thumbInset,
                left: thumbLeft,
                width: _thumbSize,
                height: _thumbSize,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(_thumbSize / 2),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x26000000), // ~0.15 alpha
                        blurRadius: 4,
                        offset: Offset(0, 1),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
