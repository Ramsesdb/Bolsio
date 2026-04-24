import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:wallex/app/layout/page_switcher.dart';
import 'package:wallex/app/onboarding/slides/s01_goals.dart';
import 'package:wallex/app/onboarding/slides/s02_currency.dart';
import 'package:wallex/app/onboarding/slides/s03_rate_source.dart';
import 'package:wallex/app/onboarding/slides/s04_initial_accounts.dart';
import 'package:wallex/app/onboarding/slides/s05_autoimport_sell.dart';
import 'package:wallex/app/onboarding/slides/s06_privacy.dart';
import 'package:wallex/app/onboarding/slides/s07_activate_listener.dart';
import 'package:wallex/app/onboarding/slides/s08_apps_included.dart';
import 'package:wallex/app/onboarding/slides/s09_seeding_overlay.dart';
import 'package:wallex/app/onboarding/slides/s10_ready.dart';
import 'package:wallex/app/onboarding/theme/v3_tokens.dart';
import 'package:wallex/app/onboarding/widgets/v3_progress_bar.dart';
import 'package:wallex/core/database/services/app-data/app_data_service.dart';
import 'package:wallex/core/database/services/user-setting/user_setting_service.dart';
import 'package:wallex/core/routes/route_utils.dart';
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

  /// `true` on Android runtimes. Determines whether the auto-import block
  /// (slides 5, 6, 7, 8) is rendered. Evaluated once in [initState] per the
  /// spec's "positive Platform.isAndroid check" requirement.
  late final bool _isAndroid;

  @override
  void initState() {
    super.initState();
    _isAndroid = !kIsWeb && Platform.isAndroid;
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
      } else {
        _selectedBankIds.add(id);
      }
    });
  }

  // ── Persistence ─────────────────────────────────────────────────────────

  /// Persists the high-level user selections collected by slides 1–4.
  ///
  /// Notes:
  /// - `onboardingGoals` is JSON-encoded per the spec (module 11).
  /// - `preferredCurrency` + `preferredRateSource` use the existing keys.
  /// - The bank profile toggles (slide 8) and `notifListenerEnabled` (slide 7
  ///   soft-skip) are persisted directly by their owning slides, so the
  ///   controller does not re-write them here.
  /// - `PersonalVESeeder.seedAll` is NOT called here — slide 9 owns seeding
  ///   and it is idempotent.
  Future<void> _applyChoices() async {
    await UserSettingService.instance.setItem(
      SettingKey.onboardingGoals,
      jsonEncode(_selectedGoals.toList()),
    );
    await UserSettingService.instance.setItem(
      SettingKey.preferredCurrency,
      _selectedCurrency,
    );
    await UserSettingService.instance.setItem(
      SettingKey.preferredRateSource,
      _selectedRateSource,
    );
  }

  /// Final handoff: marks the onboarding as complete and navigates to the
  /// main app surface. Matches the legacy contract exactly so `main.dart`'s
  /// `InitialPageRouteNavigator` gate picks up the change on next rebuild.
  Future<void> _completeOnboarding() async {
    if (_isFinishing) return;
    setState(() => _isFinishing = true);

    try {
      // Safety net: persist choices again in case the user reached slide 10
      // via a code path that skipped slide 9 (e.g. future A/B variant).
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
  /// full 10-slide flow is returned; on non-Android runtimes slides 5–8
  /// (auto-import block) are omitted per spec module 1.
  List<Widget> _buildSlides() {
    // `onNext` for slides 1–4 advances by one page. On non-Android, slide 4
    // is followed directly by the seeding overlay since 5–8 are absent from
    // the list, so `_next()` still lands on s09.
    final slides = <Widget>[
      Slide01Goals(
        selectedGoals: _selectedGoals,
        onToggle: _toggleGoal,
        onNext: _next,
      ),
      Slide02Currency(
        selected: _selectedCurrency,
        onSelect: _selectCurrency,
        onNext: _next,
      ),
      Slide03RateSource(
        selected: _selectedRateSource,
        onSelect: _selectRateSource,
        onNext: _next,
      ),
      Slide04InitialAccounts(
        selectedBankIds: _selectedBankIds,
        onToggleBank: _toggleBank,
        // On Android slide 4 hands off to slide 5; on non-Android it hands
        // off directly to the seeding overlay. `_applyChoices()` fires right
        // before the seeding overlay mounts, so on non-Android we persist
        // here; on Android we defer until slide 8 advances.
        onNext: _isAndroid ? _next : _applyChoicesAndAdvance,
      ),
    ];

    if (_isAndroid) {
      slides.addAll([
        Slide05AutoImportSell(onNext: _next),
        Slide06Privacy(onNext: _next),
        // s07 owns its own lifecycle observer, deep-link intent and the
        // `notifListenerEnabled` skip write; the controller just advances.
        Slide07ActivateListener(onNext: _next),
        // s08 persists each profile toggle directly. After tapping next,
        // apply high-level choices and move to seeding.
        Slide08AppsIncluded(onNext: _applyChoicesAndAdvance),
      ]);
    }

    slides.addAll([
      Slide09SeedingOverlay(
        selectedBankIds: _selectedBankIds,
        onDone: _next,
      ),
      Slide10Ready(
        onFinish: _completeOnboarding,
        isFinishing: _isFinishing,
      ),
    ]);

    return slides;
  }

  /// Persist user choices then advance to the next page. Used at the last
  /// interactive slide before the seeding overlay (slide 8 on Android,
  /// slide 4 on non-Android).
  Future<void> _applyChoicesAndAdvance() async {
    try {
      await _applyChoices();
    } catch (e) {
      // Non-fatal: seeding + navigation continue. The safety-net persist in
      // `_completeOnboarding()` will retry on slide 10.
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

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: FractionallySizedBox(
            widthFactor: screenWidth < 700 ? 1.0 : 700 / screenWidth,
            child: Column(
              children: [
                // Top progress bar — one segment per active slide. Currency
                // of the `currentIndex` reflects the live PageView position.
                Padding(
                  padding: const EdgeInsets.only(
                    top: V3Tokens.space16,
                    bottom: V3Tokens.space16,
                  ),
                  child: V3ProgressBar(
                    currentIndex: _currentIndex,
                    totalSlides: total,
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
