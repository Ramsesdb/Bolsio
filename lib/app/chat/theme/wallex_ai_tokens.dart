import 'package:flutter/material.dart';
import 'package:kilatex/core/extensions/color.extensions.dart';
import 'package:kilatex/core/presentation/app_colors.dart';

/// Design tokens for the Wallex AI Chat v2 visual redesign.
///
/// Translates the hardcoded tokens from the Claude Design bundle
/// (see `wai-chrome.jsx` / `wallex-theme.jsx`) to the dynamic Wallex
/// theme so chat surfaces follow the user's accent / brightness / amoled
/// selection at runtime.
///
/// API mirrors [AppColors.of] (context-bound accessor). We deliberately
/// do NOT implement [ThemeExtension] because these tokens are scoped to
/// the chat feature; promoting them to a theme extension would be
/// overkill and would force every theme rebuild to carry them.
class WallexAiTokens {
  const WallexAiTokens._(this._context);

  final BuildContext _context;

  /// Context-bound accessor. Usage: `WallexAiTokens.of(context).accent`.
  static WallexAiTokens of(BuildContext context) => WallexAiTokens._(context);

  ColorScheme get _cs => Theme.of(_context).colorScheme;
  AppColors get _app => AppColors.of(_context);
  TextTheme get _tt => Theme.of(_context).textTheme;

  // ---------------------------------------------------------------------------
  // Colors (mapped to dynamic theme)
  // ---------------------------------------------------------------------------

  /// Accent color (design spec `#C8B560`).
  /// Maps to the user's selected/ dynamic primary.
  Color get accent => _cs.primary;

  /// Deeper accent (design spec `#8a772f`), used for pressed states /
  /// gradient stops.
  Color get accentDeep => _cs.primary.darken(0.2);

  /// Text color on top of accent surfaces (user bubbles, accent buttons).
  /// Design spec `#0D0D0D` → `onPrimary` so it adapts to any accent.
  Color get textOnUser => _cs.onPrimary;

  /// Scaffold / page background (design spec `#0D0D0D`, AMOLED `#000`).
  /// Flutter already handles amoled vs dark via `scaffoldBackgroundColor`
  /// in `theme.dart`; we expose both for flexibility.
  Color get scaffold => Theme.of(_context).scaffoldBackgroundColor;
  Color get surface => _cs.surface;

  /// AI chat bubble background (design spec `#1A1A2E`).
  ///
  /// Mapped to `surfaceContainerHighest` (NOT `surfaceContainer` as the
  /// brief initially suggested) to match the existing `wallex_chat.page.dart`
  /// which already paints AI bubbles with `cs.surfaceContainerHighest`.
  /// This preserves visual continuity during the Tanda 2 migration.
  Color get bubbleAi => _cs.surfaceContainerHighest;

  /// Alternate surface for raised chrome (input bar, chips).
  /// Design spec `#26243F` → `surfaceContainerHighest` (same target in
  /// our dark theme; kept as a distinct getter so consumers can express
  /// intent and we can retune later without touching callers).
  Color get surfaceAlt => _cs.surfaceContainerHighest;

  /// Primary text (design spec `#FFFFFF`).
  Color get text => _cs.onSurface;

  /// Secondary text (design spec `rgba(255,255,255,0.55)`).
  Color get muted => _cs.onSurface.withValues(alpha: 0.6);

  /// Tertiary text (design spec `rgba(255,255,255,0.38)`).
  Color get fainter => _cs.onSurface.withValues(alpha: 0.38);

  /// Hairline borders (design spec `rgba(255,255,255,0.06)`).
  ///
  /// Uses `onSurface.withValues(alpha: 0.06)` instead of `outlineVariant`
  /// because `outlineVariant` in Material 3 ColorScheme.fromSeed tends to
  /// carry a visible accent tint that reads as colored against the dark
  /// chat surfaces; the spec explicitly wants a pure low-alpha white line.
  Color get border => _cs.onSurface.withValues(alpha: 0.06);

  /// Divider lines (design spec `rgba(255,255,255,0.08)`).
  Color get divider => _cs.outlineVariant.withValues(alpha: 0.5);

  /// Danger / destructive (design spec `#F75959`).
  Color get danger => _app.danger;

  /// Success / positive (design spec `#4CAF50`).
  Color get success => _app.success;

  // ---------------------------------------------------------------------------
  // Brand constants (accent-independent)
  // ---------------------------------------------------------------------------

  /// Brand identity color for bank hex-tiles. NOT an accent — stays constant
  /// regardless of the user's selected primary.
  /// Design spec: `hexBank` / `purple` / `violet` = `#4B2FD0`.
  static const Color hexBank = Color(0xFF4B2FD0);

