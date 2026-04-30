import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:notification_listener_service/notification_listener_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kilatex/core/services/auto_import/capture/device_quirks_service.dart';

/// Snapshot of every permission / whitelist the capture pipeline needs to
/// stay alive on modern Android (especially MIUI).
@immutable
class CapturePermissionsState {
  /// NotificationListenerService binding — the core permission.
  final bool notificationListener;

  /// POST_NOTIFICATIONS runtime permission (Android 13+).
  final bool postNotifications;

  /// Whether the app is in the system battery-optimization whitelist.
  final bool batteryOptimizationsIgnored;

  /// OEM-specific autostart. We cannot programmatically verify this on
  /// MIUI, so we rely on a "I did it" flag persisted in SharedPreferences.
  /// `null` on OEMs where autostart is not a concern.
  final bool? autostartUserConfirmed;

  /// Extra OEM battery tweaks (e.g. MIUI Security → Battery → Unrestricted).
  /// Same caveat: user-confirmed flag.
  final bool? oemBatteryUserConfirmed;

  /// Detected OEM — dictates which extra steps are shown to the user.
  final OemQuirk quirk;

  /// Whether the OS-level "Allow restricted settings" AppOps gate is open.
  /// On API 31+ sideloaded installs, Android grays out the notification
  /// listener toggle until the user explicitly allows restricted settings
  /// from the App Info kebab menu. `true` means the gate is open (or N/A:
  /// non-Android, pre-API-31, or detection failed — fail-open).
  final bool restrictedSettingsAllowed;

  const CapturePermissionsState({
    required this.notificationListener,
    required this.postNotifications,
    required this.batteryOptimizationsIgnored,
    required this.autostartUserConfirmed,
    required this.oemBatteryUserConfirmed,
    required this.quirk,
    this.restrictedSettingsAllowed = true,
  });

  factory CapturePermissionsState.initial() => const CapturePermissionsState(
        notificationListener: false,
        postNotifications: false,
        batteryOptimizationsIgnored: false,
        autostartUserConfirmed: null,
        oemBatteryUserConfirmed: null,
        quirk: OemQuirk.none,
        restrictedSettingsAllowed: true,
      );

  /// The three permissions that must be granted for the capture pipeline to
  /// be considered wired up. Autostart / OEM battery extras degrade
  /// reliability but don't outright break the listener, so they're not part
  /// of this gate — they surface as warnings in the UI.
  bool get allCriticalGranted =>
      notificationListener && postNotifications && batteryOptimizationsIgnored;

  /// Whether every OEM-specific step the user confirmed manually is done.
  bool get allQuirksConfirmed {
    final a = autostartUserConfirmed;
    final b = oemBatteryUserConfirmed;
    return (a == null || a == true) && (b == null || b == true);
  }

  CapturePermissionsState copyWith({
    bool? notificationListener,
    bool? postNotifications,
    bool? batteryOptimizationsIgnored,
    bool? autostartUserConfirmed,
    bool? oemBatteryUserConfirmed,
    OemQuirk? quirk,
    bool? restrictedSettingsAllowed,
  }) {
    return CapturePermissionsState(
      notificationListener: notificationListener ?? this.notificationListener,
      postNotifications: postNotifications ?? this.postNotifications,
      batteryOptimizationsIgnored:
          batteryOptimizationsIgnored ?? this.batteryOptimizationsIgnored,
      autostartUserConfirmed:
          autostartUserConfirmed ?? this.autostartUserConfirmed,
      oemBatteryUserConfirmed:
          oemBatteryUserConfirmed ?? this.oemBatteryUserConfirmed,
      quirk: quirk ?? this.quirk,
      restrictedSettingsAllowed:
          restrictedSettingsAllowed ?? this.restrictedSettingsAllowed,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CapturePermissionsState &&
        other.notificationListener == notificationListener &&
        other.postNotifications == postNotifications &&
        other.batteryOptimizationsIgnored == batteryOptimizationsIgnored &&
        other.autostartUserConfirmed == autostartUserConfirmed &&
        other.oemBatteryUserConfirmed == oemBatteryUserConfirmed &&
        other.quirk == quirk &&
        other.restrictedSettingsAllowed == restrictedSettingsAllowed;
  }

  @override
  int get hashCode => Object.hash(
        notificationListener,
        postNotifications,
        batteryOptimizationsIgnored,
        autostartUserConfirmed,
        oemBatteryUserConfirmed,
        quirk,
        restrictedSettingsAllowed,
      );
}

/// Singleton that evaluates every permission the capture pipeline depends on
/// and exposes it as a reactive [ValueNotifier] so UI (checklist + banner) and
/// the health monitor can converge on the same truth.
class PermissionCoordinator {
  static final PermissionCoordinator instance = PermissionCoordinator._();

  PermissionCoordinator._();

