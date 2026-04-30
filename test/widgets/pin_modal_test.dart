import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bolsio/app/settings/widgets/pin_modal.dart';
import 'package:bolsio/core/database/services/user-setting/hidden_mode_service.dart';
import 'package:bolsio/core/database/services/user-setting/user_setting_service.dart';
import 'package:bolsio/i18n/generated/translations.g.dart';

/// Widget tests for the PIN modal. We pump [PinModal] directly inside a
/// `Scaffold` (skipping the `showModalBottomSheet` wrapper) and inject a
/// [HiddenModeService.forTesting] instance so we don't have to boot Drift
/// or real secure-storage plugin channels.
Widget _wrap(Widget child) {
  return TranslationProvider(
    child: Builder(
      builder: (context) => MaterialApp(
        locale: TranslationProvider.of(context).flutterLocale,
        supportedLocales: AppLocaleUtils.supportedLocales,
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: Scaffold(body: child),
      ),
    ),
  );
}

Future<void> _tapDigit(WidgetTester tester, String digit) async {
  await tester.tap(find.byKey(ValueKey('pin-key-$digit')));
  await tester.pump();
}

Future<void> _tapPin(WidgetTester tester, String pin) async {
  for (final digit in pin.split('')) {
    await _tapDigit(tester, digit);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late HiddenModeService service;

  setUp(() async {
    await LocaleSettings.setLocale(AppLocale.en);
    appStateSettings.remove(SettingKey.hiddenModeEnabled);
    FlutterSecureStorage.setMockInitialValues({});
    service = HiddenModeService.forTesting(
      storage: const FlutterSecureStorage(),
      initialEnabled: false,
    );
  });

  tearDown(() async {
    await service.dispose();
  });

  group('PinModal — setup mode', () {
    testWidgets(
      'entering 6 digits advances from enter step to confirm step',
      (tester) async {
        await tester.pumpWidget(
          _wrap(
            PinModal(
              mode: PinModalMode.setup,
              serviceOverride: service,
            ),
          ),
        );

        // Step 1 title.
        expect(find.text('Create your PIN'), findsOneWidget);
        expect(find.text('Confirm your PIN'), findsNothing);

        await _tapPin(tester, '123456');
        await tester.pumpAndSettle();

        // Step 2 reached. The confirmation title is now visible.
        expect(find.text('Confirm your PIN'), findsOneWidget);
        expect(find.text('Create your PIN'), findsNothing);
      },
    );

    testWidgets(
      'mismatched confirmation surfaces error and sends user back to step 1',
      (tester) async {
        await tester.pumpWidget(
          _wrap(
            PinModal(
              mode: PinModalMode.setup,
              serviceOverride: service,
            ),
          ),
        );

        await _tapPin(tester, '111111');
        await tester.pumpAndSettle();
        expect(find.text('Confirm your PIN'), findsOneWidget);

        await _tapPin(tester, '222222');
        await tester.pumpAndSettle();

        expect(find.text('Create your PIN'), findsOneWidget);
        expect(find.text('PINs do not match'), findsOneWidget);
      },
    );
  });

  group('PinModal — unlock mode', () {
    testWidgets(
      'wrong PIN shows "Incorrect PIN" error and clears the dots',
      (tester) async {
        await service.setPin('123456');

        await tester.pumpWidget(
          _wrap(
            PinModal(
              mode: PinModalMode.unlock,
              serviceOverride: service,
            ),
          ),
        );

        await _tapPin(tester, '000000');
        await tester.pumpAndSettle();

        expect(find.text('Incorrect PIN'), findsOneWidget);

        // Buffer should be cleared after a failed attempt.
        final state = tester.state<PinModalState>(find.byType(PinModal));
        expect(state.currentBuffer, isEmpty);
      },
    );

    testWidgets(
      '5 wrong attempts disables the keypad (cooldown kicks in)',
      (tester) async {
        await service.setPin('123456');

        await tester.pumpWidget(
          _wrap(
            PinModal(
              mode: PinModalMode.unlock,
              serviceOverride: service,
            ),
          ),
        );

        for (var i = 0; i < kMaxAttempts; i++) {
          await _tapPin(tester, '000000');
          await tester.pumpAndSettle();
        }

        final state = tester.state<PinModalState>(find.byType(PinModal));
        expect(state.failedAttempts, kMaxAttempts);
        expect(state.keypadDisabled, isTrue);
        expect(state.cooldownSeconds, isNotNull);

        // Subsequent digit taps must not advance the buffer while disabled.
        // The keypad wraps its children in IgnorePointer, so the tap won't
        // hit any widget — pass warnIfMissed:false to keep the test log
        // clean.
        await tester.tap(
          find.byKey(const ValueKey('pin-key-1')),
          warnIfMissed: false,
        );
        await tester.pumpAndSettle();
        expect(state.currentBuffer, isEmpty);

        // Let the cooldown timer keep running so the test framework doesn't
        // complain about a pending Timer — but we stop it by disposing the
        // widget on teardown.
      },
    );
  });

  group('PinModal — keypad behavior', () {
    testWidgets(
      'backspace removes the last entered digit',
      (tester) async {
        await tester.pumpWidget(
          _wrap(
            PinModal(
              mode: PinModalMode.setup,
              serviceOverride: service,
            ),
          ),
        );

        await _tapPin(tester, '1234');
        final state = tester.state<PinModalState>(find.byType(PinModal));
        expect(state.currentBuffer, '1234');

        await tester.tap(find.byKey(const ValueKey('pin-backspace')));
        await tester.pump();
        expect(state.currentBuffer, '123');

        await tester.tap(find.byKey(const ValueKey('pin-backspace')));
        await tester.pump();
        expect(state.currentBuffer, '12');
      },
    );
  });

  group('PinModal — biometric availability', () {
    testWidgets(
      'biometric button is hidden in setup mode (biometry is unlock-only)',
      (tester) async {
        await tester.pumpWidget(
          _wrap(
            PinModal(
              mode: PinModalMode.setup,
              serviceOverride: service,
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const ValueKey('pin-biometric')), findsNothing);
      },
    );

    testWidgets(
      'biometric button is hidden in unlock mode when the platform channel '
      'is unavailable (no mock registered → LocalAuthentication throws)',
      (tester) async {
        // No MethodChannel mock installed for `plugins.flutter.io/local_auth` —
        // the call to `isDeviceSupported()` throws `MissingPluginException`,
        // which the modal swallows, leaving `_biometricAvailable = false`.
        await service.setPin('123456');

        await tester.pumpWidget(
          _wrap(
            PinModal(
              mode: PinModalMode.unlock,
              serviceOverride: service,
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const ValueKey('pin-biometric')), findsNothing);
      },
    );

    testWidgets(
      'biometric button is rendered in unlock mode when the platform reports '
      'both isDeviceSupported and canCheckBiometrics as true',
      (tester) async {
        // Register a mock for the local_auth platform channel that reports
        // biometrics as available, then pump the modal and confirm the
        // fingerprint slot appears.
        const channel = MethodChannel('plugins.flutter.io/local_auth');
        TestDefaultBinaryMessengerBinding
            .instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
          switch (call.method) {
            case 'isDeviceSupported':
            case 'deviceSupportsBiometrics':
              return true;
            case 'getEnrolledBiometrics':
              return <String>['fingerprint'];
            case 'getAvailableBiometrics':
              return <String>['fingerprint'];
            default:
              return null;
          }
        });
        addTearDown(() {
          TestDefaultBinaryMessengerBinding
              .instance.defaultBinaryMessenger
              .setMockMethodCallHandler(channel, null);
        });

        await service.setPin('123456');

        await tester.pumpWidget(
          _wrap(
            PinModal(
              mode: PinModalMode.unlock,
              serviceOverride: service,
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const ValueKey('pin-biometric')), findsOneWidget);
      },
    );
  });
}
