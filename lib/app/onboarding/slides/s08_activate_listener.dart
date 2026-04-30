import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:bolsio/app/onboarding/theme/v3_tokens.dart';
import 'package:bolsio/app/onboarding/widgets/v3_notif_access_mockup.dart';
import 'package:bolsio/app/onboarding/widgets/v3_slide_template.dart';
import 'package:bolsio/core/database/services/user-setting/user_setting_service.dart';
import 'package:bolsio/core/services/auto_import/capture/device_quirks_service.dart';
import 'package:bolsio/core/services/auto_import/capture/permission_coordinator.dart';

class Slide08ActivateListener extends StatefulWidget {
  const Slide08ActivateListener({
    super.key,
    required this.onNext,
  });

  final VoidCallback onNext;

  @override
  State<Slide08ActivateListener> createState() =>
      _Slide08ActivateListenerState();
}

class _Slide08ActivateListenerState extends State<Slide08ActivateListener>
    with WidgetsBindingObserver {
  bool _granted = false;
  bool _batteryIgnored = false;

  /// Tracks whether the user has tapped "Activar ahora" (which leaves the
  /// app to the system settings screen). When the app resumes and we detect
  /// the permission is now granted, we auto-advance to the next slide so the
  /// user doesn't need to tap a second button.
  bool _awaitingResumeAfterActivate = false;
  bool _awaitingResumeAfterBattery = false;
  OemQuirk _quirk = OemQuirk.none;
  List<QuirkInstruction> _quirkInstructions = const [];

  static const Set<String> _kBatteryInstructionIds = {
    'miui_battery_app',
    'samsung_unrestricted',
  };

  bool get _quirkRequiresBattery {
    for (final ins in _quirkInstructions) {
      if (_kBatteryInstructionIds.contains(ins.id)) return true;
    }
    return false;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshPermission();
    _detectQuirk();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshPermissionAndMaybeAdvance();
    }
  }

  Future<void> _refreshPermission() async {
    final result = await PermissionCoordinator.instance.check();
    if (!mounted) return;
    setState(() {
      _granted = result.notificationListener;
      _batteryIgnored = result.batteryOptimizationsIgnored;
    });
  }

  /// Re-check the permission after the app resumes. If the user came back
  /// from the system settings screen with the permission granted, we
  /// auto-advance to the next slide. Otherwise we just refresh the UI so
  /// the pulsing Bolsio row keeps reflecting the current state.
  Future<void> _refreshPermissionAndMaybeAdvance() async {
    final result = await PermissionCoordinator.instance.check();
    if (!mounted) return;
    final granted = result.notificationListener;
    final batteryIgnored = result.batteryOptimizationsIgnored;
    final cameFromBattery = _awaitingResumeAfterBattery;
    setState(() {
      _granted = granted;
      _batteryIgnored = batteryIgnored;
    });
    if (cameFromBattery) {
      _awaitingResumeAfterBattery = false;
      return;
    }
    if (granted &&
        _awaitingResumeAfterActivate &&
        (!_quirkRequiresBattery || batteryIgnored)) {
      _awaitingResumeAfterActivate = false;
      widget.onNext();
    }
  }

  Future<void> _detectQuirk() async {
    final q = await DeviceQuirksService.instance.detect();
    if (!mounted) return;
    setState(() {
      _quirk = q;
      _quirkInstructions = DeviceQuirksService.instance.instructionsFor(q);
    });
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
            'Abrí la configuración de la app. Busca "Notificaciones" y habilita Bolsio.',
          ),
        ),
      );
    }
  }

  Future<void> _activateBattery() async {
    _awaitingResumeAfterBattery = true;
    try {
      await DeviceQuirksService.instance.openBatteryOptimizationSettings();
    } on PlatformException {
      await DeviceQuirksService.instance.openAppDetails();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Abrí la configuración de la app. Busca "Batería" y selecciona Sin restricciones.',
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
    widget.onNext();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final batteryReady = !_quirkRequiresBattery || _batteryIgnored;
    final readyToAdvance = _granted && batteryReady;
    return V3SlideTemplate(
      primaryLabel: readyToAdvance ? 'Siguiente' : 'Activar ahora',
      onPrimary: readyToAdvance ? widget.onNext : _activate,
      secondaryLabel: readyToAdvance ? null : 'Omitir',
      onSecondary: readyToAdvance ? null : _skip,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Activa el listener',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: V3Tokens.spaceMd),
          Text(
            'Concede acceso a las notificaciones para que Bolsio registre automáticamente tus transacciones.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: V3Tokens.space24),
          // V3MiniPhone shell (300x300) showing a mock of the Android
          // "Acceso a notificaciones" settings screen. Bolsio appears at
          // the top with a pulsing accent halo (or a static check when the
          // permission is already granted), and the other apps are faded
          // out so the user's eye lands on the action they need to take.
          Align(
            alignment: Alignment.topCenter,
            child: V3NotifAccessMockup(granted: _granted),
          ),
          const SizedBox(height: V3Tokens.space16),
          if (_quirkInstructions.isNotEmpty) ...[
            _OemInstructions(
              quirk: _quirk,
              instructions: _quirkInstructions,
              showBatteryTile: _quirkRequiresBattery,
              batteryIgnored: _batteryIgnored,
              onTapBattery: _activateBattery,
            ),
            const SizedBox(height: V3Tokens.space16),
          ],
        ],
      ),
    );
  }
}

