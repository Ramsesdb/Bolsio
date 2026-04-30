import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:kilatex/app/auth/welcome_screen.dart';
import 'package:kilatex/app/home/dashboard_widgets/defaults.dart';
import 'package:kilatex/app/layout/page_switcher.dart';
import 'package:kilatex/app/onboarding/slides/s01_goals.dart';
import 'package:kilatex/app/onboarding/slides/s02_currency.dart';
import 'package:kilatex/app/onboarding/slides/s03_rate_source.dart';
import 'package:kilatex/app/onboarding/slides/s04_initial_accounts.dart';
import 'package:kilatex/app/onboarding/slides/s05_autoimport_sell.dart';
import 'package:kilatex/app/onboarding/slides/s06_privacy.dart';
import 'package:kilatex/app/onboarding/slides/s07_post_notifications.dart';
import 'package:kilatex/app/onboarding/slides/s075_restricted_settings.dart';
import 'package:kilatex/app/onboarding/slides/s08_activate_listener.dart';
import 'package:kilatex/app/onboarding/slides/s09_apps_included.dart';
import 'package:kilatex/app/onboarding/slides/s10_seeding_overlay.dart';
import 'package:kilatex/app/onboarding/slides/s11_ready.dart';
import 'package:kilatex/app/onboarding/theme/v3_tokens.dart';
import 'package:kilatex/app/onboarding/widgets/v3_progress_bar.dart';
import 'package:kilatex/core/database/services/app-data/app_data_service.dart';
import 'package:kilatex/core/database/services/user-setting/user_setting_service.dart';
import 'package:kilatex/core/models/currency/currency_mode.dart';
import 'package:kilatex/core/routes/route_utils.dart';
import 'package:kilatex/core/services/auto_import/capture/device_quirks_service.dart';
import 'package:kilatex/core/utils/unique_app_widgets_keys.dart';

