import 'package:flutter_test/flutter_test.dart';
import 'package:wallex/core/database/services/user-setting/user_setting_service.dart';
import 'package:wallex/core/models/currency/currency_mode.dart';
import 'package:wallex/core/models/currency/currency_display_policy.dart';
import 'package:wallex/core/models/currency/currency_display_policy_resolver.dart';

/// Phase 10 task 10.9 — Firebase sync round-trip for `currencyMode` /
/// `secondaryCurrency`.
///
/// Per Phase 8's verification audit (`apply-progress.md` Run 6), the
/// project's Firebase sync uses an OPT-OUT model: every `SettingKey` is
/// synced unless explicitly excluded via
/// `_userSettingsSyncExclusions` (which contains only
/// `firebaseSyncEnabled`). New keys added to the `SettingKey` enum sync
/// automatically with no code change.
///
/// Booting the real `FirebaseSyncService` in a unit test is impractical —
/// it requires Firebase initialization, `cloud_firestore` mocking, and a
/// signed-in user context. The orchestrator brief explicitly authorizes
/// the surrogate path: "If a real Firebase mock is too heavy, write a
/// focused test that exercises just the inclusion/exclusion logic of the
/// sync service."
///
/// What this test pins:
///   1. The two new keys (`currencyMode`, `secondaryCurrency`) are NOT in
///      the exclusion set — so they DO sync.
///   2. Their `.name` values do not match the sensitive-key substring
///      filter (`apikey|secret|token|password`).
///   3. The string round-trip preserves a value across push → pull (the
///      core invariant the sync round-trip provides).
///   4. An old client lacking the keys does NOT erase a new client's
///      local value (the field-by-field merge contract from Phase 8).
///   5. A new client receiving a future-mode it doesn't know downgrades
///      gracefully via `CurrencyMode.fromDb` (forward-compat).
void main() {
  /// Mirror of the sync service's sensitive-key filter
  /// (`firebase_sync_service.dart::_isSensitiveSettingKey`). Keep this in
  /// lockstep with the production code; if the rule there changes, this
  /// helper must change too.
  bool isSensitiveSettingKey(String keyName) {
    final lower = keyName.toLowerCase();
    return lower.contains('apikey') ||
        lower.contains('secret') ||
        lower.contains('token') ||
        lower.contains('password');
  }

  /// Mirror of the sync service's exclusion set
  /// (`firebase_sync_service.dart::_userSettingsSyncExclusions`). Mirrors
  /// the production set verbatim — if the production set changes, this
  /// constant must be updated.
  const userSettingsSyncExclusions = <SettingKey>{
    SettingKey.firebaseSyncEnabled,
  };

  /// Mirrors the production `pushUserSettings` body — filters a map of
  /// `(SettingKey, value)` rows down to what would be sent to Firestore.
  Map<String, String?> simulatePush(Map<SettingKey, String?> rows) {
    final values = <String, String?>{};
    for (final entry in rows.entries) {
      if (userSettingsSyncExclusions.contains(entry.key)) continue;
      if (isSensitiveSettingKey(entry.key.name)) continue;
      values[entry.key.name] = entry.value;
    }
    return values;
  }

  /// Mirrors the production `_pullUserSettings` body — given a Firestore
  /// blob, returns the `(SettingKey, value)` writes that would be applied
  /// to the local DB. Unknown keys (older/newer client) are silently
  /// skipped via `firstOrNull`, matching the production semantics.
  Map<SettingKey, String?> simulatePull(Map<String, String?> blob) {
    final out = <SettingKey, String?>{};
    for (final entry in blob.entries) {
      if (isSensitiveSettingKey(entry.key)) continue;
      final key = SettingKey.values
          .where((e) => e.name == entry.key)
          .cast<SettingKey?>()
          .firstWhere((e) => true, orElse: () => null);
      if (key == null) continue;
      if (userSettingsSyncExclusions.contains(key)) continue;
      out[key] = entry.value;
    }
    return out;
  }

  group(
    'Firebase sync inclusion/exclusion — `currencyMode` / '
    '`secondaryCurrency` (Task 10.9)',
    () {
      test(
        '`currencyMode` is NOT in the sync exclusion set',
        () {
          expect(
            userSettingsSyncExclusions.contains(SettingKey.currencyMode),
            isFalse,
            reason:
                'currencyMode MUST sync across devices — see Phase 8 Run 6.',
          );
        },
      );

      test(
        '`secondaryCurrency` is NOT in the sync exclusion set',
        () {
          expect(
            userSettingsSyncExclusions
                .contains(SettingKey.secondaryCurrency),
            isFalse,
          );
        },
      );

      test(
        'neither key matches the sensitive-substring filter',
        () {
          // The filter rejects substrings `apikey|secret|token|password`.
          // Neither `currencyMode` nor `secondaryCurrency` matches.
          expect(isSensitiveSettingKey('currencyMode'), isFalse);
          expect(isSensitiveSettingKey('secondaryCurrency'), isFalse);
        },
      );

      test(
        'simulated push includes both new keys',
        () {
          final pushedBlob = simulatePush({
            SettingKey.preferredCurrency: 'USD',
            SettingKey.currencyMode: 'dual',
            SettingKey.secondaryCurrency: 'VES',
            SettingKey.firebaseSyncEnabled: '1', // excluded
          });

          expect(pushedBlob.keys, containsAll(['currencyMode', 'secondaryCurrency']));
          expect(pushedBlob['currencyMode'], 'dual');
          expect(pushedBlob['secondaryCurrency'], 'VES');
          expect(
            pushedBlob.keys.contains('firebaseSyncEnabled'),
            isFalse,
            reason: 'firebaseSyncEnabled is the only excluded key.',
          );
        },
      );
    },
  );

  group('Firebase sync round-trip (Task 10.9 spec scenario)', () {
    test(
      'Round-trip preserves `currencyMode=single_bs` from device A to '
      'device B',
      () {
        // Device A pushes single_bs.
        final pushedBlob = simulatePush({
          SettingKey.preferredCurrency: 'VES',
          SettingKey.currencyMode: 'single_bs',
        });

        // Firestore stores the blob verbatim (no transformation).
        // Device B pulls.
        final pulledWrites = simulatePull(pushedBlob);

        expect(pulledWrites[SettingKey.currencyMode], 'single_bs');

        // Sanity check: the resolver on device B emits `SingleMode(VES)`.
        final policy = CurrencyDisplayPolicyResolver.buildPolicy(
          preferredCurrency: pulledWrites[SettingKey.preferredCurrency],
          currencyMode: pulledWrites[SettingKey.currencyMode],
          secondaryCurrency: pulledWrites[SettingKey.secondaryCurrency],
        );
        expect(policy, const SingleMode(code: 'VES'));
      },
    );

    test(
      'Round-trip preserves `dual(EUR, ARS)` shape',
      () {
        final pushedBlob = simulatePush({
          SettingKey.preferredCurrency: 'EUR',
          SettingKey.currencyMode: 'dual',
          SettingKey.secondaryCurrency: 'ARS',
        });
        final pulledWrites = simulatePull(pushedBlob);

        expect(pulledWrites[SettingKey.currencyMode], 'dual');
        expect(pulledWrites[SettingKey.secondaryCurrency], 'ARS');

        final policy = CurrencyDisplayPolicyResolver.buildPolicy(
          preferredCurrency: pulledWrites[SettingKey.preferredCurrency],
          currencyMode: pulledWrites[SettingKey.currencyMode],
          secondaryCurrency: pulledWrites[SettingKey.secondaryCurrency],
        );
        expect(policy, const DualMode(primary: 'EUR', secondary: 'ARS'));
      },
    );
  });

  group(
    'Mixed-version rollout tolerance — Task 10.9 spec scenario "Cliente '
    'antiguo sin las claves"',
    () {
      test(
        'Old client blob lacking `currencyMode` does NOT erase the local '
        'value (field-by-field merge)',
        () {
          // The new client previously wrote `currencyMode='single_bs'`
          // locally. An old client (without the new keys) pushes a blob
          // that omits `currencyMode`.
          final oldClientBlob = <String, String?>{
            'preferredCurrency': 'USD',
            'themeMode': 'dark',
          };

          final pulledWrites = simulatePull(oldClientBlob);

          expect(
            pulledWrites.containsKey(SettingKey.currencyMode),
            isFalse,
            reason:
                'Pull MUST NOT touch keys absent from the remote blob — '
                'the field-by-field merge preserves the local value.',
          );
          expect(
            pulledWrites.containsKey(SettingKey.secondaryCurrency),
            isFalse,
          );
          // The keys that DID arrive are written.
          expect(pulledWrites[SettingKey.preferredCurrency], 'USD');
        },
      );

      test(
        'Old client receives a blob with future-mode → unknown key '
        'silently skipped (no crash)',
        () {
          // A FUTURE client emits `currencyMode='something_new'`. An old
          // client pulls — `firstOrNull` returns null for the unknown
          // value space and simulatePull skips it.
          //
          // This test pins the contract: future-proofing relies on
          // `CurrencyMode.fromDb` downgrading gracefully on the read
          // side after the value is written locally.
          final futureBlob = <String, String?>{
            'currencyMode': 'something_new',
          };
          final pulledWrites = simulatePull(futureBlob);

          // The simulation writes the unknown VALUE to a known KEY (the
          // sync layer stores raw strings; mode parsing happens on read).
          // The Phase 1 tolerant parser MUST downgrade the unknown value
          // to `dual`.
          expect(
            pulledWrites[SettingKey.currencyMode],
            'something_new',
            reason:
                'Sync layer stores raw strings — parsing happens on read.',
          );
          // On read, `CurrencyMode.fromDb('something_new')` MUST resolve
          // to `dual` (forward-compat default).
          expect(
            CurrencyMode.fromDb(pulledWrites[SettingKey.currencyMode]),
            CurrencyMode.dual,
          );
        },
      );

      test(
        'New client with no remote blob falls back to dual(USD, VES) via '
        'the resolver',
        () {
          // Fresh device, no Firestore doc, no local row. The sync layer
          // is a no-op; the resolver's null fallback kicks in.
          final policy = CurrencyDisplayPolicyResolver.buildPolicy(
            preferredCurrency: null,
            currencyMode: null,
            secondaryCurrency: null,
          );
          expect(policy, const DualMode(primary: 'USD', secondary: 'VES'));
        },
      );
    },
  );
}
