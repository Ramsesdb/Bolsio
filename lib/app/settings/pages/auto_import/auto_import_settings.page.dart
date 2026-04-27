import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wallex/app/settings/pages/auto_import/binance_api_config.page.dart';
import 'package:wallex/app/settings/pages/auto_import/capture_diagnostics.page.dart';
import 'package:wallex/app/settings/pages/auto_import/capture_permissions.page.dart';
import 'package:wallex/app/transactions/auto_import/pending_imports.page.dart';
import 'package:wallex/core/database/services/pending_import/pending_import_service.dart';
import 'package:wallex/core/database/services/user-setting/user_setting_service.dart';
import 'package:wallex/core/routes/route_utils.dart';
import 'package:wallex/core/services/auto_import/binance/binance_credentials_store.dart';
import 'package:wallex/core/services/auto_import/background/wallex_background_service.dart';
import 'package:wallex/core/services/auto_import/capture/capture_health_monitor.dart';
import 'package:wallex/core/services/auto_import/capture/permission_coordinator.dart';
import 'package:wallex/core/services/auto_import/orchestrator/capture_orchestrator.dart';

/// Settings page for the auto-import feature.
///
/// Allows the user to toggle the master switch, individual channels,
/// bank profiles, and access diagnostic information.
class AutoImportSettingsPage extends StatefulWidget {
  const AutoImportSettingsPage({super.key});

  @override
  State<AutoImportSettingsPage> createState() => _AutoImportSettingsPageState();
}

class _AutoImportSettingsPageState extends State<AutoImportSettingsPage> {
  late bool _autoImportEnabled;
  late bool _smsEnabled;
  late bool _notifEnabled;
  late bool _binanceApiEnabled;
  late bool _bdvSmsProfileEnabled;
  late bool _bdvNotifProfileEnabled;
  late bool _binanceApiProfileEnabled;

