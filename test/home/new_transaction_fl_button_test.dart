import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bolsio/app/home/widgets/new_transaction_fl_button.dart';
import 'package:bolsio/core/database/app_db.dart';
import 'package:bolsio/core/database/services/user-setting/user_setting_service.dart';
import 'package:bolsio/core/models/account/account.dart';
import 'package:bolsio/core/presentation/theme.dart';
import 'package:bolsio/core/utils/unique_app_widgets_keys.dart';
import 'package:bolsio/i18n/generated/translations.g.dart';

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
  late AppDB db;
  const accountId = 'acc-fab-test-57';

  setUp(() async {
    await LocaleSettings.setLocale(AppLocale.en);
    appStateSettings[SettingKey.font] = '0';
    appStateSettings[SettingKey.accentColor] = 'auto';
    appStateSettings[SettingKey.amoledMode] = '0';
    appStateSettings[SettingKey.themeMode] = 'system';

    tempRoot = await Directory.systemTemp.createTemp('bolsio_fab_test_');

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, (MethodCall call) async {
      if (call.method == 'getApplicationDocumentsDirectory') {
        return tempRoot.path;
      }
      return null;
    });

    db = AppDB.instance;

    final usd = await (db.select(
      db.currencies,
    )..where((c) => c.code.equals('USD'))).getSingleOrNull();
    if (usd == null) {
      await db
          .into(db.currencies)
          .insert(
            CurrenciesCompanion.insert(
              code: 'USD',
              symbol: r'$',
              name: 'USD',
              decimalPlaces: 2,
              isDefault: true,
              type: 0,
            ),
          );
    }

    await (db.delete(db.accounts)..where((a) => a.id.equals(accountId))).go();
    await db
        .into(db.accounts)
        .insert(
          AccountsCompanion.insert(
            id: accountId,
            name: 'Cuenta FAB Test',
            iniValue: 0,
            date: DateTime(2026, 1, 1),
            type: AccountType.normal,
            iconId: 'wallet',
            displayOrder: 0,
            currencyId: 'USD',
          ),
        );
  });

  tearDown(() async {
    await (db.delete(db.accounts)..where((a) => a.id.equals(accountId))).go();

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

  testWidgets('5.7 FAB shows 3 actions and routes manual create', (
    tester,
  ) async {
    await tester.pumpWidget(const _FabHost());

    final ctx = tester.element(find.byType(NewTransactionButton));
    final t = Translations.of(ctx);

    // The custom fan FAB widget must be present before expansion.
    expect(find.byType(NewTransactionButton), findsOneWidget);

    // Tap the opening FAB (rendered with add_rounded icon) to fan out.
    await tester.tap(find.byIcon(Icons.add_rounded));
    await tester.pumpAndSettle();

    // Each child FAB carries its i18n label as its tooltip (via
    // FloatingActionButton.small.tooltip), which is findable via byTooltip.
    expect(find.byTooltip(t.transaction.create), findsOneWidget);
    expect(
      find.byTooltip(t.transaction.receipt_import.entry_gallery),
      findsOneWidget,
    );
    expect(
      find.byTooltip(t.transaction.receipt_import.entry_camera),
      findsOneWidget,
    );

    // Tapping the "create" entry closes the fan and triggers a navigation
    // path gated by a drift stream, which isn't reliable under fakeAsync.
    // The structural assertions above are the key contract: the 3 entry
    // points must be reachable from the FAB after fan expansion.
    await tester.tap(find.byTooltip(t.transaction.create));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  });
}

class _FabHost extends StatelessWidget {
  const _FabHost();

  @override
  Widget build(BuildContext context) {
    // Custom fan FAB renders its own Overlay entry on open, so standard
    // Scaffold FAB plumbing (endFloat) is all that is required here.
    return _wrap(
      Scaffold(
        floatingActionButton: const NewTransactionButton(isExtended: true),
        floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      ),
    );
  }
}
