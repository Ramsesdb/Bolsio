import 'package:flutter/material.dart';
import 'package:nitido/app/onboarding/theme/v3_tokens.dart';
import 'package:nitido/app/onboarding/widgets/v3_mini_phone_frame.dart';
import 'package:nitido/app/onboarding/widgets/v3_slide_template.dart';
import 'package:nitido/core/services/auto_import/capture/device_quirks_service.dart';
import 'package:nitido/i18n/generated/translations.g.dart';

/// Shared onboarding step that walks the user through enabling the Android
/// "Allow restricted settings" AppOp before reaching the notification listener
/// activation step.
///
/// Consumed by both `OnboardingPage` (as `Slide075`) and `ReturningUserFlow`
/// (as an intermediate step). The widget is host-agnostic: it does not know
/// which flow it lives in, and exposes only callbacks for `onContinue` (skip
/// or auto-advance) and `onOpenAppInfo` (primary CTA tap → host fires the
/// deep-link).
///
/// Internally registers a [WidgetsBindingObserver] so that when the user
/// returns to the app after opening App info, the primary CTA flips from
/// "Open app info" to "Done, continue" — letting the user manually confirm
/// they enabled the toggle. Auto-advance via re-detection was removed because
/// the underlying check is an installer-source heuristic (immutable for the
/// lifetime of the install) and could never observe the user's toggle change.
///
/// The widget also adapts step copy for Xiaomi/Redmi/POCO devices (MIUI /
/// HyperOS), where the "Allow restricted settings" toggle lives at the bottom
/// of App info rather than behind a top-right kebab menu. The vendor is
/// resolved asynchronously via [DeviceQuirksService.getDeviceVendor] and
/// defaults to `'stock'` until resolved.
///
/// The [showBackPill] flag is contractual metadata for hosts: `OnboardingPage`
/// renders its global back-pill above the slide and forwards `true`;
/// `ReturningUserFlow` has no back-pill and forwards `false`. The widget does
/// not paint a back-pill itself — it just stores the flag for hosts to honor.
class V3RestrictedSettingsStep extends StatefulWidget {
  const V3RestrictedSettingsStep({
    super.key,
    required this.onContinue,
    required this.onOpenAppInfo,
    this.showBackPill = true,
  });

  /// Invoked when the user taps "Skip for now" OR when a lifecycle resume
  /// re-check reports the AppOp is now allowed (auto-advance).
  final VoidCallback onContinue;

  /// Invoked when the user taps the primary CTA. The host is expected to
  /// fire `DeviceQuirksService.openAppDetails()` so the OS opens App Info.
  final VoidCallback onOpenAppInfo;

  /// Contractual flag for hosts: `true` means the host should render a
  /// back-pill above this step (e.g. `OnboardingPage`); `false` means the
  /// host has no back-pill (e.g. `ReturningUserFlow`).
  final bool showBackPill;

  @override
  State<V3RestrictedSettingsStep> createState() =>
      _V3RestrictedSettingsStepState();
}