  /// Alias for [hexBank] — the design bundle uses both names.
  static const Color purple = hexBank;

  // ---------------------------------------------------------------------------
  // Typography recipes
  // ---------------------------------------------------------------------------

  /// Big balance number display (40pt, ultra-light, tabular).
  /// Pair with [displayCurrencySymbol] for `$1,234.56`-style layouts.
  TextStyle get displayBalance => (_tt.displayMedium ?? const TextStyle())
      .copyWith(
        fontSize: 40,
        fontWeight: FontWeight.w300,
        letterSpacing: -1.5,
        color: _cs.onSurface,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  /// Currency symbol accent that rides next to [displayBalance].
  TextStyle get displayCurrencySymbol =>
      (_tt.displayMedium ?? const TextStyle()).copyWith(
        fontSize: 24,
        fontWeight: FontWeight.w700,
        color: _cs.primary,
      );

  /// Small uppercase label above cards ("INGRESOS", "GASTOS"...).
  /// The consumer is responsible for applying `.toUpperCase()` to the string.
  TextStyle get cardKicker => (_tt.labelSmall ?? const TextStyle()).copyWith(
    fontSize: 10.5,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.6,
    color: muted,
  );

  /// Card title (16pt extra-bold).
  TextStyle get cardTitle => (_tt.titleMedium ?? const TextStyle()).copyWith(
    fontSize: 16,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.3,
    color: _cs.onSurface,
  );

  /// Default chat bubble body (AI side).
  TextStyle get bubbleBody => (_tt.bodyMedium ?? const TextStyle()).copyWith(
    fontSize: 14,
    fontWeight: FontWeight.w500,
    height: 1.55,
    letterSpacing: -0.1,
    color: _cs.onSurface,
  );

  /// Chat bubble body when painted on top of the accent (user side).
  /// `letterSpacing` is intentionally left at the default (no reduction):
  /// readability wins on a colored background.
  TextStyle get bubbleBodyOnUser =>
      (_tt.bodyMedium ?? const TextStyle()).copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        height: 1.55,
        color: _cs.onPrimary,
      );

  /// Helper for anything that renders aligned numbers (balances, category
  /// amounts, transaction rows). Caller picks color/weight/size; tabular
  /// figures are always enforced.
  TextStyle tabularNum(
    BuildContext context, {
    Color? color,
    FontWeight? weight,
    double? size,
  }) {
    final base = Theme.of(context).textTheme.bodyMedium ?? const TextStyle();
    return base.copyWith(
      fontSize: size,
      fontWeight: weight,
      color: color,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
  }

  // ---------------------------------------------------------------------------
  // Radii & spacing (static const — do not depend on context)
  // ---------------------------------------------------------------------------

  /// Phone frame radius — for design-preview widgets / mocks only, NOT
  /// used inside real chat UI.
  static const double phoneRadius = 48.0;

  static const double sheetRadius = 20.0;
  static const double cardRadius = 18.0;
  static const double innerCardRadius = 12.0;

  static const double bubbleRadius = 20.0;
  static const double bubbleTailRadius = 6.0;

  static const double inputBarRadius = 26.0;
  static const double inputBarHeight = 52.0;

  /// Pill radius for chips. Callers can also use [chipShape] for a
  /// pre-built [StadiumBorder].
  static const double chipRadius = 999.0;
  static const StadiumBorder chipShape = StadiumBorder();

  // Hex tile sizes (see §Hex tiles in design spec).
  static const double hexTileHeader = 34.0;
  static const double hexTileAlert = 36.0;
  static const double hexTileAccount = 44.0;

  /// Space reserved at the bottom of the chat viewport for the floating
  /// input bar (includes safe-area allowance).
  static const double inputZoneBottom = 96.0;

  static const double cardPaddingH = 16.0;
  static const double cardPaddingV = 14.0;

  /// Vertical gap between stacked chat bubbles.
  static const double bubbleGap = 12.0;

  // ---------------------------------------------------------------------------
  // Motion
  // ---------------------------------------------------------------------------

  static const Duration typingBounceDuration = Duration(milliseconds: 1200);
  static const Duration typingStagger = Duration(milliseconds: 150);
  static const double typingTranslateY = 4.0;

  /// Orb pulse only — NO rotation (user rejected rotation in design review).
  static const Duration orbPulseDuration = Duration(milliseconds: 2200);
  static const Duration orbRippleDuration = Duration(milliseconds: 2200);

  static const Duration streamingCursorBlink = Duration(milliseconds: 1000);
}
