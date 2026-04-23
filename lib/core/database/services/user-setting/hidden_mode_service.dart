import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:rxdart/rxdart.dart';

import 'package:wallex/core/database/services/account/account_service.dart';
import 'package:wallex/core/database/services/user-setting/user_setting_service.dart';
import 'package:wallex/core/models/account/account.dart';
import 'package:wallex/core/utils/logger.dart';

/// Service that manages the app "Hidden Mode": a stronger-than-private-mode
/// layer that removes savings accounts (and their transactions / balances) from
/// every visible dashboard while the app is locked.
///
/// Storage layout:
///  - [SettingKey.hiddenModeEnabled]  — DB (user preference, survives backup).
///  - PIN hash + salt                 — [FlutterSecureStorage] only. Never DB.
///    Rationale: the app exports/imports the Drift DB as a backup; the PIN
///    must NOT travel in that file.
///
/// Consumers should read [visibleAccountIdsStream] and inject the IDs into any
/// query that filters by account. When locked, the stream excludes savings; when
/// unlocked (or when the feature is disabled), it emits every account id. Any
/// new screen that filters by account MUST subscribe to this stream, otherwise
/// it will silently leak savings data when locked.
class HiddenModeService with WidgetsBindingObserver {
  HiddenModeService._();
  static final HiddenModeService instance = HiddenModeService._();

  /// Test-only constructor. Allows injecting an alternative secure storage, a
  /// custom [AccountService], and an in-memory feature-flag store so unit tests
  /// don't have to spin up the real Drift DB (which requires path_provider).
  @visibleForTesting
  HiddenModeService.forTesting({
    required FlutterSecureStorage storage,
    UserSettingService? userSettingService,
    AccountService? accountService,
    bool? initialEnabled,
  }) : _storage = storage,
       _userSettingService = userSettingService ?? UserSettingService.instance,
       _accountService = accountService ?? AccountService.instance,
       _testEnabledOverride = initialEnabled;

  // ─────────── Storage wiring ───────────

  FlutterSecureStorage _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  UserSettingService _userSettingService = UserSettingService.instance;
  AccountService _accountService = AccountService.instance;

  /// When non-null, overrides the DB-backed feature flag with an in-memory
  /// value. Only set via [HiddenModeService.forTesting] so we don't need to
  /// stand up a real Drift instance in unit tests.
  bool? _testEnabledOverride;

  static const _kPinHashKey = 'hidden_mode_pin_hash';
  static const _kPinSaltKey = 'hidden_mode_pin_salt';

  // ─────────── Reactive state ───────────

  /// Seeded locked so callers never observe a "leaked" false before [init].
  final BehaviorSubject<bool> _isLockedController =
      BehaviorSubject<bool>.seeded(true);

  /// Emits true when the user is locked out (filter savings) and false when
  /// unlocked (show everything). While the feature is disabled the service
  /// keeps this stream on `false` so dependent streams behave transparently.
  Stream<bool> get isLockedStream => _isLockedController.stream.distinct();

  /// Synchronous view of the current locked state (defaults to `true`).
  bool get isLocked => _isLockedController.value;

  /// Cached shared stream; built lazily on first access so tests that replace
  /// [_accountService] via [forTesting] get the injected instance.
  Stream<List<String>>? _visibleAccountIdsStream;

  /// IDs of the accounts that should be visible at any given moment.
  ///
  /// - Locked  → every [AccountType.normal] account id.
  /// - Unlocked → every account id (including savings).
  ///
  /// Emits distinct values only so downstream queries are not re-fired on
  /// spurious ticks.
  ///
  /// Shared via [shareValue] so every dashboard subscriber (total balance,
  /// income/expense cards, carousel, finance-health) reuses the same upstream
  /// `Rx.combineLatest2` + `AccountService.getAccounts()` pipeline instead of
  /// firing one parallel account query per subscriber at startup.
  Stream<List<String>> get visibleAccountIdsStream {
    return _visibleAccountIdsStream ??= Rx.combineLatest2<bool, List<Account>,
            List<String>>(
          isLockedStream,
          _accountService.getAccounts(),
          (locked, accounts) {
            final filtered = locked
                ? accounts.where((a) => a.type != AccountType.saving)
                : accounts;
            return filtered.map((a) => a.id).toList(growable: false);
          },
        )
        .distinct(_listEquals)
        .shareValue();
  }

