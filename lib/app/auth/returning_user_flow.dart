import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wallex/app/layout/page_switcher.dart';
import 'package:wallex/app/onboarding/theme/v3_tokens.dart';
import 'package:wallex/app/onboarding/widgets/v3_notif_access_mockup.dart';
import 'package:wallex/app/onboarding/widgets/v3_primary_button.dart';
import 'package:wallex/app/onboarding/widgets/v3_secondary_button.dart';
import 'package:wallex/core/database/services/app-data/app_data_service.dart';
import 'package:wallex/core/database/services/user-setting/user_setting_service.dart';
import 'package:wallex/core/routes/route_utils.dart';
import 'package:wallex/core/services/auto_import/capture/permission_coordinator.dart';
import 'package:wallex/core/services/auto_import/capture/device_quirks_service.dart';
import 'package:wallex/core/utils/logger.dart';
import 'package:wallex/core/utils/unique_app_widgets_keys.dart';

/// Mini-flow shown to a returning Google user (data already in Firebase).
///
/// Skips the full 10-slide onboarding. Two steps:
///   1. "Bienvenido de vuelta" — hero with display copy + user name.
///   2. "Activar notificaciones" — short reuse of slide-7 lifecycle logic.
///
/// On completion: marks `introSeen = '1'` and `onboarded = '1'`, then
/// `pushAndRemoveUntil` to [PageSwitcher]. Does NOT seed (data is already in
/// Firebase) and does NOT run any onboarding `_applyChoices`.
///
/// On non-Android runtimes step 2 is skipped automatically (no notification
/// listener concept). On Android, if the permission is already granted
/// (rare on a fresh device but possible), step 2 is also skipped.
class ReturningUserFlow extends StatefulWidget {
  const ReturningUserFlow({
    super.key,
    this.displayName,
  });

  /// Display name to show on the welcome-back hero. Falls back to a generic
  /// greeting if null/empty.
  final String? displayName;

  @override
  State<ReturningUserFlow> createState() => _ReturningUserFlowState();
}

class _ReturningUserFlowState extends State<ReturningUserFlow> {
  /// 0 = welcome back; 1 = activate listener.
  int _step = 0;

  /// `true` on Android runtimes. The notification-listener step is only
  /// rendered on Android; other platforms jump straight to home.
  late final bool _isAndroid;
  bool _finishing = false;

  @override
  void initState() {
    super.initState();
    _isAndroid = !kIsWeb && Platform.isAndroid;
  }

  /// Returns the first-name slice of [widget.displayName] when present, e.g.
  /// "Ramses Briceño" → "Ramses". Returns `null` for empty/null inputs so
  /// callers can fall back to a generic greeting.
  String? get _firstName {
    final name = widget.displayName?.trim();
    if (name == null || name.isEmpty) return null;
    final parts = name.split(RegExp(r'\s+'));
    return parts.isEmpty ? null : parts.first;
  }

  Future<void> _advanceFromWelcome() async {
    if (!_isAndroid) {
      // Non-Android: there is no notification-listener step. Finish now.
      await _finish();
      return;
    }

    // On Android, skip step 2 if the permission is already granted.
    final result = await PermissionCoordinator.instance.check();
    if (!mounted) return;

    if (result.notificationListener) {
      await _finish();
      return;
    }

    setState(() => _step = 1);
  }

  /// Returns from step 2 back to step 1 ("Bienvenido de vuelta").
  void _backToWelcome() {
    if (_finishing) return;
    setState(() => _step = 0);
  }

  Future<void> _finish() async {
    if (_finishing) return;
    setState(() => _finishing = true);

    try {
      // `onboarded` was already set by WelcomeScreen, but we re-assert for
      // safety (idempotent if value is unchanged).
      await AppDataService.instance.setItem(
        AppDataKey.onboarded,
        '1',
        updateGlobalState: true,
      );
      await AppDataService.instance.setItem(
        AppDataKey.introSeen,
        '1',
        updateGlobalState: true,
      );
    } catch (e) {
      Logger.printDebug('ReturningUserFlow: error marking flags: $e');
      if (!mounted) return;
      setState(() => _finishing = false);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          child: _step == 0
              ? _WelcomeBackStep(
                  key: const ValueKey('welcome-back'),
                  firstName: _firstName,
                  onContinue: _advanceFromWelcome,
                )
              : _ActivateListenerStep(
                  key: const ValueKey('activate-listener'),
                  isFinishing: _finishing,
                  onDone: _finish,
                  onBack: _backToWelcome,
                ),
        ),
      ),
    );
  }
}

// ─── Step 1: Welcome back hero ──────────────────────────────────────────────

class _WelcomeBackStep extends StatelessWidget {
  const _WelcomeBackStep({
    super.key,
    required this.firstName,
    required this.onContinue,
  });

  final String? firstName;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final Color fg = isDark ? Colors.white : const Color(0xFF141414);
    final Color subFg = isDark ? V3Tokens.mutedDark : V3Tokens.mutedLight;

    final double viewportHeight = MediaQuery.of(context).size.height;
    final double displaySize =
        (viewportHeight * 0.085).clamp(38.0, 56.0).toDouble();