class _OemInstructions extends StatelessWidget {
  const _OemInstructions({
    required this.quirk,
    required this.instructions,
    required this.showBatteryTile,
    required this.batteryIgnored,
    required this.onTapBattery,
  });

  final OemQuirk quirk;
  final List<QuirkInstruction> instructions;
  final bool showBatteryTile;
  final bool batteryIgnored;
  final VoidCallback onTapBattery;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(V3Tokens.space16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(V3Tokens.radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.info_outline, size: 18),
              const SizedBox(width: V3Tokens.spaceXs),
              Text(
                'Pasos extra en ${quirk.name.toUpperCase()}',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ],
          ),
          const SizedBox(height: V3Tokens.spaceXs),
          for (final step in instructions) ...[
            Text(
              step.titleEs,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            Text(
              step.descEs,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: V3Tokens.spaceXs),
          ],
          if (showBatteryTile) ...[
            const SizedBox(height: V3Tokens.spaceXs),
            _BatteryTile(
              ignored: batteryIgnored,
              onTap: onTapBattery,
            ),
          ],
        ],
      ),
    );
  }
}

class _BatteryTile extends StatelessWidget {
  const _BatteryTile({
    required this.ignored,
    required this.onTap,
  });

  final bool ignored;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (ignored) {
      return Container(
        padding: const EdgeInsets.symmetric(
          horizontal: V3Tokens.spaceMd,
          vertical: V3Tokens.spaceXs,
        ),
        decoration: BoxDecoration(
          color: V3Tokens.accent.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(V3Tokens.radiusSm),
        ),
        child: Row(
          children: [
            const Icon(Icons.check_circle, color: V3Tokens.accent, size: 18),
            const SizedBox(width: V3Tokens.spaceXs),
            Expanded(
              child: Text(
                'Batería sin restricciones',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
          ],
        ),
      );
    }
    return Material(
      color: scheme.surface,
      borderRadius: BorderRadius.circular(V3Tokens.radiusSm),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(V3Tokens.radiusSm),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: V3Tokens.spaceMd,
            vertical: V3Tokens.spaceMd,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(V3Tokens.radiusSm),
            border: Border.all(color: V3Tokens.accent, width: 1),
          ),
          child: Row(
            children: [
              const Icon(Icons.battery_charging_full,
                  color: V3Tokens.accent, size: 18),
              const SizedBox(width: V3Tokens.spaceXs),
              Expanded(
                child: Text(
                  'Toca para quitar la restricción de batería',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
              Icon(Icons.chevron_right,
                  color: scheme.onSurfaceVariant, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}
