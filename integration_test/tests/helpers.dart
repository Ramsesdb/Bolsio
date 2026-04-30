import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kilatex/app/home/dashboard.page.dart';
import 'package:kilatex/app/onboarding/onboarding.dart';
import 'package:kilatex/app/settings/more_actions.page.dart';
import 'package:kilatex/core/database/services/app-data/app_data_service.dart';
import 'package:kilatex/core/database/services/user-setting/user_setting_service.dart';
import 'package:kilatex/i18n/generated/translations.g.dart';
import 'package:kilatex/main.dart';

Future<void> setupMonekin() async {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  await UserSettingService.instance.initializeGlobalStateMap();
  await AppDataService.instance.initializeGlobalStateMap();

  await LocaleSettings.setLocale(AppLocale.en, listenToDeviceLocale: true);
  await UserSettingService.instance.setItem(
    SettingKey.appLanguage,
    AppLocale.en.languageCode,
  );
}

Future<void> startMonekin(WidgetTester tester) async {
  await tester.pumpWidget(const WallexAppEntryPoint());
  await tester.pumpAndSettle();
  expect(find.byType(WallexAppEntryPoint), findsOneWidget);

  // Legacy Monekin onboarding button — no longer present in the v3 onboarding
  // flow. The INTRO i18n namespace was removed 2026-04-24 (onboarding-v2-auto-import
  // Fase 6). This test helper is broken against v3; left as a literal so the file
  // compiles until the integration tests are rewired for v3 slides.
  await tester.tap(find.text('Start session offline'));

  await tester.pumpAndSettle();
  expect(find.byType(OnboardingPage), findsOneWidget);

  await tester.tap(find.byIcon(Icons.arrow_forward_rounded));
  await tester.pumpAndSettle();
  await tester.tap(find.byIcon(Icons.arrow_forward_rounded));
  await tester.pumpAndSettle();
  await tester.tap(find.byIcon(Icons.arrow_forward_rounded));

  await tester.pumpAndSettle();
  expect(find.byType(DashboardPage), findsOneWidget);
}

Future<void> openMorePage(WidgetTester tester) async {
  await tester.tap(find.text(t.more.title));
  await tester.pumpAndSettle();

  expect(find.byType(MoreActionsPage), findsOneWidget);
}
