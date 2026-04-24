import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wallex/app/onboarding/theme/v3_tokens.dart';
import 'package:wallex/app/onboarding/widgets/v3_slide_template.dart';
import 'package:wallex/core/database/services/user-setting/user_setting_service.dart';
import 'package:wallex/core/services/auto_import/capture/device_quirks_service.dart';
import 'package:wallex/core/services/auto_import/capture/permission_coordinator.dart';

class Slide07ActivateListener extends StatefulWidget {
  const Slide07ActivateListener({
    super.key,
    required this.onNext,
  });

  final VoidCallback onNext;

  @override
  State<Slide07ActivateListener> createState() =>
      _Slide07ActivateListenerState();
}

class _Slide07ActivateListenerState extends State<Slide07ActivateListener>
    with WidgetsBindingObserver {
  bool _granted = false;
  OemQuirk _quirk = OemQuirk.none;
  List<QuirkInstruction> _quirkInstructions = const [];

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
      _refreshPermission();
    }
  }

  Future<void> _refreshPermission() async {
    final result = await PermissionCoordinator.instance.check();
    if (!mounted) return;
    setState(() => _granted = result.notificationListener);
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
    widget.onNext();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return V3SlideTemplate(
      primaryLabel: _granted ? 'Siguiente' : 'Activar ahora',
      onPrimary: _granted ? widget.onNext : _activate,
      secondaryLabel: _granted ? null : 'Omitir por ahora',
      onSecondary: _granted ? null : _skip,
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
            'Concede acceso a las notificaciones para que Wallex registre automáticamente tus transacciones.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: V3Tokens.space24),
          if (_quirkInstructions.isNotEmpty) ...[
            _OemInstructions(
              quirk: _quirk,
              instructions: _quirkInstructions,
            ),
            const SizedBox(height: V3Tokens.space16),
          ],
          if (_granted)
            _StatusBanner(
              icon: Icons.check_circle,
              color: Colors.green,
              label: 'Permiso activado',
            )
          else
            _StatusBanner(
              icon: Icons.warning_amber_outlined,
              color: V3Tokens.accent,
              label:
                  'Sin esto, el auto-import no estará disponible hasta que lo actives en Ajustes.',
            ),
        ],
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({
    required this.icon,
    required this.color,
    required this.label,
  });

  final IconData icon;
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(V3Tokens.space16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(V3Tokens.radiusMd),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: V3Tokens.spaceMd),
          Expanded(child: Text(label)),
        ],
      ),
    );
  }
}

class _OemInstructions extends StatelessWidget {
  const _OemInstructions({
    required this.quirk,
    required this.instructions,
  });

  final OemQuirk quirk;
  final List<QuirkInstruction> instructions;

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
        ],
      ),
    );
  }
}