  static const String _prefsAutostartConfirmed =
      'capture_perms_autostart_confirmed';
  static const String _prefsOemBatteryConfirmed =
      'capture_perms_oem_battery_confirmed';

  final ValueNotifier<CapturePermissionsState> _stateNotifier =
      ValueNotifier<CapturePermissionsState>(
          CapturePermissionsState.initial());

  ValueListenable<CapturePermissionsState> get stateNotifier => _stateNotifier;
  CapturePermissionsState get state => _stateNotifier.value;

  bool _checking = false;

  /// Re-evaluate every permission and push the new snapshot to listeners.
  Future<CapturePermissionsState> check() async {
    if (_checking) return _stateNotifier.value;
    _checking = true;
    try {
      if (!Platform.isAndroid) {
        // iOS / desktop: most of this doesn't apply. Report as "granted"
        // so the capture pipeline isn't artificially flagged red.
        final safe = const CapturePermissionsState(
          notificationListener: true,
          postNotifications: true,
          batteryOptimizationsIgnored: true,
          autostartUserConfirmed: null,
          oemBatteryUserConfirmed: null,
          quirk: OemQuirk.none,
        );
        _setState(safe);
        return safe;
      }

      final prefs = await SharedPreferences.getInstance();
      final quirk = await DeviceQuirksService.instance.detect();

      final notifListener =
          await _safe(() => NotificationListenerService.isPermissionGranted(),
              fallback: false);
      final postNotif =
          await _safe(() async => (await Permission.notification.status).isGranted,
              fallback: false);
      final batteryOk = await _safe(
          () => DeviceQuirksService.instance.isIgnoringBatteryOptimizations(),
          fallback: false);

      bool? autostart;
      bool? oemBattery;
      final quirkInstructions =
          DeviceQuirksService.instance.instructionsFor(quirk);
      for (final ins in quirkInstructions) {
        if (ins.id == 'miui_autostart' ||
            ins.id == 'huawei_protected' ||
            ins.id == 'oppo_autostart' ||
            ins.id == 'vivo_autostart') {
          autostart = prefs.getBool(_prefsAutostartConfirmed) ?? false;
        }
        if (ins.id == 'miui_battery_app' || ins.id == 'samsung_unrestricted') {
          oemBattery = prefs.getBool(_prefsOemBatteryConfirmed) ?? false;
        }
      }

      final snapshot = CapturePermissionsState(
        notificationListener: notifListener,
        postNotifications: postNotif,
        batteryOptimizationsIgnored: batteryOk,
        autostartUserConfirmed: autostart,
        oemBatteryUserConfirmed: oemBattery,
        quirk: quirk,
      );
      _setState(snapshot);
      return snapshot;
    } finally {
      _checking = false;
    }
  }

  /// Alias of [check] — used by UI callers that want a more explicit name
  /// (e.g. "pull-to-refresh" or `AppLifecycleState.resumed`).
  Future<CapturePermissionsState> refresh() => check();

  /// Persist the user's "I already enabled autostart" self-report.
  Future<void> setAutostartConfirmed(bool confirmed) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefsAutostartConfirmed, confirmed);
    } catch (e) {
      debugPrint('PermissionCoordinator: setAutostartConfirmed error: $e');
    }
    await check();
  }

  /// Persist the user's "I already enabled the OEM battery option" self-report.
  Future<void> setOemBatteryConfirmed(bool confirmed) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefsOemBatteryConfirmed, confirmed);
    } catch (e) {
      debugPrint('PermissionCoordinator: setOemBatteryConfirmed error: $e');
    }
    await check();
  }

  /// Request notification listener binding. Idempotent — calling twice just
  /// reopens the system picker.
  Future<bool> requestNotificationListener() async {
    if (!Platform.isAndroid) return true;
    try {
      final ok = await NotificationListenerService.requestPermission();
      await check();
      return ok;
    } catch (e) {
      debugPrint(
        'PermissionCoordinator: requestNotificationListener error: $e',
      );
      return false;
    }
  }

  /// Request POST_NOTIFICATIONS runtime permission (Android 13+).
  Future<bool> requestPostNotifications() async {
    if (!Platform.isAndroid) return true;
    try {
      final status = await Permission.notification.request();
      await check();
      return status.isGranted;
    } catch (e) {
      debugPrint(
        'PermissionCoordinator: requestPostNotifications error: $e',
      );
      return false;
    }
  }

  void _setState(CapturePermissionsState next) {
    if (_stateNotifier.value == next) return;
    _stateNotifier.value = next;
  }

  static Future<T> _safe<T>(
    Future<T> Function() op, {
    required T fallback,
  }) async {
    try {
      return await op();
    } catch (e) {
      debugPrint('PermissionCoordinator: safe() caught $e');
      return fallback;
    }
  }
}