  bool _hasSmsPermission = false;
  bool _hasNotifPermission = false;
  bool _hasBinanceCreds = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _checkPermissions();
    // Defensive: kick the health monitor so the UI status is fresh when the
    // user opens this page (covers cold-start races where the monitor was
    // not yet running).
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await CaptureHealthMonitor.instance.forceCheck();
      } catch (e) {
        debugPrint('CaptureHealthMonitor.forceCheck error: $e');
      }
    });
  }

  void _loadSettings() {
    _autoImportEnabled =
        appStateSettings[SettingKey.autoImportEnabled] == '1';
    _smsEnabled = appStateSettings[SettingKey.smsImportEnabled] == '1';
    _notifEnabled =
        appStateSettings[SettingKey.notifListenerEnabled] == '1';
    _binanceApiEnabled =
        appStateSettings[SettingKey.binanceApiEnabled] == '1';
    _bdvSmsProfileEnabled =
        appStateSettings[SettingKey.bdvSmsProfileEnabled] != '0';
    _bdvNotifProfileEnabled =
        appStateSettings[SettingKey.bdvNotifProfileEnabled] != '0';
    // MIGRATION: this toggle used to live under SettingKey.binanceNotifProfileEnabled.
    // That key was a misnomer — the profile is Binance API, not Binance notifications.
    // We now read/write to `binanceApiProfileEnabled`. Users who had disabled the old
    // key will have their Binance API profile re-enabled by default; they can flip it
    // off again manually here. No automatic data migration is performed.
    _binanceApiProfileEnabled =
        appStateSettings[SettingKey.binanceApiProfileEnabled] != '0';
  }

  Future<void> _checkPermissions() async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        _hasSmsPermission = await Permission.sms.isGranted;
      } catch (_) {}
      try {
        // The notification-listener binding is the real signal we need for
        // the push notifications channel — `Permission.notification` is only
        // the POST_NOTIFICATIONS runtime permission and doesn't tell us
        // whether the listener service is actually bound.
        final permState = await PermissionCoordinator.instance.check();
        _hasNotifPermission = permState.notificationListener;
      } catch (_) {}
    }
    try {
      _hasBinanceCreds =
          await BinanceCredentialsStore.instance.hasCredentials();
    } catch (_) {}
    if (mounted) setState(() {});
  }

  Future<void> _saveSetting(SettingKey key, bool value) async {
    await UserSettingService.instance
        .setItem(key, value ? '1' : '0');
    if (mounted) {
      _loadSettings();
      setState(() {});
    }
    // Reconfigure capture orchestrator
    try {
      await CaptureOrchestrator.instance.applySettings();
    } catch (_) {}

    // Manage background service based on master toggle
    if (key == SettingKey.autoImportEnabled) {
      try {
        if (value) {
          await WallexBackgroundService.instance.startService();
        } else {
          await WallexBackgroundService.instance.stopService();
        }
      } catch (_) {}
    } else if (_autoImportEnabled) {
      // For channel/credential changes, restart the background orchestrator
      try {
        await WallexBackgroundService.instance.restartOrchestrator();
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAndroid = !kIsWeb && Platform.isAndroid;
    final isIOS = !kIsWeb && Platform.isIOS;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Auto-import bancario'),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(Icons.auto_mode,
                    size: 40,
                    color: theme.colorScheme.primary),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    'Captura automatica de movimientos bancarios '
                    'desde SMS, notificaciones y APIs.',
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          ),

          // iOS banner
          if (isIOS)
            Card(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: Colors.blue.shade50,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.blue.shade700),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'SMS y notificaciones push solo funcionan en Android. '
                        'Binance API funciona en todas las plataformas.',
                        style: TextStyle(
                            color: Colors.blue.shade900, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // Master toggle
          SwitchListTile(
            secondary: Icon(Icons.auto_mode,
                color: _autoImportEnabled ? theme.colorScheme.primary : null),
            title: const Text('Auto-import activo',
                style: TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(_autoImportEnabled
                ? 'Capturando movimientos'
                : 'Desactivado'),
            value: _autoImportEnabled,
            onChanged: (v) => _saveSetting(SettingKey.autoImportEnabled, v),
          ),

          const Divider(),

          // Channels section — only visible when master toggle is ON
          if (_autoImportEnabled) ...[
            // Listener health banner (Android + notifications channel ON).
            if (isAndroid && _notifEnabled)
              _CaptureHealthBanner(
                onRequestPermission: _requestNotifPermission,
              ),

            _sectionLabel(context, 'Canales de captura'),

            // SMS (Android only)
            if (isAndroid) ...[
              SwitchListTile(
                secondary: Icon(Icons.sms_outlined,
                    color: _smsStatusColor()),
                title: const Text('SMS'),
                subtitle: Text(_smsStatusText()),
                value: _smsEnabled,
                onChanged: (v) =>
                    _saveSetting(SettingKey.smsImportEnabled, v),
              ),
              if (_smsEnabled && !_hasSmsPermission)
                Padding(
                  padding:
                      const EdgeInsets.only(left: 72, right: 16, bottom: 8),
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.lock_open, size: 18),
                    label: const Text('Solicitar permiso SMS'),
                    onPressed: _requestSmsPermission,
                  ),
                ),
            ],

            // Notifications (Android only)
            if (isAndroid) ...[
              SwitchListTile(
                secondary: Icon(Icons.notifications_outlined,
                    color: _notifStatusColor()),
                title: const Text('Notificaciones push'),
                subtitle: Text(_notifStatusText()),
                value: _notifEnabled,
                onChanged: (v) =>
                    _saveSetting(SettingKey.notifListenerEnabled, v),
              ),
              if (_notifEnabled && !_hasNotifPermission)
                Padding(
                  padding:
                      const EdgeInsets.only(left: 72, right: 16, bottom: 8),
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.settings, size: 18),
                    label: const Text(
                        'Configurar acceso a notificaciones'),
                    onPressed: _requestNotifPermission,
                  ),
                ),
            ],

            // Binance API (all platforms)
            SwitchListTile(
              secondary:
                  Icon(Icons.sync, color: _binanceStatusColor()),
              title: const Text('Binance API'),
              subtitle: Text(_binanceStatusText()),
              value: _binanceApiEnabled,
              onChanged: (v) =>
                  _saveSetting(SettingKey.binanceApiEnabled, v),
            ),
            if (_binanceApiEnabled)
              Padding(
                padding:
                    const EdgeInsets.only(left: 72, right: 16, bottom: 8),
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.key, size: 18),
                  label: Text(_hasBinanceCreds
                      ? 'Configurar credenciales'
                      : 'Agregar credenciales'),
                  onPressed: () async {
                    await RouteUtils.pushRoute(
                        const BinanceApiConfigPage());
                    await _checkPermissions();
                    // Re-apply settings after config change
                    try {
                      await CaptureOrchestrator.instance.applySettings();
                      await WallexBackgroundService.instance
                          .restartOrchestrator();
                    } catch (_) {}
                  },
                ),
              ),

            const Divider(),

            // Bank profiles section
            _sectionLabel(context, 'Perfiles de banco'),

            if (isAndroid) ...[
              SwitchListTile(
                title: const Text('BDV (SMS)'),
                subtitle: const Text('Banco de Venezuela via SMS'),
                value: _bdvSmsProfileEnabled,
                onChanged: (v) =>
                    _saveSetting(SettingKey.bdvSmsProfileEnabled, v),
              ),
              SwitchListTile(
                title: const Text('BDV (Notificaciones)'),
                subtitle:
                    const Text('Banco de Venezuela via notificaciones'),
                value: _bdvNotifProfileEnabled,
                onChanged: (v) =>
                    _saveSetting(SettingKey.bdvNotifProfileEnabled, v),
              ),
            ],
            SwitchListTile(
              title: const Text('Binance (API)'),
              subtitle: const Text('Binance via API REST'),
              value: _binanceApiProfileEnabled,
              onChanged: (v) =>
                  _saveSetting(SettingKey.binanceApiProfileEnabled, v),
            ),
            ListTile(
              title: const Text('Zinli'),
              subtitle: const Text('Proximamente'),
              enabled: false,
              trailing: Chip(
                label: Text('Pronto',
                    style: TextStyle(
                        fontSize: 11,
                        color: theme.colorScheme.onSurfaceVariant)),
                visualDensity: VisualDensity.compact,
              ),
            ),

            const Divider(),

            // Pending imports link
            _sectionLabel(context, 'Bandeja de movimientos'),
            StreamBuilder<int>(
              stream:
                  PendingImportService.instance.watchPendingCount(),
              builder: (context, snapshot) {
                final count = snapshot.data ?? 0;
                return ListTile(
                  leading: const Icon(Icons.inbox),
                  title: const Text('Ver bandeja de movimientos'),
                  subtitle: Text('$count pendiente(s)'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => RouteUtils.pushRoute(
                      const PendingImportsPage()),
                );
              },
            ),

            const Divider(),

            // Diagnostics section
            ExpansionTile(
              title: const Text('Diagnostico'),
              leading: const Icon(Icons.bug_report_outlined),
              children: [
                ListTile(
                  title: const Text('Forzar sincronizacion ahora'),
                  leading: const Icon(Icons.refresh),
                  onTap: () async {
                    try {
                      final count = await CaptureOrchestrator.instance
                          .pollNow();
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                                'Sincronizacion completada ($count fuentes)'),
                          ),
                        );
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Error: $e')),
                        );
                      }
                    }
                  },
                ),
                ListTile(
                  title: const Text('Ver historial de capturas'),
                  leading: const Icon(Icons.history),
                  subtitle: const Text(
                      'Diagnostico detallado de cada notificacion/SMS'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => RouteUtils.pushRoute(
                      const CaptureDiagnosticsPage()),
                ),
              ],
            ),

            // Permissions checklist entry (Tanda 3).
            // Replaces the old generic battery-optimization card with a
            // dedicated guided flow that handles MIUI autostart, Doze
            // whitelist and OEM-specific battery tweaks.
            if (isAndroid)
              ListTile(
                leading: Icon(Icons.shield_outlined,
                    color: theme.colorScheme.primary),
                title: const Text('Permisos del listener'),
                subtitle: const Text(
                    'Autoarranque, batería y accesos para Xiaomi/MIUI'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () =>
                    RouteUtils.pushRoute(const CapturePermissionsPage()),
              ),
          ],
        ],
      ),
    );
  }

  Widget _sectionLabel(BuildContext context, String label) {
    return Padding(
      padding: const EdgeInsets.only(left: 16, top: 12, bottom: 4),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }

  // SMS status helpers
  String _smsStatusText() {
    if (!_smsEnabled) return 'Desactivado';
    if (!_hasSmsPermission) return 'Sin permiso';
    return 'Activo';
  }

  Color _smsStatusColor() {
    if (!_smsEnabled) return Colors.grey;
    if (!_hasSmsPermission) return Colors.orange;
    return Colors.green;
  }

  // Notification status helpers
  String _notifStatusText() {
    if (!_notifEnabled) return 'Desactivado';
    if (!_hasNotifPermission) return 'Sin permiso';
    return 'Activo';
  }

  Color _notifStatusColor() {
    if (!_notifEnabled) return Colors.grey;
    if (!_hasNotifPermission) return Colors.orange;
    return Colors.green;
  }

  // Binance status helpers
  String _binanceStatusText() {
    if (!_binanceApiEnabled) return 'Desactivado';
    if (!_hasBinanceCreds) return 'Sin credenciales';
    return 'Conectado';
  }

  Color _binanceStatusColor() {
    if (!_binanceApiEnabled) return Colors.grey;
    if (!_hasBinanceCreds) return Colors.orange;
    return Colors.green;
  }

  Future<void> _requestSmsPermission() async {
    final status = await Permission.sms.request();
    if (status.isGranted) {
      _hasSmsPermission = true;
      if (mounted) setState(() {});
    } else if (status.isPermanentlyDenied) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
                'Permiso de SMS denegado. Abre configuracion del sistema.'),
            action: SnackBarAction(
              label: 'Abrir',
              onPressed: openAppSettings,
            ),
          ),
        );
      }
    }
  }

  Future<void> _requestNotifPermission() async {
    // Request the notification-listener binding (real dependency for the
    // notifications capture channel). Also fire the POST_NOTIFICATIONS
    // runtime request so Android 13+ foreground notifications work.
    try {
      await PermissionCoordinator.instance.requestPostNotifications();
      await PermissionCoordinator.instance.requestNotificationListener();
    } catch (_) {}
    final permState = await PermissionCoordinator.instance.check();
    _hasNotifPermission = permState.notificationListener;
    if (mounted) setState(() {});
    if (!_hasNotifPermission && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
              'Habilita el acceso a notificaciones en configuracion del sistema.'),
          action: SnackBarAction(
            label: 'Abrir',
            onPressed: openAppSettings,
          ),
        ),
      );
    }
  }
}

