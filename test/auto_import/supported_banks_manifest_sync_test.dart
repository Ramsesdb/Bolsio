import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nitido/core/services/auto_import/supported_banks.dart';

/// Guards the contract that every package in [kSupportedBanks] is also
/// listed in `<queries>` of `android/app/src/main/AndroidManifest.xml`.
///
/// `installed_apps` cannot enumerate apps on Android 11+ HyperOS / MIUI
/// without an explicit `<package>` entry, so a missing entry would silently
/// hide a supported bank from onboarding detection. This test fires before
/// CI and prints exactly which packages need to be added.
void main() {
  test(
    'AndroidManifest.xml <queries> contains every package in kSupportedBanks',
    () {
      final manifestFile = File('android/app/src/main/AndroidManifest.xml');
      expect(
        manifestFile.existsSync(),
        isTrue,
        reason:
            'AndroidManifest.xml not found at android/app/src/main/AndroidManifest.xml',
      );

      final manifestContent = manifestFile.readAsStringSync();

      final missing = <String>[];
      for (final pkg in kAllSupportedPackages) {
        // Match `<package android:name="<pkg>" />`. Quoting the value
        // disambiguates packages that share a prefix.
        final pattern = 'android:name="$pkg"';
        if (!manifestContent.contains(pattern)) {
          missing.add(pkg);
        }
      }

      expect(
        missing,
        isEmpty,
        reason:
            'The following packages are declared in kSupportedBanks but '
            'missing from AndroidManifest.xml <queries>:\n'
            '  - ${missing.join("\n  - ")}\n'
            'Add a `<package android:name="..." />` entry for each one to '
            'the <queries> block in '
            '`android/app/src/main/AndroidManifest.xml`.',
      );
    },
  );
}
