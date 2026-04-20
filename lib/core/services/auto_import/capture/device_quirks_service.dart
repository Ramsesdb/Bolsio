import 'dart:io' show Platform;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Identified OEM families that impose extra background-execution rules on
/// top of vanilla Android. Used to tailor the permission-onboarding UX.
enum OemQuirk {
  /// Xiaomi / Redmi / POCO running MIUI.
  miui,

  /// Xiaomi flagships on HyperOS (MIUI successor). Treated like MIUI for
  /// the autostart deep-link but kept as a separate label for UI copy.
  hyperos,
  huawei,
  samsung,
  oppo,
  vivo,
  realme,
  none,
}

/// User-facing step shown in the permission checklist when the detected OEM
/// has known quirks (e.g. MIUI autostart).
@immutable
class QuirkInstruction {
  final String titleEs;
  final String titleEn;
  final String descEs;
  final String descEn;
  final String ctaEs;
  final String ctaEn;

  /// Stable id used to persist "user said they did it" flags.
  final String id;

  const QuirkInstruction({
    required this.id,
    required this.titleEs,
    required this.titleEn,
    required this.descEs,
    required this.descEn,
    required this.ctaEs,
    required this.ctaEn,
  });
}

/// Detects the OEM of the current device and exposes deep-links to the
/// OEM-specific autostart / battery optimization screens through the
/// `com.wallex.capture/quirks` MethodChannel.
class DeviceQuirksService {
  static final DeviceQuirksService instance = DeviceQuirksService._();

  DeviceQuirksService._();

  static const MethodChannel _channel = MethodChannel('com.wallex.capture/quirks');

  OemQuirk? _cached;

  /// Best-effort OEM detection via `device_info_plus`. On iOS (or if the
  /// plugin fails), returns [OemQuirk.none] so that the UI falls back to the
  /// generic checklist.
  Future<OemQuirk> detect() async {
    if (_cached != null) return _cached!;
    if (!Platform.isAndroid) {
      _cached = OemQuirk.none;
      return _cached!;
    }
    try {
      final info = await DeviceInfoPlugin().androidInfo;
      final manufacturer = info.manufacturer.toLowerCase();
      final brand = info.brand.toLowerCase();
      final combined = '$manufacturer/$brand';

      OemQuirk quirk;
      if (combined.contains('xiaomi') ||
          combined.contains('redmi') ||
          combined.contains('poco')) {
        // HyperOS vs MIUI: we don't have a reliable programmatic check across
        // firmware versions, so we map all Xiaomi family devices to `miui`
        // for deep-link purposes. Kept separate in the enum in case we want
        // different UI copy later.
        quirk = OemQuirk.miui;
      } else if (combined.contains('huawei') || combined.contains('honor')) {
        quirk = OemQuirk.huawei;
      } else if (combined.contains('samsung')) {
        quirk = OemQuirk.samsung;
      } else if (combined.contains('oppo')) {
        quirk = OemQuirk.oppo;
      } else if (combined.contains('vivo')) {
        quirk = OemQuirk.vivo;
      } else if (combined.contains('realme')) {
        quirk = OemQuirk.realme;
      } else {
        quirk = OemQuirk.none;
      }
      _cached = quirk;
      return quirk;
    } catch (e) {
      debugPrint('DeviceQuirksService: detect error (assuming none): $e');
      _cached = OemQuirk.none;
      return OemQuirk.none;
    }
  }

  /// Best-effort: is the app in the OS battery-optimization whitelist.
  /// Non-Android returns `true` (not applicable).
  Future<bool> isIgnoringBatteryOptimizations() async {
    if (!Platform.isAndroid) return true;
    try {
      final res = await _channel
          .invokeMethod<bool>('isIgnoringBatteryOptimizations');
      return res ?? false;
    } catch (e) {
      debugPrint(
        'DeviceQuirksService: isIgnoringBatteryOptimizations error: $e',
      );
      return false;
    }
  }

  /// Opens the system "battery optimizations" whitelist screen. Returns
  /// whether the intent was dispatched (not whether the user accepted).
  Future<bool> openBatteryOptimizationSettings() async {
    if (!Platform.isAndroid) return false;
    try {
      final res = await _channel.invokeMethod<bool>('openBatteryOptimization');
      return res ?? false;
    } catch (e) {
      debugPrint(
        'DeviceQuirksService: openBatteryOptimizationSettings error: $e',
      );
      return false;
    }
  }

