import 'package:flutter/material.dart';

/// Design tokens for the v3 onboarding flow. Scoped to the onboarding
/// module — do not import from outside `lib/app/onboarding/`.
class V3Tokens {
  V3Tokens._();

  /// Brand accent used as a fallback when dynamic colors (Material You)
  /// are not available or not expressive enough.
  static const Color accent = Color(0xFFC8B560);

  /// Halo color for the `v3-pulse` animation on the activate-listener tile.
  static const Color pulseHalo = Color(0x26C8B560); // rgba(200,181,96,0.15)

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
}