    final greeting = firstName != null
        ? 'Hola, $firstName.'
        : 'Tu Wallex sigue listo.';

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        V3Tokens.space24,
        V3Tokens.space24,
        V3Tokens.space24,
        V3Tokens.space24,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Spacer(flex: 2),
          Text(
            'Bienvenido de vuelta',
            style: V3Tokens.displayStyle(
              size: displaySize,
              letterSpacing: -2.5,
              color: fg,
              height: 1.02,
            ),
            textAlign: TextAlign.left,
          ),
          const SizedBox(height: V3Tokens.space16),
          Text(
            greeting,
            style: V3Tokens.uiStyle(
              size: 16,
              weight: FontWeight.w500,
              color: subFg,
            ),
            textAlign: TextAlign.left,
          ),
          const Spacer(flex: 3),
          V3PrimaryButton(
            label: 'Continuar',
            onPressed: onContinue,
            trailingIcon: Icons.arrow_forward,
          ),
        ],
      ),
    );
  }
}

// ─── Step 2: Activate notification listener (compact) ───────────────────────

class _ActivateListenerStep extends StatefulWidget {
  const _ActivateListenerStep({
    super.key,
    required this.isFinishing,
    required this.onDone,
    required this.onBack,
  });

  final bool isFinishing;
  final VoidCallback onDone;
  final VoidCallback onBack;

  @override
  State<_ActivateListenerStep> createState() => _ActivateListenerStepState();
}

class _ActivateListenerStepState extends State<_ActivateListenerStep>
    with WidgetsBindingObserver {
  bool _granted = false;

  /// Tracks whether the user has tapped "Activar ahora" (which leaves the
  /// app to the system settings screen). When the app resumes and we detect
  /// the permission is now granted, we auto-finish the flow without
  /// requiring a second tap on "Listo".
  bool _awaitingResumeAfterActivate = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshPermission();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshPermissionAndMaybeFinish();
    }
  }

  Future<void> _refreshPermission() async {
    final result = await PermissionCoordinator.instance.check();
    if (!mounted) return;
    setState(() => _granted = result.notificationListener);
  }

  /// Re-check the permission after the app resumes. If the user came back
  /// from the system settings screen with the permission granted, we
  /// auto-finish the flow (mark intro/onboarded + navigate to home).
  /// Otherwise we just refresh the UI so the pulsing Wallex row keeps
  /// reflecting the current state.
  Future<void> _refreshPermissionAndMaybeFinish() async {
    final result = await PermissionCoordinator.instance.check();
    if (!mounted) return;
    final granted = result.notificationListener;
    setState(() => _granted = granted);
    if (granted && _awaitingResumeAfterActivate && !widget.isFinishing) {
      _awaitingResumeAfterActivate = false;
      widget.onDone();
    }
  }

  Future<void> _activate() async {
    _awaitingResumeAfterActivate = true;
    try {
      await DeviceQuirksService.instance.openNotificationListenerSettings();
    } on PlatformException {
      await DeviceQuirksService.instance.openAppDetails();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Abrí la configuración de la app. Busca "Notificaciones" y habilita Wallex.',
          ),
        ),
      );
    }
  }

  Future<void> _skip() async {
    await UserSettingService.instance.setItem(
      SettingKey.notifListenerEnabled,
      '0',
    );
    if (!mounted) return;
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final Color fg = isDark ? Colors.white : const Color(0xFF141414);
    final Color subFg = isDark ? V3Tokens.mutedDark : V3Tokens.mutedLight;
    final Color pillBg =
        isDark ? V3Tokens.pillBgDark : V3Tokens.pillBgLight;
    final Color pillFg = isDark ? V3Tokens.mutedDark : V3Tokens.mutedLight;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        V3Tokens.space24,
        V3Tokens.space16,
        V3Tokens.space24,
        V3Tokens.space24,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Back arrow row — minimal pill matching the v3 onboarding chrome.
          Align(
            alignment: Alignment.centerLeft,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: widget.isFinishing ? null : widget.onBack,
                borderRadius: BorderRadius.circular(V3Tokens.radiusPill),
                child: Container(
                  padding: const EdgeInsets.all(V3Tokens.spaceMd),
                  decoration: BoxDecoration(
                    color: pillBg,
                    borderRadius:
                        BorderRadius.circular(V3Tokens.radiusPill),
                  ),
                  child: Icon(
                    Icons.arrow_back_ios_new,
                    size: 16,
                    color: pillFg,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: V3Tokens.space16),
          Text(
            'Activar notificaciones',
            style: V3Tokens.displayStyle(
              size: 36,
              letterSpacing: -1.6,
              color: fg,
              height: 1.04,
            ),
            textAlign: TextAlign.left,
          ),
          const SizedBox(height: V3Tokens.space16),
          Text(
            'Para registrar tus transacciones automáticamente.',
            style: V3Tokens.uiStyle(
              size: 16,
              weight: FontWeight.w500,
              color: subFg,
            ),
            textAlign: TextAlign.left,
          ),
          const SizedBox(height: V3Tokens.space24),
          // Mini-phone shell (300x300) with the Android "Acceso a
          // notificaciones" mockup — Wallex pulsing on top, peer apps
          // faded — same widget the full onboarding (s07) renders.
          Align(
            alignment: Alignment.topCenter,
            child: V3NotifAccessMockup(granted: _granted),
          ),
          const Spacer(),
          if (!_granted)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: V3SecondaryButton(
                    label: 'Omitir',
                    onPressed: widget.isFinishing ? null : _skip,
                    leadingIcon: Icons.arrow_forward,
                  ),
                ),
                const SizedBox(width: 10),
                Flexible(
                  child: V3PrimaryButton(
                    label: 'Activar ahora',
                    onPressed: widget.isFinishing ? null : _activate,
                    loading: widget.isFinishing,
                  ),
                ),
              ],
            )
          else
            V3PrimaryButton(
              label: 'Listo',
              onPressed: widget.isFinishing ? null : widget.onDone,
              loading: widget.isFinishing,
              trailingIcon: Icons.arrow_forward,
            ),
        ],
      ),
    );
  }
}
