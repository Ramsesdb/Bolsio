import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nitido/app/settings/pages/backup/backup_settings.page.dart';
import 'package:nitido/core/database/app_db.dart';
import 'package:nitido/core/database/services/user-setting/user_setting_service.dart';
import 'package:nitido/core/presentation/theme.dart';
import 'package:nitido/core/utils/unique_app_widgets_keys.dart';
import 'package:nitido/i18n/generated/translations.g.dart';

Widget _wrap(Widget child) {
  return TranslationProvider(
    child: Builder(
      builder: (context) => MaterialApp(
        navigatorKey: navigatorKey,
        scaffoldMessengerKey: snackbarKey,
        theme: getThemeData(
          context,
          isDark: false,
          amoledMode: false,
          lightDynamic: null,
          darkDynamic: null,
          accentColor: 'auto',
        ),
        locale: TranslationProvider.of(context).flutterLocale,
        supportedLocales: AppLocaleUtils.supportedLocales,
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: child,
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');

  late Directory tempRoot;

  setUp(() async {
    await LocaleSettings.setLocale(AppLocale.en);
    appStateSettings[SettingKey.font] = '0';
    appStateSettings[SettingKey.accentColor] = 'auto';
    appStateSettings[SettingKey.amoledMode] = '0';
    appStateSettings[SettingKey.themeMode] = 'system';

    tempRoot = await Directory.systemTemp.createTemp('nitido_backup_test_');

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, (MethodCall call) async {
      if (call.method == 'getApplicationDocumentsDirectory') {
        return tempRoot.path;
      }
      return null;
    });

    final dbPath = await AppDB.instance.databasePath;
    final dbFile = File(dbPath);
    if (!dbFile.existsSync()) {
      dbFile.createSync(recursive: true);
    }
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, null);

    if (await tempRoot.exists()) {
      try {
        await tempRoot.delete(recursive: true);
      } on FileSystemException {
        // Ignore Windows file-lock races from shared DB handles in tests.
      }
    }
  });

  testWidgets('5.10 settings cleanup action runs and reports removed count', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(const BackupSettingsPage()));
    await tester.pumpAndSettle();

    final tileFinder = find.text('Limpieza de adjuntos huerfanos');
    await tester.scrollUntilVisible(tileFinder, 300);
    await tester.tap(tileFinder);
    await tester.pumpAndSettle();

    expect(find.textContaining('Limpieza completada:'), findsOneWidget);
  });
}