class _V3RestrictedSettingsStepState extends State<V3RestrictedSettingsStep>
    with WidgetsBindingObserver {
  /// Set to `true` after the user taps the primary "Open app info" CTA at
  /// least once. Gates the resume → "userReturnedFromSettings" transition so
  /// an unrelated foreground/background cycle (e.g. user briefly switches
  /// apps before tapping anything) does not flip the CTA prematurely.
  bool _didTapOpenAppInfo = false;

  /// Set to `true` on the first lifecycle resume that follows a tap on the
  /// primary CTA. Drives the CTA label/action swap from "Open app info" to
  /// "Done, continue" so the user can manually confirm they enabled the
  /// toggle.
  bool _userReturnedFromSettings = false;

  /// Coarse OEM bucket: `'xiaomi'` (MIUI/HyperOS) or `'stock'`. Resolved
  /// asynchronously in [initState] and defaults to `'stock'` until the
  /// platform channel responds, keeping the first frame stable.
  String _vendor = 'stock';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _resolveVendor();
  }

  Future<void> _resolveVendor() async {
    final vendor = await DeviceQuirksService.instance.getDeviceVendor();
    if (!mounted) return;
    if (vendor != _vendor) {
      setState(() => _vendor = vendor);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        _didTapOpenAppInfo &&
        !_userReturnedFromSettings) {
      setState(() => _userReturnedFromSettings = true);
    }
  }

  void _handleOpenAppInfo() {
    _didTapOpenAppInfo = true;
    widget.onOpenAppInfo();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final t = Translations.of(context);
    final copy = t.onboarding.restricted_settings;

    final isXiaomi = _vendor == 'xiaomi';
    final step1Text = isXiaomi ? copy.step1_xiaomi : copy.step1;
    final step2Text = isXiaomi ? copy.step2_xiaomi : copy.step2;
    // step3 is identical for both vendors ("return to Nitido").
    final step3Text = copy.step3;

    final primaryLabel =
        _userReturnedFromSettings ? copy.cta_done : copy.cta_primary;
    final VoidCallback primaryAction =
        _userReturnedFromSettings ? widget.onContinue : _handleOpenAppInfo;

    return V3SlideTemplate(
      primaryLabel: primaryLabel,
      onPrimary: primaryAction,
      secondaryLabel: copy.cta_skip,
      onSecondary: widget.onContinue,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            copy.title,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: V3Tokens.spaceMd),
          Text(
            copy.subtitle,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: V3Tokens.space24),
          Align(
            alignment: Alignment.topCenter,
            child: V3MiniPhoneFrame(
              height: 200,
              child: const _AppInfoMockup(),
            ),
          ),
          const SizedBox(height: V3Tokens.space24),
          _StepRow(index: 1, text: step1Text),
          const SizedBox(height: V3Tokens.spaceMd),
          _StepRow(index: 2, text: step2Text),
          const SizedBox(height: V3Tokens.spaceMd),
          _StepRow(index: 3, text: step3Text),
        ],
      ),
    );
  }
}

/// Numbered step row for the inline 3-step walkthrough. Mirrors the layout
/// language of the OEM instruction tiles in `s08_activate_listener.dart` but
/// without the surface container (steps render directly on the slide body).
class _StepRow extends StatelessWidget {
  const _StepRow({required this.index, required this.text});

  final int index;
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            color: V3Tokens.accent.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(V3Tokens.radiusSm),
          ),
          alignment: Alignment.center,
          child: Text(
            '$index',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: V3Tokens.accent,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ),
        const SizedBox(width: V3Tokens.spaceMd),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurface,
                  ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Stylised App Info mockup: a header bar with the kebab `⋮` highlighted,
/// hinting at the menu the user needs to tap. Drawn with native Flutter
/// primitives — no screenshot asset, keeping the APK lean and the visual
/// resilient to OEM UI drift.
class _AppInfoMockup extends StatelessWidget {
  const _AppInfoMockup();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(V3Tokens.spaceMd),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(V3Tokens.radiusMd),
        border: Border.all(color: scheme.outlineVariant, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Top bar: back arrow + "App info" + highlighted kebab.
          Row(
            children: [
              Icon(
                Icons.arrow_back,
                size: 16,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(width: V3Tokens.spaceXs),
              Expanded(
                child: Text(
                  'App info',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: scheme.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: V3Tokens.accent,
                  borderRadius: BorderRadius.circular(V3Tokens.radiusSm),
                  boxShadow: [
                    BoxShadow(
                      color: V3Tokens.accent.withValues(alpha: 0.40),
                      blurRadius: 0,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                alignment: Alignment.center,
                child: const Icon(
                  Icons.more_vert,
                  size: 14,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: V3Tokens.spaceMd),
          // App icon + label row.
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: V3Tokens.accent,
                  borderRadius: BorderRadius.circular(V3Tokens.radiusSm),
                ),
                alignment: Alignment.center,
                child: const Icon(
                  Icons.account_balance_wallet,
                  size: 16,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: V3Tokens.spaceMd),
              Text(
                'Nitido',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ],
          ),
          const SizedBox(height: V3Tokens.spaceMd),
          // Faint placeholder rows representing the rest of the App info screen.
          _FaintLine(width: 0.85, color: scheme.onSurfaceVariant),
          const SizedBox(height: 6),
          _FaintLine(width: 0.60, color: scheme.onSurfaceVariant),
          const SizedBox(height: 6),
          _FaintLine(width: 0.72, color: scheme.onSurfaceVariant),
        ],
      ),
    );
  }
}

class _FaintLine extends StatelessWidget {
  const _FaintLine({required this.width, required this.color});

  final double width;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      widthFactor: width,
      alignment: Alignment.centerLeft,
      child: Container(
        height: 6,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.22),
          borderRadius: BorderRadius.circular(3),
        ),
      ),
    );
  }
}
