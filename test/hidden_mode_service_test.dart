import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nitido/core/database/services/user-setting/hidden_mode_service.dart';
import 'package:nitido/core/database/services/user-setting/user_setting_service.dart';

/// Unit tests for the core PIN / crypto behavior of [HiddenModeService].
///
/// These tests intentionally avoid touching the DB-backed feature flag
/// (hiddenModeEnabled). That path is covered by the settings-page widget
/// tests in T3, and exercising it here would require booting a full
/// in-memory Drift instance, which T1's scope explicitly excludes.
///
/// To keep the PIN-management asserts hermetic we drive the service with the
/// mock secure-storage plugin (`FlutterSecureStorage.setMockInitialValues`),
/// which is the same pattern used by `binance_credentials_store_test.dart`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late HiddenModeService service;

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    // Reset the in-memory setting cache so `isEnabled()` doesn't leak between
    // tests when they do touch the feature flag.
    appStateSettings.remove(SettingKey.hiddenModeEnabled);
    service = HiddenModeService.forTesting(
      storage: const FlutterSecureStorage(),
      // Route the feature flag through an in-memory override so the tests
      // don't need to boot the real Drift DB (which pulls path_provider).
      initialEnabled: false,
    );
  });

  tearDown(() async {
    await service.dispose();
  });

  group('HiddenModeService — PIN lifecycle', () {
    test('setPin persists a PIN and hasPin becomes true', () async {
      expect(await service.hasPin(), isFalse);
      await service.setPin('123456');
      expect(await service.hasPin(), isTrue);
    });

    test('two setPin calls with the same PIN produce different stored hashes '
        '(unique salt per call)', () async {
      final storage = const FlutterSecureStorage();

      await service.setPin('123456');
      final firstHash = await storage.read(key: 'hidden_mode_pin_hash');
      final firstSalt = await storage.read(key: 'hidden_mode_pin_salt');

      await service.setPin('123456');
      final secondHash = await storage.read(key: 'hidden_mode_pin_hash');
      final secondSalt = await storage.read(key: 'hidden_mode_pin_salt');

      expect(firstHash, isNotNull);
      expect(secondHash, isNotNull);
      expect(firstSalt, isNotNull);
      expect(secondSalt, isNotNull);
      expect(firstSalt, isNot(equals(secondSalt)));
      expect(firstHash, isNot(equals(secondHash)));
    });

    test('unlock returns true with the correct PIN', () async {
      await service.setPin('123456');
      expect(await service.unlock('123456'), isTrue);
    });

    test('unlock returns false with a wrong PIN', () async {
      await service.setPin('123456');
      expect(await service.unlock('999999'), isFalse);
    });

    test('unlock returns false when no PIN is provisioned', () async {
      expect(await service.unlock('anything'), isFalse);
    });

    test('validatePin does not mutate locked state', () async {
      await service.setPin('123456');
      // setPin leaves the service locked.
      expect(service.isLocked, isTrue);
      expect(await service.validatePin('123456'), isTrue);
      expect(service.isLocked, isTrue);
    });

    test('changePin requires the old PIN and replaces the hash', () async {
      await service.setPin('111111');
      expect(
        () => service.changePin('999999', '222222'),
        throwsStateError,
      );

      await service.changePin('111111', '222222');
      expect(await service.unlock('111111'), isFalse);
      expect(await service.unlock('222222'), isTrue);
    });
  });

  group('HiddenModeService — locked stream', () {
    test('lock() emits true on isLockedStream', () async {
      // setPin primes us into the locked state so switching to false first
      // gives us an observable transition.
      await service.setPin('123456');
      expect(await service.unlock('123456'), isTrue);
      expect(service.isLocked, isFalse);

      final future = service.isLockedStream
          .firstWhere((locked) => locked == true);
      service.lock();
      expect(await future, isTrue);
      expect(service.isLocked, isTrue);
    });

    test('unlock transitions the stream from locked → unlocked', () async {
      await service.setPin('123456');
      expect(service.isLocked, isTrue);

      final future = service.isLockedStream
          .firstWhere((locked) => locked == false);
      expect(await service.unlock('123456'), isTrue);
      expect(await future, isFalse);
    });

    test('unlockWithBiometric unlocks without validating the PIN', () async {
      await service.setPin('123456');
      expect(service.isLocked, isTrue);

      service.unlockWithBiometric();
      expect(service.isLocked, isFalse);
    });
  });

  group('HiddenModeService — disableHiddenMode', () {
    test('clears secure storage and requires the current PIN', () async {
      await service.setPin('123456');
      expect(await service.hasPin(), isTrue);

      expect(
        () => service.disableHiddenMode('000000'),
        throwsStateError,
      );
      expect(await service.hasPin(), isTrue);

      await service.disableHiddenMode('123456');
      expect(await service.hasPin(), isFalse);
      // Service should be left in the unlocked state so dependent streams
      // behave as if the feature never existed.
      expect(service.isLocked, isFalse);
      expect(await service.isEnabled(), isFalse);
    });

    test('setPin flips the feature flag on', () async {
      expect(await service.isEnabled(), isFalse);
      await service.setPin('123456');
      expect(await service.isEnabled(), isTrue);
    });
  });
}
