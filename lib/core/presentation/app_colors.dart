import 'package:flutter/material.dart';

/// Bolsio brand color (very dark muted purple — used for glass surfaces).
const brandBlue = Color(0xFF1E1B2E);

/// Muted gray-purple accent for active text/icons.
const accentMuted = Color(0xFF8B85A8);

class AppColors extends ThemeExtension<AppColors> {
  const AppColors({required this.colors});

  final Map<String, Color> colors;

  // Getters for type-safe access with autocompletion
  Color get link => colors['link']!;
  Color get danger => colors['danger']!;
  Color get success => colors['success']!;
  Color get brand => colors['brand']!;
  Color get shadowColor => colors['shadowColor']!;
  Color get shadowColorLight => colors['shadowColorLight']!;
  Color get textBody => colors['textBody']!;
  Color get textHint => colors['textHint']!;
  Color get modalBackground => colors['modalBackground']!;
  Color get consistentPrimary => colors['consistentPrimary']!;
  Color get onConsistentPrimary => colors['onConsistentPrimary']!;
  Color get white => colors['white']!;
  Color get black => colors['black']!;
  Color get accentMuted => colors['accentMuted']!;

  /// Full-opacity text on the dashboard header gradient.
  /// Dark: white — Light: dark navy for contrast on teal.
  Color get onHeader => colors['onHeader']!;

  /// Semi-transparent text on the dashboard header (labels, secondary info).
  /// Dark: white @ 70% — Light: black @ 65%.
  Color get onHeaderMuted => colors['onHeaderMuted']!;

  /// Very faint text / dividers on the dashboard header.
  /// Dark: white @ 45% — Light: black @ 45%.
  Color get onHeaderSubtle => colors['onHeaderSubtle']!;

  static AppColors fromColorScheme(ColorScheme colorScheme) {
    final isDark = colorScheme.brightness == Brightness.dark;

    return AppColors(
      colors: {
        'link': isDark ? Colors.blue.shade200 : Colors.blue.shade700,
        'danger': isDark ? Colors.redAccent : Colors.red,
        'success': isDark
            ? Colors.lightGreen
            : const Color.fromARGB(255, 55, 161, 59),
        'brand': isDark ? const Color.fromARGB(255, 128, 134, 177) : brandBlue,
        'shadowColor': isDark
            ? const Color.fromARGB(105, 189, 189, 189)
            : const Color.fromARGB(100, 90, 90, 90),
        'shadowColorLight': isDark
            ? Colors.transparent
            : const Color.fromARGB(44, 90, 90, 90),
        'textBody': isDark
            ? const Color.fromARGB(245, 211, 211, 211)
            : const Color.fromARGB(255, 67, 67, 67),
        'textHint': isDark
            ? const Color.fromARGB(255, 153, 153, 153)
            : const Color.fromARGB(255, 123, 123, 123),
        'modalBackground': colorScheme.surfaceContainer,
        'accentMuted': isDark
            ? colorScheme.primary.withValues(alpha: 0.7)
            : colorScheme.primary,
        'consistentPrimary': isDark
            ? colorScheme.primaryContainer
            : colorScheme.primary,
        'onConsistentPrimary': isDark
            ? colorScheme.onPrimaryContainer
            : colorScheme.onPrimary,
        'white': !isDark ? Colors.white : Colors.black,
        'black': isDark ? Colors.white : Colors.black,
        'onHeader': isDark ? Colors.white : const Color(0xFF1A1A2E),
        'onHeaderMuted': isDark
            ? Colors.white.withValues(alpha: 0.7)
            : Colors.black.withValues(alpha: 0.65),
        'onHeaderSubtle': isDark
            ? Colors.white.withValues(alpha: 0.45)
            : Colors.black.withValues(alpha: 0.45),
      },
    );
  }

  static AppColors of(BuildContext context) {
    return Theme.of(context).extension<AppColors>()!;
  }

  @override
  AppColors copyWith({Map<String, Color>? colors}) {
    return AppColors(colors: colors ?? this.colors);
  }

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) {
      return this;
    }

    final lerpedColors = <String, Color>{};
    colors.forEach((key, value) {
      lerpedColors[key] = Color.lerp(value, other.colors[key], t)!;
    });

    return AppColors(colors: lerpedColors);
  }
}
