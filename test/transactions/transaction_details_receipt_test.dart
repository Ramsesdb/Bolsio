import 'dart:io';

import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:wallex/app/transactions/transaction_details.page.dart';
import 'package:wallex/core/database/app_db.dart';
import 'package:wallex/core/database/services/transaction/transaction_service.dart';
import 'package:wallex/core/database/services/user-setting/user_setting_service.dart';
import 'package:wallex/core/models/account/account.dart';
import 'package:wallex/core/models/category/category.dart';
import 'package:wallex/core/models/transaction/transaction_type.enum.dart';
import 'package:wallex/core/presentation/theme.dart';
import 'package:wallex/core/services/attachments/attachment_model.dart';
import 'package:wallex/core/services/attachments/attachments_service.dart';
import 'package:wallex/i18n/generated/translations.g.dart';

Widget _wrap(Widget child) {
  return TranslationProvider(
    child: Builder(
      builder: (context) => MaterialApp(
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
  const accountId = 'acc-tdr-58';
  const categoryId = 'cat-tdr-58';
  const txId = 'tx-tdr-58';

  setUp(() async {
    await LocaleSettings.setLocale(AppLocale.en);
    appStateSettings[SettingKey.font] = '0';
    appStateSettings[SettingKey.accentColor] = 'auto';
    appStateSettings[SettingKey.amoledMode] = '0';
    appStateSettings[SettingKey.themeMode] = 'system';

    tempRoot = await Directory.systemTemp.createTemp('wallex_tdr_test_');

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, (MethodCall call) async {
      if (call.method == 'getApplicationDocumentsDirectory') {
        return tempRoot.path;
      }
      return tempRoot.path;
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

    await (db.delete(db.transactions)..where((t) => t.id.equals(txId))).go();
    await (db.delete(db.accounts)..where((a) => a.id.equals(accountId))).go();
    await (db.delete(db.categories)..where((c) => c.id.equals(categoryId))).go();

    await db
        .into(db.accounts)
        .insert(
          AccountsCompanion.insert(
            id: accountId,
            name: 'Cuenta Receipt Test',
            iniValue: 0,
            date: DateTime(2026, 1, 1),
            type: AccountType.normal,
            iconId: 'wallet',
            displayOrder: 0,
            currencyId: 'USD',
          ),
        );

    await db
        .into(db.categories)
        .insert(
          CategoriesCompanion.insert(
            id: categoryId,
            name: 'Categoria Receipt Test',
            iconId: 'food',
            displayOrder: 0,
            color: const drift.Value('FF8C00'),
            type: const drift.Value(CategoryType.E),
          ),
        );

    await db
        .into(db.transactions)
        .insert(
          TransactionsCompanion.insert(
            id: txId,
            date: DateTime(2026, 4, 17, 12, 0),
            accountID: accountId,
            value: 25,
            type: TransactionType.expense,
            categoryID: const drift.Value(categoryId),
            createdAt: drift.Value(DateTime.now()),
          ),
        );
  });

  tearDown(() async {
    await AttachmentsService.instance.deleteByOwner(
      ownerType: AttachmentOwnerType.transaction,
      ownerId: txId,
    );
    await (db.delete(db.transactions)..where((t) => t.id.equals(txId))).go();
    await (db.delete(db.accounts)..where((a) => a.id.equals(accountId))).go();
    await (db.delete(db.categories)..where((c) => c.id.equals(categoryId))).go();

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, null);

    // AppDB.instance is a static singleton backed by a drift background
    // connection, so we cannot close it here without breaking subsequent tests.
    // On Windows, the sqlite file handle inside tempRoot may still be live when
    // we try to remove the directory, which raises PathAccessException and,
    // without this guard, caused scenario 5.8 to hang until the 10 min timeout.
    // Retry a few times with a short backoff, then give up quietly: the OS
    // temp dir is cleaned up eventually by the system regardless.
    if (await tempRoot.exists()) {
      for (var attempt = 1; attempt <= 5; attempt++) {
        try {
          await tempRoot.delete(recursive: true);
          break;
        } on FileSystemException {
          if (attempt == 5 || !Platform.isWindows) break;
          await Future<void>.delayed(Duration(milliseconds: 50 * attempt));
        }
      }
    }
  });

  testWidgets('5.8 receipt chip appears only when receipt attachment exists', (
    tester,
  ) async {
    final tx = await TransactionService.instance.getTransactionById(txId).first;
    expect(tx, isNotNull);

    await tester.pumpWidget(
      _wrap(
        TransactionDetailsPage(transaction: tx!, heroTag: null),
      ),
    );
    await tester.pumpAndSettle();

    final ctx = tester.element(find.byType(TransactionDetailsPage));
    final t = Translations.of(ctx);

    expect(find.text(t.transaction.view_receipt), findsNothing);

    final source = File('${tempRoot.path}/receipt_source.png')
      ..writeAsBytesSync(img.encodePng(img.Image(width: 80, height: 80)));

    await AttachmentsService.instance.attach(
      ownerType: AttachmentOwnerType.transaction,
      ownerId: txId,
      sourceFile: source,
      role: 'receipt',
    );

    await tester.pumpWidget(
      _wrap(
        TransactionDetailsPage(transaction: tx, heroTag: null),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(t.transaction.view_receipt), findsOneWidget);
  });
}