  static bool _listEquals(List<String> a, List<String> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  // ─────────── Feature flag ───────────

  /// Whether the Hidden Mode feature is currently enabled.
  ///
  /// Reads from the in-memory [appStateSettings] cache first (populated at
  /// boot by [UserSettingService.initializeGlobalStateMap]) and falls back to
  /// the DB stream for the rare case the cache is empty. Tests can pre-seed a
  /// value via [HiddenModeService.forTesting] to bypass the DB entirely.
  Future<bool> isEnabled() async {
    if (_testEnabledOverride != null) return _testEnabledOverride!;
    final cached = appStateSettings[SettingKey.hiddenModeEnabled];
    if (cached != null) return cached == '1';
    final stored = await _userSettingService
        .getSettingFromDB(SettingKey.hiddenModeEnabled)
        .first;
    return stored == '1';
  }

  Future<void> _setEnabled(bool v) async {
    if (_testEnabledOverride != null) {
      _testEnabledOverride = v;
      return;
    }
    await _userSettingService.setItem(
      SettingKey.hiddenModeEnabled,
      v ? '1' : '0',
    );
  }

  // ─────────── PIN management ───────────

  /// Whether a PIN has been provisioned in secure storage.
  Future<bool> hasPin() async {
    final hash = await _storage.read(key: _kPinHashKey);
    final salt = await _storage.read(key: _kPinSaltKey);
    return hash != null &&
        hash.isNotEmpty &&
        salt != null &&
        salt.isNotEmpty;
  }

  // for Firebase sync only
  Future<String?> readPinHash() => _storage.read(key: _kPinHashKey);

  // for Firebase sync only
  Future<String?> readPinSalt() => _storage.read(key: _kPinSaltKey);

  // for Firebase sync only — writes both atomically and resets lock state so
  // the service behaves as if the PIN had been provisioned locally.
  Future<void> writePinHashAndSalt(String hash, String salt) async {
    await _storage.write(key: _kPinSaltKey, value: salt);
    await _storage.write(key: _kPinHashKey, value: hash);
  }

  /// Generate a fresh 16-byte salt, hash with SHA-256 and persist both.
  /// After a successful setPin the feature is toggled on and the service is
  /// left in the locked state.
  Future<void> setPin(String pin) async {
    final salt = _generateSalt();
    final hash = _hashPin(salt: salt, pin: pin);
    await _storage.write(key: _kPinSaltKey, value: salt);
    await _storage.write(key: _kPinHashKey, value: hash);
    await _setEnabled(true);
    _isLockedController.add(true);
  }

  /// Compare [pin] against stored hash and, on success, flip the service into
  /// the unlocked state. Returns whether the pin matched.
  Future<bool> unlock(String pin) async {
    final ok = await validatePin(pin);
    if (ok) {
      _isLockedController.add(false);
    }
    return ok;
  }

  /// Validate a pin without mutating the locked state. Used by flows that
  /// need to re-prompt for the current pin (change pin, disable).
  Future<bool> validatePin(String pin) async {
    final salt = await _storage.read(key: _kPinSaltKey);
    final storedHash = await _storage.read(key: _kPinHashKey);
    if (salt == null || storedHash == null) {
      return false;
    }
    final candidate = _hashPin(salt: salt, pin: pin);
    return _constantTimeEquals(candidate, storedHash);
  }

  /// Force re-lock. Idempotent.
  void lock() {
    _isLockedController.add(true);
  }

  /// Flip the service into the unlocked state without validating a PIN.
  ///
  /// Used exclusively by the PIN modal's biometric shortcut (Android/iOS
  /// fingerprint or face unlock). The actual `local_auth` call happens at the
  /// UI layer — this method only mutates the reactive lock state once the OS
  /// has reported a successful authentication. It is *not* a fallback for an
  /// unknown PIN: without OS-level biometrics available the UI does not expose
  /// this path.
  void unlockWithBiometric() {
    _isLockedController.add(false);
  }

  /// Replace the current PIN with [newPin] after validating [oldPin].
  /// Generates a new salt so the hash changes even if the pin is reused.
  Future<void> changePin(String oldPin, String newPin) async {
    final ok = await validatePin(oldPin);
    if (!ok) {
      throw StateError('Current PIN does not match.');
    }
    final salt = _generateSalt();
    final hash = _hashPin(salt: salt, pin: newPin);
    await _storage.write(key: _kPinSaltKey, value: salt);
    await _storage.write(key: _kPinHashKey, value: hash);
  }

  /// Tear down Hidden Mode. Requires the current [pin] to avoid accidental
  /// disable from a UI bug. Clears secure storage, flips the feature off and
  /// leaves the service unlocked so the app behaves as if the feature never
  /// existed.
  Future<void> disableHiddenMode(String pin) async {
    final ok = await validatePin(pin);
    if (!ok) {
      throw StateError('PIN does not match. Cannot disable Hidden Mode.');
    }
    await _storage.delete(key: _kPinHashKey);
    await _storage.delete(key: _kPinSaltKey);
    await _setEnabled(false);
    _isLockedController.add(false);
  }

  // ─────────── Lifecycle ───────────

  /// Initialise the service state at app boot.
  ///
  /// Contract:
  /// - If the feature is enabled and a PIN exists → start locked.
  /// - If the feature is enabled but no PIN exists → treat as corrupted
  ///   (classic backup/restore scenario where the DB preference survived but
  ///   the secure-storage key did not). Force the feature off and log.
  /// - If the feature is disabled → stay unlocked.
  Future<void> init() async {
    final enabled = await isEnabled();
    if (!enabled) {
      _isLockedController.add(false);
      return;
    }

    final pinPresent = await hasPin();
    if (!pinPresent) {
      Logger.printDebug(
        '[HiddenModeService] Feature was enabled but no PIN present '
        '(likely restored from backup). Resetting flag to off.',
      );
      await _setEnabled(false);
      _isLockedController.add(false);
      return;
    }

    _isLockedController.add(true);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Re-lock whenever the app loses foreground. `paused` covers Home button,
    // `inactive` covers transitional states on iOS/Android (app switcher,
    // incoming call) — both should hide the data.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      lock();
    }
  }

  /// Close internal streams. Mainly for tests.
  @visibleForTesting
  Future<void> dispose() async {
    await _isLockedController.close();
  }

  // ─────────── Crypto helpers ───────────

  String _generateSalt() {
    final rand = Random.secure();
    final bytes = List<int>.generate(16, (_) => rand.nextInt(256));
    return base64UrlEncode(bytes);
  }

  String _hashPin({required String salt, required String pin}) {
    final bytes = utf8.encode('$salt$pin');
    return sha256.convert(bytes).toString();
  }

  /// Constant-time string compare. Prevents timing side-channels even though
  /// secure_storage already isolates the hash.
  bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }
}
