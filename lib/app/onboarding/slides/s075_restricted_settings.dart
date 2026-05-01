import 'package:flutter/material.dart';
import 'package:nitido/app/onboarding/widgets/v3_restricted_settings_step.dart';
import 'package:nitido/core/services/auto_import/capture/device_quirks_service.dart';

/// Onboarding slide adapter for the "Allow restricted settings" gate, sitting
/// between [Slide07PostNotifications] and [Slide08ActivateListener] when the
/// host detects that Android's `android:access_restricted_settings` AppOp is
/// blocked (sideload installs on Android 13+).
///
/// This widget is a thin host-side wrapper around [V3RestrictedSettingsStep]:
/// the shared widget owns lifecycle re-checks, CTA labels (via i18n), and the
/// "still blocked" hint. The slide:
///
/// - forwards the primary CTA (`onOpenAppInfo`) to
///   [DeviceQuirksService.openAppDetails], which fires
///   `Settings.ACTION_APPLICATION_DETAILS_SETTINGS` for `com.nitido.app`;
/// - forwards `onContinue` (skip OR auto-advance after a successful resume
///   re-check) to the host's [onNext] page-controller advance;
/// - sets `showBackPill: true` as the documentary contract for
///   [OnboardingPage] — the actual back-pill is rendered by the host header
///   above the [PageView], not by this slide.
///
/// No state is persisted by this slide (skip is silent — the existing
/// `SettingKey.notifListenerEnabled = '0'` skip persistence stays scoped to
/// `s08_activate_listener.dart`).
class Slide075RestrictedSettings extends StatelessWidget {
  const Slide075RestrictedSettings({
    super.key,
    required this.onNext,
  });

  /// Host advance callback. Invoked when the user taps "Skip for now" OR when
  /// the shared widget's lifecycle observer auto-advances after detecting the
  /// AppOp is now allowed.
  final VoidCallback onNext;

  Future<void> _handleOpenAppInfo() async {
    await DeviceQuirksService.instance.openAppDetails();
  }

  @override
  Widget build(BuildContext context) {
    return V3RestrictedSettingsStep(
      onContinue: onNext,
      onOpenAppInfo: _handleOpenAppInfo,
      showBackPill: true,
    );
  }
}