  /// Opens the OEM-specific autostart panel when available. Falls back to
  /// the generic app-details screen on the native side.
  Future<bool> openAutostartSettings() async {
    if (!Platform.isAndroid) return false;
    final quirk = await detect();
    try {
      final res = await _channel.invokeMethod<bool>(
        'openAutostart',
        <String, String>{'quirk': quirk.name},
      );
      return res ?? false;
    } catch (e) {
      debugPrint('DeviceQuirksService: openAutostartSettings error: $e');
      return false;
    }
  }

  /// Opens the generic "App info" settings page for this app.
  Future<bool> openAppDetails() async {
    if (!Platform.isAndroid) return false;
    try {
      final res = await _channel.invokeMethod<bool>('openAppDetails');
      return res ?? false;
    } catch (e) {
      debugPrint('DeviceQuirksService: openAppDetails error: $e');
      return false;
    }
  }

  /// Extra manual steps for the detected OEM. Returns an empty list for
  /// [OemQuirk.none] so callers can short-circuit.
  List<QuirkInstruction> instructionsFor(OemQuirk quirk) {
    switch (quirk) {
      case OemQuirk.miui:
      case OemQuirk.hyperos:
        return const [
          QuirkInstruction(
            id: 'miui_autostart',
            titleEs: 'Autoarranque (MIUI)',
            titleEn: 'Autostart (MIUI)',
            descEs: 'Xiaomi impide que las apps sin autoarranque se '
                'reactiven después de cerrarlas. Activalo en Seguridad → '
                'Permisos → Autoarranque → Wallex.',
            descEn: 'Xiaomi blocks apps without autostart from restarting '
                'after being closed. Enable it in Security → Permissions → '
                'Autostart → Wallex.',
            ctaEs: 'Abrir autoarranque',
            ctaEn: 'Open autostart',
          ),
          QuirkInstruction(
            id: 'miui_battery_app',
            titleEs: 'Batería sin restricciones (MIUI)',
            titleEn: 'No battery restrictions (MIUI)',
            descEs: 'Además de la lista blanca del sistema, MIUI tiene un '
                'control extra en Seguridad → Batería → Wallex → Sin '
                'restricciones. Sin esto el listener se detiene en segundo '
                'plano.',
            descEn: 'On top of the system whitelist, MIUI has an extra '
                'control in Security → Battery → Wallex → No restrictions. '
                'Without it the listener stops in the background.',
            ctaEs: 'Abrir ajustes de la app',
            ctaEn: 'Open app settings',
          ),
        ];
      case OemQuirk.huawei:
        return const [
          QuirkInstruction(
            id: 'huawei_protected',
            titleEs: 'Apps protegidas (Huawei)',
            titleEn: 'Protected apps (Huawei)',
            descEs: 'EMUI mata las apps al cerrar la pantalla. Marcá '
                'Wallex como protegida en Ajustes → Batería → Inicio de '
                'aplicaciones.',
            descEn: 'EMUI kills apps when the screen turns off. Mark '
                'Wallex as protected in Settings → Battery → App launch.',
            ctaEs: 'Abrir inicio de apps',
            ctaEn: 'Open app launch',
          ),
        ];
      case OemQuirk.oppo:
      case OemQuirk.realme:
        return const [
          QuirkInstruction(
            id: 'oppo_autostart',
            titleEs: 'Inicio automático (ColorOS)',
            titleEn: 'Auto-launch (ColorOS)',
            descEs: 'Habilitá Wallex en Ajustes → Batería → Gestión de '
                'inicio automático.',
            descEn: 'Enable Wallex in Settings → Battery → Auto-launch '
                'management.',
            ctaEs: 'Abrir inicio automático',
            ctaEn: 'Open auto-launch',
          ),
        ];
      case OemQuirk.vivo:
        return const [
          QuirkInstruction(
            id: 'vivo_autostart',
            titleEs: 'Autoarranque (Funtouch OS)',
            titleEn: 'Autostart (Funtouch OS)',
            descEs: 'Activá Wallex en Gestor de teléfono → Apps en segundo '
                'plano.',
            descEn: 'Enable Wallex in Phone manager → Background apps.',
            ctaEs: 'Abrir autoarranque',
            ctaEn: 'Open autostart',
          ),
        ];
      case OemQuirk.samsung:
        return const [
          QuirkInstruction(
            id: 'samsung_unrestricted',
            titleEs: 'Sin restricciones (One UI)',
            titleEn: 'Unrestricted (One UI)',
            descEs: 'En Device Care → Batería → Wallex → Sin restricciones.',
            descEn: 'In Device Care → Battery → Wallex → Unrestricted.',
            ctaEs: 'Abrir ajustes de batería',
            ctaEn: 'Open battery settings',
          ),
        ];
      case OemQuirk.none:
        return const [];
    }
  }

  @visibleForTesting
  void resetCache() {
    _cached = null;
  }
}
