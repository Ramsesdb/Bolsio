import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:installed_apps/installed_apps.dart';

/// Detects which banking / fintech apps relevant to Wallex auto-import
/// are installed on the device. Wraps the `installed_apps` package so
/// UI code never imports it directly — this is the only point in the
/// codebase allowed to depend on that library.
///
/// Returns a list of bank profile ids (e.g. `bdv_notif`, `zinli_notif`,
/// `binance_api`) matching [BankProfile.profileId] values. On non-Android
/// platforms or on any error, returns `const []`.
class BankDetectionService {
  /// Maps Android package names to the bank profile id Wallex uses to
  /// toggle per-bank auto-import settings.
  ///
  /// Only profiles with a matching [BankProfile] implementation and
  /// [SettingKey] toggle are listed here. Detection of an app that has
  /// no profile yet is dropped silently.
  static const Map<String, String> _kPackageToProfileId = {
    // Banco de Venezuela (SMS + notifications share the same app).
    'com.tralix.bdvmovil': 'bdv_notif',
    // Zinli.
    'com.zinli.wallet': 'zinli_notif',
    // Binance.
    'com.binance.dev': 'binance_api',
  };

  Future<List<String>> getInstalledBankIds() async {
    if (!Platform.isAndroid) return const [];
    try {
      final apps = await InstalledApps.getInstalledApps(true, false);
      final detected = <String>{};
      for (final app in apps) {
        final profileId = _kPackageToProfileId[app.packageName];
        if (profileId != null) detected.add(profileId);
      }
      return detected.toList();
    } catch (e) {
      debugPrint('BankDetectionService: getInstalledBankIds error: $e');
      return const [];
    }
  }
}
