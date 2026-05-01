import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:nitido/core/services/auto_import/capture/device_quirks_service.dart';
import 'package:nitido/core/services/auto_import/capture/permission_coordinator.dart';
import 'package:nitido/i18n/generated/translations.g.dart';

/// Guided checklist for every permission / OEM tweak the capture pipeline
/// needs in order to stay alive in the background.
///
/// Refreshed on: page init, app resume, and "Verify now" button press.
class CapturePermissionsPage extends StatefulWidget {
  const CapturePermissionsPage({super.key});

  @override
  State<CapturePermissionsPage> createState() => _CapturePermissionsPageState();
}

class _CapturePermissionsPageState extends State<CapturePermissionsPage>
    with WidgetsBindingObserver {
  bool _working = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Fire the first refresh on the next microtask so the ValueListenable
    // has time to attach before we mutate state.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      PermissionCoordinator.instance.check();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // User likely came back from a system settings screen. Re-check so the
    // checklist updates without requiring a manual tap.
    if (state == AppLifecycleState.resumed) {
      PermissionCoordinator.instance.check();
    }
  }

  bool get _isSpanish => LocaleSettings.currentLocale == AppLocale.es;

  String _tr({required String es, required String en}) => _isSpanish ? es : en;

  @override
  Widget build(BuildContext context) {
    final isAndroid = !kIsWeb && Platform.isAndroid;
    return Scaffold(
      appBar: AppBar(
        title: Text(_tr(
          es: 'Permisos del listener',
          en: 'Listener permissions',
        )),
      ),
      body: ValueListenableBuilder<CapturePermissionsState>(
        valueListenable: PermissionCoordinator.instance.stateNotifier,
        builder: (context, state, _) {
          final quirkInstructions =
              DeviceQuirksService.instance.instructionsFor(state.quirk);
          return ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              _StatusBanner(
                allGranted: state.allCriticalGranted,
                allQuirksConfirmed: state.allQuirksConfirmed,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Text(
                  _tr(
                    es: 'Para que la captura automática sobreviva en '
                        'segundo plano necesitamos varios permisos. '
                        'Verificá cada uno — en Xiaomi y otros OEMs hay '
                        'pasos adicionales fuera de Android.',
                    en: 'For auto-capture to survive in the background we '
                        'need several permissions. Check each one — on '
                        'Xiaomi and other OEMs there are extra steps '
                        'beyond stock Android.',
                  ),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              if (!isAndroid)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    _tr(
                      es: 'Esta pantalla solo aplica a Android.',
                      en: 'This screen only applies to Android.',
                    ),
                  ),
                )
              else ...[
                _PermissionTile(
                  icon: Icons.notifications_active_outlined,
                  title: _tr(
                    es: 'Acceso a notificaciones',
                    en: 'Notification access',
                  ),
                  desc: _tr(
                    es: 'Permite leer notificaciones de apps bancarias. '
                        'Sin esto no hay captura push.',
                    en: 'Lets us read notifications from banking apps. '
                        'Without this there is no push capture.',
                  ),
                  granted: state.notificationListener,
                  ctaLabel: _tr(es: 'Conceder', en: 'Grant'),
                  onGrant: () async {
                    await _guard(() => PermissionCoordinator.instance
                        .requestNotificationListener());
                  },
                ),
                _PermissionTile(
                  icon: Icons.notifications_outlined,
                  title: _tr(
                    es: 'Notificaciones del sistema',
                    en: 'System notifications',
                  ),
                  desc: _tr(
                    es: 'Requerido en Android 13+ para mostrar el aviso '
                        'persistente del servicio en background.',
                    en: 'Required on Android 13+ to show the foreground '
                        'service sticky notification.',
                  ),
                  granted: state.postNotifications,
                  ctaLabel: _tr(es: 'Conceder', en: 'Grant'),
                  onGrant: () async {
                    await _guard(() => PermissionCoordinator.instance
                        .requestPostNotifications());
                  },
                ),
                _PermissionTile(
                  icon: Icons.battery_charging_full,
                  title: _tr(
                    es: 'Sin optimización de batería',
                    en: 'Unrestricted battery',
                  ),
                  desc: _tr(
                    es: 'Android entra en Doze si no está en la lista '
                        'blanca; el foreground service queda ahogado.',
                    en: 'Android enters Doze otherwise; the foreground '
                        'service gets throttled.',
                  ),
                  granted: state.batteryOptimizationsIgnored,
                  ctaLabel: _tr(es: 'Abrir ajustes', en: 'Open settings'),
                  onGrant: () async {
                    await _guard(() async {
                      await DeviceQuirksService.instance
                          .openBatteryOptimizationSettings();
                    });
                  },
                ),
                for (final ins in quirkInstructions)
                  _QuirkTile(
                    instruction: ins,
                    isSpanish: _isSpanish,
                    confirmed: _confirmedFor(state, ins.id) ?? false,
                    onOpen: () async {
                      await _guard(() async {
                        // For autostart-style IDs go through the OEM deep
                        // link, for battery-style through battery opt.
                        if (ins.id == 'miui_autostart' ||
                            ins.id == 'huawei_protected' ||
                            ins.id == 'oppo_autostart' ||
                            ins.id == 'vivo_autostart') {
                          await DeviceQuirksService.instance
                              .openAutostartSettings();
                        } else {
                          await DeviceQuirksService.instance
                              .openBatteryOptimizationSettings();
                        }
                      });
                    },
                    onConfirmChanged: (value) async {
                      if (ins.id == 'miui_autostart' ||
                          ins.id == 'huawei_protected' ||
                          ins.id == 'oppo_autostart' ||
                          ins.id == 'vivo_autostart') {
                        await PermissionCoordinator.instance
                            .setAutostartConfirmed(value);
                      } else {
                        await PermissionCoordinator.instance
                            .setOemBatteryConfirmed(value);
                      }
                    },
                  ),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: FilledButton.icon(
                    onPressed: _working
                        ? null
                        : () async {
                            final messenger = ScaffoldMessenger.of(context);
                            await _guard(() =>
                                PermissionCoordinator.instance.refresh());
                            if (!mounted) return;
                            messenger.showSnackBar(
                              SnackBar(
                                content: Text(_tr(
                                  es: 'Estado actualizado',
                                  en: 'State refreshed',
                                )),
                                duration: const Duration(seconds: 2),
                              ),
                            );
                          },
                    icon: const Icon(Icons.refresh),
                    label: Text(_tr(
                      es: 'Verificar ahora',
                      en: 'Verify now',
                    )),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  bool? _confirmedFor(CapturePermissionsState state, String id) {
    if (id == 'miui_autostart' ||
        id == 'huawei_protected' ||
        id == 'oppo_autostart' ||
        id == 'vivo_autostart') {
      return state.autostartUserConfirmed;
    }
    if (id == 'miui_battery_app' || id == 'samsung_unrestricted') {
      return state.oemBatteryUserConfirmed;
    }
    return null;
  }

  Future<void> _guard(Future<void> Function() op) async {
    if (_working) return;
    setState(() => _working = true);
    try {
      await op();
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }
}

class _StatusBanner extends StatelessWidget {
  final bool allGranted;
  final bool allQuirksConfirmed;

  const _StatusBanner({
    required this.allGranted,
    required this.allQuirksConfirmed,
  });

  @override
  Widget build(BuildContext context) {
    final ok = allGranted && allQuirksConfirmed;
    final bg = ok ? Colors.green.shade50 : Colors.red.shade50;
    final fg = ok ? Colors.green.shade900 : Colors.red.shade900;
    final icon = ok ? Icons.check_circle : Icons.error_outline;
    final isSpanish = LocaleSettings.currentLocale == AppLocale.es;

    final title = ok
        ? (isSpanish
            ? 'Listo, el listener puede funcionar'
            : 'All set — the listener can run')
        : (isSpanish ? 'Faltan permisos' : 'Missing permissions');
    final subtitle = ok
        ? (isSpanish
            ? 'Los tres permisos críticos están activos.'
            : 'All three critical permissions are active.')
        : allGranted
            ? (isSpanish
                ? 'Falta confirmar pasos específicos del fabricante.'
                : 'OEM-specific steps still pending confirmation.')
            : (isSpanish
                ? 'Activá cada ítem rojo para estabilizar el listener.'
                : 'Grant each red item to stabilize the listener.');

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: fg),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: fg,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(subtitle, style: TextStyle(color: fg, fontSize: 13)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PermissionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String desc;
  final bool granted;
  final String ctaLabel;
  final Future<void> Function() onGrant;

  const _PermissionTile({
    required this.icon,
    required this.title,
    required this.desc,
    required this.granted,
    required this.ctaLabel,
    required this.onGrant,
  });

  @override
  Widget build(BuildContext context) {
    final color = granted ? Colors.green.shade700 : Colors.red.shade700;
    final trailingIcon = granted
        ? const Icon(Icons.check_circle, color: Colors.green)
        : const Icon(Icons.cancel_outlined, color: Colors.red);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                ),
                trailingIcon,
              ],
            ),
            const SizedBox(height: 6),
            Text(desc, style: Theme.of(context).textTheme.bodySmall),
            if (!granted) ...[
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.lock_open, size: 18),
                  label: Text(ctaLabel),
                  onPressed: onGrant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _QuirkTile extends StatelessWidget {
  final QuirkInstruction instruction;
  final bool isSpanish;
  final bool confirmed;
  final Future<void> Function() onOpen;
  final Future<void> Function(bool) onConfirmChanged;

  const _QuirkTile({
    required this.instruction,
    required this.isSpanish,
    required this.confirmed,
    required this.onOpen,
    required this.onConfirmChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = isSpanish ? instruction.titleEs : instruction.titleEn;
    final desc = isSpanish ? instruction.descEs : instruction.descEn;
    final cta = isSpanish ? instruction.ctaEs : instruction.ctaEn;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      elevation: 0,
      color: confirmed
          ? Colors.green.shade50
          : theme.colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.warning_amber_outlined,
                  color: confirmed
                      ? Colors.green.shade700
                      : Colors.orange.shade700,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                ),
                if (confirmed)
                  const Icon(Icons.check_circle, color: Colors.green),
              ],
            ),
            const SizedBox(height: 6),
            Text(desc, style: theme.textTheme.bodySmall),
            const SizedBox(height: 8),
            Row(
              children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.open_in_new, size: 18),
                  label: Text(cta),
                  onPressed: onOpen,
                ),
              ],
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              value: confirmed,
              onChanged: (v) => onConfirmChanged(v),
              title: Text(
                isSpanish ? 'Ya lo activé' : 'I already enabled it',
                style: const TextStyle(fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