/// Root widget of the v3 onboarding flow.
///
/// The class name is preserved to keep `lib/main.dart` unchanged — the router
/// references [OnboardingPage] by type when `AppDataKey.introSeen` is `'0'`.
class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  // ── Navigation state ────────────────────────────────────────────────────
  final PageController _pageController = PageController();
  int _currentIndex = 0;
  bool _isFinishing = false;

  // ── User selections (lifted state) ──────────────────────────────────────
  final Set<String> _selectedGoals = <String>{};

  /// Currency mode picked on slide 2. Defaults to [CurrencyMode.single_usd]
  /// — the historical onboarding default was USD. The 4-mode rework
  /// (`currency-modes-rework`) widens this from a 3-option string
  /// (`'USD'|'VES'|'DUAL'`) to the canonical [CurrencyMode] enum that maps
  /// 1:1 to the on-disk `currencyMode` setting.
  CurrencyMode _selectedMode = CurrencyMode.single_usd;

  /// Primary currency ISO code. For `single_*` modes this IS the user's
  /// chosen currency; for `dual` it is the primary side of the pair.
  /// Defaults match [_selectedMode] = `single_usd`.
  String _selectedPrimaryCurrency = 'USD';

  /// Secondary currency ISO code. Only meaningful (and only persisted) when
  /// [_selectedMode] is [CurrencyMode.dual]. For all single modes this is
  /// `null` — at persist time we either skip the row or write `null`.
  String? _selectedSecondaryCurrency;

  String _selectedRateSource = 'bcv';
  final Set<String> _selectedBankIds = <String>{};

  /// Per-bank "also USD?" flag, only meaningful when [_selectedMode] is
  /// [CurrencyMode.dual] and the bank has `supportsBoth = true`. Key = bank
  /// id, value = whether the user wants a second USD account seeded alongside
  /// the native VES one. Cleared automatically when a bank is deselected from
  /// [_selectedBankIds].
  final Map<String, bool> _alsoUsdForBank = <String, bool>{};

  /// `true` on Android runtimes. Determines whether the auto-import block
  /// (slides 5, 6, 7, 8, 9) is rendered. Evaluated once in [initState] per the
  /// spec's "positive Platform.isAndroid check" requirement.
  late final bool _isAndroid;

  /// `true` when Android's `android:access_restricted_settings` AppOp reports
  /// `MODE_IGNORED`/`MODE_ERRORED` for this app — i.e. the OS will gray-out
  /// the notification-listener toggle on Android 13+ until the user opts in
  /// via App info → ⋮ → "Allow restricted settings".
  ///
  /// Default `false` (= no extra slide) so the slide list is invariant during
  /// the in-flight async detection. Flipped to `true` by
  /// [_resolveRestrictedSettings] when the call resolves to "blocked".
  /// Triggers a slide list rebuild via `setState` when it transitions, so
  /// [_buildSlides] inserts [Slide075RestrictedSettings] between s07 and s08.
  bool _restrictedSettingsBlocked = false;

  @override
  void initState() {
    super.initState();
    _isAndroid = !kIsWeb && Platform.isAndroid;
    _resolveRestrictedSettings();
  }

  /// Async detection of the restricted-settings AppOp gate. Fires once on
  /// mount; resolves typically in <50ms. Fail-open: any error (non-Android,
  /// PlatformException, missing OPSTR on pre-S firmware) returns `true` from
  /// [DeviceQuirksService.isRestrictedSettingsAllowed], so this method only
  /// flips [_restrictedSettingsBlocked] in the affirmative-blocked branch.
  ///
  /// Late resolution (after the user already passed s07 → s08) is harmless:
  /// the rebuild would insert s075 at the s07/s08 boundary in the slide list,
  /// but the [PageController] stays on its current index and the user
  /// continues uninterrupted per the spec's "Resolución tardía" scenario.
  Future<void> _resolveRestrictedSettings() async {
    if (!_isAndroid) return;
    final allowed =
        await DeviceQuirksService.instance.isRestrictedSettingsAllowed();
    if (!mounted) return;
    if (allowed) {
      debugPrint(
        '[OnboardingPage] restrictedSettingsBlocked=$_restrictedSettingsBlocked '
        '(allowed=true, no s075 inserted)',
      );
      return;
    }
    setState(() => _restrictedSettingsBlocked = true);
    debugPrint(
      '[OnboardingPage] restrictedSettingsBlocked=$_restrictedSettingsBlocked',
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  // ── Navigation helpers ──────────────────────────────────────────────────

  void _goTo(int index) {
    if (!_pageController.hasClients) return;
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeInOut,
    );
  }

  void _next() => _goTo(_currentIndex + 1);

  /// Go back one slide via the global header back pill. The active selection
  /// state (goals / currency / etc.) is preserved — this only moves the
  /// PageController.
  void _previous() {
    if (!_pageController.hasClients) return;
    if (_currentIndex <= 0) return;
    _pageController.previousPage(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeInOut,
    );
  }

  /// Escape hatch on slide 0: resets the onboarded flag and navigates back
  /// to [WelcomeScreen], replacing the current route so the user cannot
  /// press the system back button to re-enter a half-completed onboarding.
  Future<void> _exitOnboarding() async {
    await AppDataService.instance.setItem(
      AppDataKey.onboarded,
      null,
      updateGlobalState: true,
    );
    if (!mounted) return;
    unawaited(Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const WelcomeScreen()),
      (route) => false,
    ));
  }

  /// Skip the current slide without committing any selection. Used by the
  /// "Omitir" secondary CTA on optional slides. Slides that need a richer
  /// skip behaviour (e.g. s08 persisting `notifListenerEnabled='0'`) own
  /// their own skip handler and do not use this.
  void _skip() => _next();

  // ── State mutators (callbacks wired into slides) ────────────────────────

  void _toggleGoal(String id) {
    setState(() {
      if (_selectedGoals.contains(id)) {
        _selectedGoals.remove(id);
      } else {
        _selectedGoals.add(id);
      }
    });
  }

  /// Lift state from [Slide02Currency]. The slide emits the full tuple
  /// (`mode`, `primary`, `secondary?`) on every tile tap or modal selection.
  /// `setState` triggers a slide-list rebuild so [Slide03RateSource] is
  /// included/excluded based on the new mode + pair without manual
  /// PageController index recompute (per design §5).
  void _onCurrencyModeChanged(
    CurrencyMode mode,
    String primary,
    String? secondary,
  ) {
    setState(() {
      _selectedMode = mode;
      _selectedPrimaryCurrency = primary;
      // Preserve a previously chosen secondary across Dual → Single
      // transitions (per resolved decision #2). When the new mode is
      // single_*, we DO NOT clear the in-memory secondary — it stays as
      // the suggested default if the user comes back to dual. At persist
      // time `_applyChoices()` only writes secondaryCurrency when the
      // committed mode is `dual`.
      if (mode == CurrencyMode.dual) {
        _selectedSecondaryCurrency = secondary;
      }
    });
  }

  /// Whether [Slide03RateSource] applies to the current selection. True
  /// only when mode is dual AND the unordered pair is exactly USD+VES,
  /// per `specs/onboarding/spec.md` Requirement "Gating del slide 3".
  bool get _needsRateSourceSlide {
    if (_selectedMode != CurrencyMode.dual) return false;
    final secondary = _selectedSecondaryCurrency;
    if (secondary == null) return false;
    final pair = {_selectedPrimaryCurrency, secondary};
    return pair.containsAll(<String>{'USD', 'VES'});
  }

  /// Legacy currency-mode string consumed by [Slide04InitialAccounts] and
  /// [Slide10SeedingOverlay] / [PersonalVESeeder.seedAll] which still
  /// switch on `'USD'|'VES'|'DUAL'`. We translate at the boundary so the
  /// downstream wiring (out of scope for this phase) keeps working.
  String get _legacyCurrencyMode {
    switch (_selectedMode) {
      case CurrencyMode.single_usd:
        return 'USD';
      case CurrencyMode.single_bs:
        return 'VES';
      case CurrencyMode.single_other:
        return _selectedPrimaryCurrency;
      case CurrencyMode.dual:
        return 'DUAL';
    }
  }

  void _selectRateSource(String source) {
    setState(() => _selectedRateSource = source);
  }

  void _toggleBank(String id) {
    setState(() {
      if (_selectedBankIds.contains(id)) {
        _selectedBankIds.remove(id);
        // Reset the "also USD" flag when the bank is deselected so a future
        // re-selection starts from the default OFF state.
        _alsoUsdForBank.remove(id);
      } else {
        _selectedBankIds.add(id);
      }
    });
  }

  /// Toggle the per-bank "also USD" flag (slide 4 sub-row). Only invoked for
  /// banks with `supportsBoth = true` while the currency mode is DUAL.
  void _toggleAlsoUsd(String bankId, bool value) {
    setState(() {
      if (value) {
        _alsoUsdForBank[bankId] = true;
      } else {
        _alsoUsdForBank.remove(bankId);
      }
    });
  }

  // ── Persistence ─────────────────────────────────────────────────────────

  /// Persists the high-level user selections collected by slides 1–4.
  ///
  /// Notes:
  /// - `onboardingGoals` is JSON-encoded per the spec (module 11).
  /// - `preferredCurrency` + `preferredRateSource` use the existing keys.
  /// - The bank profile toggles (slide 9) and `notifListenerEnabled` (slide 8
  ///   soft-skip) are persisted directly by their owning slides, so the
  ///   controller does not re-write them here.
  /// - `PersonalVESeeder.seedAll` is NOT called here — slide 10 owns seeding
  ///   and it is idempotent.
  Future<void> _applyChoices() async {
    await UserSettingService.instance.setItem(
      SettingKey.onboardingGoals,
      jsonEncode(_selectedGoals.toList()),
    );

    // ── Currency mode + primary + secondary ───────────────────────────────
    // Replaces the old lossy `'DUAL' → 'USD'` collapse. We now persist:
    //   - currencyMode       : the canonical enum dbValue
    //   - preferredCurrency  : the user's primary ISO code
    //   - secondaryCurrency  : ISO code when mode is dual, NULL otherwise
    //   - preferredRateSource: only when slide 3 was shown (dual USD+VES)
    //
    // Per `specs/onboarding/spec.md` Requirement "Selección de moneda
    // preferida (slide 2)" + design.md §5.
    await UserSettingService.instance.setItem(
      SettingKey.currencyMode,
      _selectedMode.dbValue,
    );
    await UserSettingService.instance.setItem(
      SettingKey.preferredCurrency,
      _selectedPrimaryCurrency,
    );
    if (_selectedMode == CurrencyMode.dual) {
      await UserSettingService.instance.setItem(
        SettingKey.secondaryCurrency,
        _selectedSecondaryCurrency ?? 'VES',
      );
    } else {
      // Single modes: write NULL so the row is canonical (vs. leaving a
      // stale value behind from a prior dual selection on this device).
      // The migration heuristic from Phase 1 also writes NULL for single
      // modes, so this keeps the in-memory state aligned with the
      // freshly-onboarded shape.
      await UserSettingService.instance.setItem(
        SettingKey.secondaryCurrency,
        null,
      );
    }

    // `preferredRateSource` is only meaningful for the BCV/Paralelo gating
    // on USD↔VES dual. For every other mode/pair we skip the write — leaving
    // any existing value alone (it will be ignored at read time when the
    // policy doesn't ask for the chip).
    if (_needsRateSourceSlide) {
      await UserSettingService.instance.setItem(
        SettingKey.preferredRateSource,
        _selectedRateSource,
      );
    }

    // Spec `dashboard-layout` § Defaults por onboardingGoals (Scenario
    // "Goal único save_usd"): derivar el layout del dashboard a partir de
    // las metas seleccionadas y persistirlo. `updateGlobalState: true`
    // garantiza que `appStateSettings[SettingKey.dashboardLayout]` quede
    // sincronizado para que el dashboard `initState` lo lea sin un
    // round-trip a Drift.
    //
    // Se hace AQUÍ (en `_applyChoices`, no en `initState` del dashboard)
    // por coherencia transaccional — todos los settings derivados del
    // onboarding se escriben juntos. El fallback en `initState` cubre
    // el caso degradado (returning user sin layout en Firebase).
    final layout = DashboardLayoutDefaults.fromGoals(_selectedGoals);
    await UserSettingService.instance.setItem(
      SettingKey.dashboardLayout,
      jsonEncode(layout.toJson()),
      updateGlobalState: true,
    );
  }

  /// Final handoff: marks the onboarding as complete and navigates to the
  /// main app surface. Matches the legacy contract exactly so `main.dart`'s
  /// `InitialPageRouteNavigator` gate picks up the change on next rebuild.
  Future<void> _completeOnboarding() async {
    if (_isFinishing) return;
    setState(() => _isFinishing = true);

    try {
      // Safety net: persist choices again in case the user reached slide 11
      // via a code path that skipped slide 10 (e.g. future A/B variant).
      // `setItem` is idempotent for equal values.
      await _applyChoices();

      await AppDataService.instance.setItem(
        AppDataKey.introSeen,
        '1',
        updateGlobalState: true,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isFinishing = false);
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Error al configurar Wallex'),
          content: const Text(
            'No se pudieron guardar tus preferencias. '
            'Por favor intenta de nuevo.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Reintentar'),
            ),
          ],
        ),
      );
      return;
    }

    if (!mounted) return;
    unawaited(
      RouteUtils.pushRoute(
        PageSwitcher(key: tabsPageKey),
        withReplacement: true,
      ),
    );
  }

  // ── Slide list builder ──────────────────────────────────────────────────

  /// Builds the active slide list for the current platform. On Android the
  /// full 11-slide flow is returned; on non-Android runtimes slides 5–9
  /// (auto-import block) are omitted per spec module 1.
  List<Widget> _buildSlides() {
    // `onNext` for slides 1–4 advances by one page. On non-Android, slide 4
    // is followed directly by the seeding overlay since 5–9 are absent from
    // the list, so `_next()` still lands on s10.
    final slides = <Widget>[
      Slide01Goals(
        selectedGoals: _selectedGoals,
        onToggle: _toggleGoal,
        onNext: _next,
        // s01 has no skip — the goals selection is the first thing we ask.
      ),
      Slide02Currency(
        mode: _selectedMode,
        primaryCurrency: _selectedPrimaryCurrency,
        secondaryCurrency: _selectedSecondaryCurrency,
        onChange: _onCurrencyModeChanged,
        onNext: _next,
        onSkip: _skip,
      ),
      // Slide 3 (rate source) is conditional per the spec: only shown when
      // the user picked dual mode AND the unordered pair is exactly USD+VES.
      // For any other mode/pair the controller advances directly to slide 4.
      // `_buildSlides()` runs every `build`, so the PageController index
      // re-resolves automatically when the user goes back to slide 2 and
      // changes mode (per design.md §5).
      if (_needsRateSourceSlide)
        Slide03RateSource(
          selected: _selectedRateSource,
          onSelect: _selectRateSource,
          onNext: _next,
          onSkip: _skip,
        ),
      Slide04InitialAccounts(
        selectedBankIds: _selectedBankIds,
        onToggleBank: _toggleBank,
        // Slide 4 still consumes the legacy `'USD'|'VES'|'DUAL'` string for
        // its "also USD" sub-row gating + seeding. We translate the new
        // mode at the boundary. The rework's downstream coupling to s04 /
        // PersonalVESeeder is out of scope for this phase.
        currencyMode: _legacyCurrencyMode,
        alsoUsdForBank: _alsoUsdForBank,
        onToggleAlsoUsd: _toggleAlsoUsd,
        // On Android slide 4 hands off to slide 5; on non-Android it hands
        // off directly to the seeding overlay. `_applyChoices()` fires right
        // before the seeding overlay mounts, so on non-Android we persist
        // here; on Android we defer until slide 9 advances.
        onNext: _isAndroid ? _next : _applyChoicesAndAdvance,
        // Skip on non-Android still needs to apply choices (we are about to
        // hand off to seeding). On Android we just advance to slide 5.
        onSkip: _isAndroid ? _skip : _applyChoicesAndAdvance,
      ),
    ];

    if (_isAndroid) {
      slides.addAll([
        Slide05AutoImportSell(onNext: _next, onSkip: _skip),
        Slide06Privacy(onNext: _next, onSkip: _skip),
        Slide07PostNotifications(onNext: _next),
        // s075 — restricted-settings AppOp gate. Inserted between s07 and s08
        // ONLY when Android 13+ sideload reports the gate as blocked, so the
        // user can flip the kebab toggle in App info before s08 tries to open
        // the (grayed-out) notification-listener toggle. Slide list length
        // remains invariant when `_restrictedSettingsBlocked == false`.
        if (_restrictedSettingsBlocked)
          Slide075RestrictedSettings(onNext: _next),
        Slide08ActivateListener(onNext: _next),
        Slide09AppsIncluded(
          onNext: _applyChoicesAndAdvance,
          onSkip: _applyChoicesAndAdvance,
        ),
      ]);
    }

    slides.addAll([
      Slide10SeedingOverlay(
        selectedBankIds: _selectedBankIds,
        alsoUsdForBank: _alsoUsdForBank,
        currencyMode: _legacyCurrencyMode,
        onDone: _next,
      ),
      Slide11Ready(
        onFinish: _completeOnboarding,
        isFinishing: _isFinishing,
      ),
    ]);

    return slides;
  }

  /// Persist user choices then advance to the next page. Used at the last
  /// interactive slide before the seeding overlay (slide 9 on Android,
  /// slide 4 on non-Android).
  Future<void> _applyChoicesAndAdvance() async {
    try {
      await _applyChoices();
    } catch (e) {
      // Non-fatal: seeding + navigation continue. The safety-net persist in
      // `_completeOnboarding()` will retry on slide 11.
      if (kDebugMode) {
        // ignore: avoid_print
        debugPrint('Onboarding._applyChoices failed: $e');
      }
    }
    if (!mounted) return;
    _next();
  }

  // ── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final slides = _buildSlides();
    final total = slides.length;
    final screenWidth = MediaQuery.of(context).size.width;

    // Back pill visibility:
    // - Hidden on slide 0 (nothing to go back to).
    // - Hidden while the seeding overlay is mounted (the user must not
    //   interrupt seeding).
    // - Shown for every other slide.
    final bool isSeedingSlide = _currentIndex >= 0 &&
        _currentIndex < slides.length &&
        slides[_currentIndex] is Slide10SeedingOverlay;
    final bool showBack = _currentIndex > 0 && !isSeedingSlide;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: FractionallySizedBox(
            widthFactor: screenWidth < 700 ? 1.0 : 700 / screenWidth,
            child: Column(
              children: [
                // Top header — back pill (left) + segmented progress bar.
                // The `currentIndex` reflects the live PageView position.
                // When there is no back affordance the pill collapses to
                // zero width so the progress bar takes the full row width;
                // when it appears (slide 1 → 2) it fades + slides in from
                // the left and the row width animates via [AnimatedSize].
                Padding(
                  padding: const EdgeInsets.only(
                    top: V3Tokens.space16,
                    bottom: V3Tokens.space16,
                    left: V3Tokens.space24,
                    right: V3Tokens.space24,
                  ),
                  child: AnimatedSize(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    child: Row(
                      children: [
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 220),
                          switchInCurve: Curves.easeOutCubic,
                          switchOutCurve: Curves.easeInCubic,
                          transitionBuilder: (child, animation) {
                            final slide = Tween<Offset>(
                              begin: const Offset(-0.3, 0),
                              end: Offset.zero,
                            ).animate(animation);
                            return FadeTransition(
                              opacity: animation,
                              child: SlideTransition(
                                position: slide,
                                child: child,
                              ),
                            );
                          },
                          child: showBack
                              ? Padding(
                                  key: const ValueKey('back-pill'),
                                  padding: const EdgeInsets.only(
                                    right: V3Tokens.spaceMd,
                                  ),
                                  child: _BackPill(onTap: _previous),
                                )
                              : _currentIndex == 0
                                  ? Padding(
                                      key: const ValueKey('close-pill'),
                                      padding: const EdgeInsets.only(
                                        right: V3Tokens.spaceMd,
                                      ),
                                      child: _BackPill(
                                        onTap: _exitOnboarding,
                                        icon: Icons.close,
                                      ),
                                    )
                                  : const SizedBox.shrink(
                                      key: ValueKey('no-back'),
                                    ),
                        ),
                        Expanded(
                          // The header Row owns the horizontal padding, so
                          // the progress bar renders flush inside the Row.
                          child: V3ProgressBar(
                            currentIndex: _currentIndex,
                            totalSlides: total,
                            flush: true,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: PageView.builder(
                    controller: _pageController,
                    // Slides are CTA-driven; horizontal swipes are disabled
                    // to prevent the user from skipping past mandatory setup
                    // steps (the seeding overlay in particular must run in
                    // its own mount cycle).
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: total,
                    onPageChanged: (i) => setState(() => _currentIndex = i),
                    itemBuilder: (_, i) => slides[i],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Header back affordance — a 36×36 pill button containing a chevron.
///
/// Visibility is owned by the parent header: when there is no slide to go
/// back to, the parent renders a [SizedBox.shrink] in place of this widget
/// (wrapped in an [AnimatedSwitcher]) so the adjacent progress bar grows
/// to fill the row.
///
/// Visuals match the official v3 design HTML:
/// - background `pillBgDark`/`pillBgLight`
/// - radius 999 (full pill)
/// - icon `arrow_back_ios_new` size 14, `mutedDark`/`mutedLight` color
class _BackPill extends StatelessWidget {
  const _BackPill({
    required this.onTap,
    this.icon = Icons.arrow_back_ios_new,
  });

  final VoidCallback? onTap;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    const double size = 36;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final Color bg = isDark ? V3Tokens.pillBgDark : V3Tokens.pillBgLight;
    final Color fg = isDark ? V3Tokens.mutedDark : V3Tokens.mutedLight;
    return SizedBox(
      width: size,
      height: size,
      child: Material(
        color: bg,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Center(
            child: Icon(
              icon,
              size: 14,
              color: fg,
            ),
          ),
        ),
      ),
    );
  }
}