/// Reactive banner that surfaces the listener health status computed by
/// [CaptureHealthMonitor]. Re-runs on every status change and, on tap, asks
/// the monitor to force a re-check + re-subscribe attempt.
class _CaptureHealthBanner extends StatelessWidget {
  final Future<void> Function() onRequestPermission;

  const _CaptureHealthBanner({
    required this.onRequestPermission,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<CaptureHealthStatus>(
      valueListenable: CaptureHealthMonitor.instance.statusNotifier,
      builder: (context, status, _) {
        final theme = Theme.of(context);
        final lastEvent = CaptureHealthMonitor.instance.lastEventAt;

        final (bg, fg, icon, title, subtitle) = _palette(
          status: status,
          theme: theme,
          lastEvent: lastEvent,
        );

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Material(
            color: bg,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => _onTap(context, status),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(icon, color: fg, size: 22),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: fg,
                              fontSize: 14,
                            ),
                          ),
                          if (subtitle != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              subtitle,
                              style: TextStyle(
                                color: fg,
                                fontSize: 12.5,
                              ),
                            ),
                          ],
                          const SizedBox(height: 2),
                          ValueListenableBuilder<DateTime?>(
                            valueListenable: CaptureHealthMonitor
                                .instance.lastResubscribeAtNotifier,
                            builder: (context, ts, _) {
                              return Text(
                                'Última reconexión automática: '
                                '${ts == null ? 'nunca' : _relative(ts)}',
                                style: TextStyle(
                                  color: fg,
                                  fontSize: 12.5,
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _onTap(
    BuildContext context,
    CaptureHealthStatus status,
  ) async {
    switch (status) {
      case CaptureHealthStatus.permissionMissing:
        // Tanda 3: route to the guided permissions checklist instead of
        // bouncing the user to a generic system screen.
        await RouteUtils.pushRoute(const CapturePermissionsPage());
        break;
      case CaptureHealthStatus.unsubscribed:
      case CaptureHealthStatus.stale:
      case CaptureHealthStatus.healthy:
      case CaptureHealthStatus.unknown:
        final messenger = ScaffoldMessenger.of(context);
        // "In progress" snack — kept as indefinite so we can hide it
        // ourselves when repairNow() returns.
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Reparando listener...'),
            duration: Duration(seconds: 30),
          ),
        );
        final recovered = await CaptureHealthMonitor.instance.repairNow();
        messenger.hideCurrentSnackBar();
        if (context.mounted) {
          messenger.showSnackBar(
            SnackBar(
              content: Text(
                recovered
                    ? 'Listener reparado'
                    : 'No se pudo recuperar, revisa permisos',
              ),
              duration: const Duration(seconds: 3),
            ),
          );
        }
        break;
    }
  }

  (Color bg, Color fg, IconData icon, String title, String? subtitle) _palette({
    required CaptureHealthStatus status,
    required ThemeData theme,
    required DateTime? lastEvent,
  }) {
    switch (status) {
      case CaptureHealthStatus.healthy:
        return (
          Colors.green.shade50,
          Colors.green.shade900,
          Icons.check_circle_outline,
          'Listener activo',
          lastEvent != null
              ? 'Ultimo evento ${_relative(lastEvent)}'
              : 'Esperando el primer evento',
        );
      case CaptureHealthStatus.stale:
        return (
          Colors.amber.shade50,
          Colors.amber.shade900,
          Icons.warning_amber_outlined,
          'Sin eventos recientes (${kStaleEventThreshold.inHours}h+)',
          'Puede estar bloqueado por el sistema. '
              'Toca para reintentar suscripcion.',
        );
      case CaptureHealthStatus.unsubscribed:
        return (
          Colors.red.shade50,
          Colors.red.shade900,
          Icons.link_off,
          'Listener desconectado',
          'Toca para reconectar.',
        );
      case CaptureHealthStatus.permissionMissing:
        return (
          Colors.red.shade50,
          Colors.red.shade900,
          Icons.lock_outline,
          'Permiso de notificaciones revocado',
          'Toca para reabrir ajustes del sistema.',
        );
      case CaptureHealthStatus.unknown:
        return (
          theme.colorScheme.surfaceContainerHighest,
          theme.colorScheme.onSurfaceVariant,
          Icons.hourglass_empty,
          'Evaluando estado del listener...',
          null,
        );
    }
  }

  String _relative(DateTime ts) {
    final diff = DateTime.now().difference(ts);
    if (diff.inSeconds < 60) return 'ahora';
    if (diff.inMinutes < 60) return 'hace ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'hace ${diff.inHours} h';
    if (diff.inDays < 7) return 'hace ${diff.inDays} d';
    return '${ts.year}-${ts.month.toString().padLeft(2, '0')}-'
        '${ts.day.toString().padLeft(2, '0')}';
  }
}
