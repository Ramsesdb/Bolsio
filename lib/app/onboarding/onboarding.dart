import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:wallex/app/auth/welcome_screen.dart';
import 'package:wallex/app/home/dashboard_widgets/defaults.dart';
import 'package:wallex/app/layout/page_switcher.dart';
import 'package:wallex/app/onboarding/slides/s01_goals.dart';
import 'package:wallex/app/onboarding/slides/s02_currency.dart';
import 'package:wallex/app/onboarding/slides/s03_rate_source.dart';
import 'package:wallex/app/onboarding/slides/s04_initial_accounts.dart';
import 'package:wallex/app/onboarding/slides/s05_autoimport_sell.dart';
import 'package:wallex/app/onboarding/slides/s06_privacy.dart';
import 'package:wallex/app/onboarding/slides/s07_post_notifications.dart';
import 'package:wallex/app/onboarding/slides/s075_restricted_settings.dart';
import 'package:wallex/app/onboarding/slides/s08_activate_listener.dart';
import 'package:wallex/app/onboarding/slides/s09_apps_included.dart';
import 'package:wallex/app/onboarding/slides/s10_seeding_overlay.dart';
import 'package:wallex/app/onboarding/slides/s11_ready.dart';
import 'package:wallex/app/onboarding/theme/v3_tokens.dart';
import 'package:wallex/app/onboarding/widgets/v3_progress_bar.dart';
import 'package:wallex/core/database/services/app-data/app_data_service.dart';
import 'package:wallex/core/database/services/user-setting/user_setting_service.dart';
import 'package:wallex/core/routes/route_utils.dart';
import 'package:wallex/core/services/auto_import/capture/device_quirks_service.dart';
import 'package:wallex/core/utils/unique_app_widgets_keys.dart';

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
  // Currency default: USD. Spec module 3 allows any of USD/VES/DUAL; the
  // device-default detection helper noted in the spec isn't wired in here
  // to keep Fase 5 scoped to controller wiring. If the user does not tap,
  // 'USD' is persisted.
  String _selectedCurrency = 'USD';
  String _selectedRateSource = 'bcv';
  final Set<String> _selectedBankIds = <String>{};

  /// Per-bank "also USD?" flag, only meaningful when [_selectedCurrency] is
  /// `'DUAL'` and the bank has `supportsBoth = true`. Key = bank id, value =
  /// whether the user wants a second USD account seeded alongside the
  /// native VES one. Cleared automatically when a bank is deselected from
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

  void _selectCurrency(String code) {
    setState(() => _selectedCurrency = code);
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
    // 'DUAL' is a UI-only mode label, not a real currency code in the DB.
    // When the user picks dual USD/VES, the base currency defaults to USD.
    final persistedCurrency =
        _selectedCurrency == 'DUAL' ? 'USD' : _selectedCurrency;
    await UserSettingService.instance.setItem(
      SettingKey.preferredCurrency,
      persistedCurrency,
    );
    await UserSettingService.instance.setItem(
      SettingKey.preferredRateSource,
      _selectedRateSource,
    );

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
        selected: _selectedCurrency,
        onSelect: _selectCurrency,
        onNext: _next,
        onSkip: _skip,
      ),
      Slide03RateSource(
        selected: _selectedRateSource,
        onSelect: _selectRateSource,
        onNext: _next,
        onSkip: _skip,
      ),
      Slide04InitialAccounts(
        selectedBankIds: _selectedBankIds,
        onToggleBank: _toggleBank,
        currencyMode: _selectedCurrency,
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
        currencyMode: _selectedCurrency,
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
