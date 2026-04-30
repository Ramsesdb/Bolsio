import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:installed_apps/installed_apps.dart';
import 'package:kilatex/core/services/auto_import/supported_banks.dart'
    as supported_banks;

/// Detects which banking / fintech apps relevant to Wallex auto-import
/// are installed on the device. Wraps the `installed_apps` package so
/// UI code never imports it directly — this is the only point in the
/// codebase allowed to depend on that library.
///
/// Returns a list of bank profile ids (e.g. `bdv_notif`, `zinli_notif`,
/// `binance_api`) matching [BankProfile.profileId] values. On non-Android
/// platforms or on any error, returns `const []`.
class BankDetectionService {
  /// Public read-only view of the package-name → profile-id map.
  ///
  /// Used by [CaptureOrchestrator] to determine whether a notification sender
  /// is a known bank (even if no regex profile exists for it yet), so the
  /// LLM fallback can be triggered selectively.
  ///
  /// The single source of truth lives in
  /// `lib/core/services/auto_import/supported_banks.dart` —
  /// edit [supported_banks.kSupportedBanks] to add a new bank, then update
  /// AndroidManifest.xml `<queries>` (the `supported_banks_manifest_sync`
  /// test will tell you which packages are missing).
  static Map<String, String> get kPackageToProfileId =>
      supported_banks.kPackageToProfileId;

  Future<List<String>> getInstalledBankIds() async {
    if (!Platform.isAndroid) return const [];
    try {
      final apps = await InstalledApps.getInstalledApps(true, false);
      final detected = <String>{};
      final map = supported_banks.kPackageToProfileId;
      for (final app in apps) {
        final profileId = map[app.packageName];
        if (profileId != null) detected.add(profileId);
      }
      return detected.toList();
    } catch (e) {
      debugPrint('BankDetectionService: getInstalledBankIds error: $e');
      return const [];
    }
  }
}
