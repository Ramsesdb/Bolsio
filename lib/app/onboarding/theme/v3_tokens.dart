import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Design tokens for the v3 onboarding flow. Scoped to the onboarding
/// module — do not import from outside `lib/app/onboarding/`.
class V3Tokens {
  V3Tokens._();

  /// Brand accent used as a fallback when dynamic colors (Material You)
  /// are not available or not expressive enough.
  static const Color accent = Color(0xFF00897B);

  /// Halo color for the `v3-pulse` animation on the activate-listener tile.
  static const Color pulseHalo = Color(0x2600897B); // rgba(0,137,123,0.15)

  // ── Surfaces & pill backgrounds ──
  /// Frame surface used in primary buttons in dark mode.
  static const Color surfaceFrameDark = Color(0xFF1A1A1A);

  /// Pill / secondary button background, dark mode.
  static const Color pillBgDark = Color(0xFF141414);

  /// Pill / secondary button background, light mode.
  static const Color pillBgLight = Color(0xFFF2F0EA);

  // ── Muted foregrounds (used by V3SecondaryButton, status text, etc.) ──
  /// Muted text on dark backgrounds: rgba(255,255,255,0.55).
  static const Color mutedDark = Color(0x8CFFFFFF);

  /// Muted text on light backgrounds: rgba(20,20,20,0.55).
  static const Color mutedLight = Color(0x8C141414);

  // ── Strong borders / V3Switch off-track ──
  /// Strong border on dark surfaces: rgba(255,255,255,0.14).
  static const Color borderStrongDark = Color(0x24FFFFFF);

  /// Strong border on light surfaces: rgba(0,0,0,0.12).
  static const Color borderStrongLight = Color(0x1F000000);

  // ── Faint foregrounds (used to fade out non-target rows in mockups) ──
  /// Faint text on dark backgrounds: rgba(255,255,255,0.38).
  static const Color faintDark = Color(0x61FFFFFF);

  /// Faint text on light backgrounds: rgba(20,20,20,0.38).
  static const Color faintLight = Color(0x61141414);

  // ── V3MiniPhone frame (bezel + AMOLED interior) ──
  /// Outer phone bezel, dark mode. Reuses [surfaceFrameDark] (#1A1A1A).
  static const Color bezelDark = surfaceFrameDark;

  /// Outer phone bezel, light mode (warm off-white).
  static const Color bezelLight = Color(0xFFE8E5DE);

  /// Inner AMOLED screen, dark mode (deeper than bezel).
  static const Color bezelInnerDark = Color(0xFF050505);

  /// Inner screen background, light mode (warm off-white, lighter than bezel).
  static const Color bezelInnerLight = Color(0xFFF7F5EE);

  // ── Spacing scale ──
  static const double spaceXs = 8;
  static const double spaceSm = 10;
  static const double spaceMd = 12;
  static const double spaceLg = 14;
  static const double space16 = 16;
  static const double space22 = 22;
  static const double space24 = 24;
  static const double space26 = 26;

  // ── Radii ──
  static const double radiusPill = 999;
  static const double radiusLg = 22;
  static const double radiusMd = 14;
  static const double radiusSm = 10;

  // ── Animation durations ──
  static const Duration notifInStagger = Duration(milliseconds: 600);
  static const Duration cardIn = Duration(milliseconds: 300);
  static const Duration pulse = Duration(milliseconds: 2400);

  // ── Progress bar ──
  static const double progressBarHeight = 3;
  static const double progressBarTop = 52;

  // ── Typography helpers ──
  /// Display style: Gabarito 900, tight letter-spacing. Used for slide
  /// titles and large headings (38–80px). Defaults match the official v3
  /// design spec (size 56, letter-spacing -2.5).
  static TextStyle displayStyle({
    double size = 56,
    double letterSpacing = -2.5,
    Color? color,
    double? height,
  }) {
    return GoogleFonts.gabarito(
      fontSize: size,
      fontWeight: FontWeight.w900,
      letterSpacing: letterSpacing,
      color: color,
      height: height,
    );
  }

  /// UI style: Inter 500–700. Used for body, status, notifications,
  /// timestamps and button labels.
  static TextStyle uiStyle({
    double size = 14,
    FontWeight weight = FontWeight.w500,
    Color? color,
    double? letterSpacing,
    double? height,
  }) {
    return GoogleFonts.inter(
      fontSize: size,
      fontWeight: weight,
      color: color,
      letterSpacing: letterSpacing,
      height: height,
    );
  }
}
