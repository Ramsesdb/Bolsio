import 'dart:io';

import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:nitido/app/transactions/receipt_import/receipt_review_page.dart';
import 'package:nitido/core/database/app_db.dart';
import 'package:nitido/core/database/services/user-setting/user_setting_service.dart';
import 'package:nitido/core/models/account/account.dart';
import 'package:nitido/core/models/auto_import/capture_channel.dart';
import 'package:nitido/core/models/auto_import/transaction_proposal.dart';
import 'package:nitido/core/models/category/category.dart';
import 'package:nitido/core/models/transaction/transaction_type.enum.dart';
import 'package:nitido/core/presentation/theme.dart';
import 'package:nitido/core/services/attachments/attachment_model.dart';
import 'package:nitido/core/services/attachments/attachments_service.dart';
import 'package:nitido/core/services/receipt_ocr/receipt_extractor_service.dart';
import 'package:nitido/core/services/receipt_ocr/receipt_image_service.dart';
import 'package:nitido/core/utils/unique_app_widgets_keys.dart';
import 'package:nitido/i18n/generated/translations.g.dart';
import 'package:flutter/services.dart';

class _FakeReceiptImageService extends ReceiptImageService {
  _FakeReceiptImageService(this.filePath);

  final String filePath;

  @override
  Future<File?> pickAndCompress({required ImageSource source}) async {
    return File(filePath);
  }
}

class _FakeReceiptExtractorService extends ReceiptExtractorService {
  _FakeReceiptExtractorService(this.result);

  final ExtractionResult result;

  @override
  Future<ExtractionResult> extractFromImage(
    File imageFile, {
    String sender = 'com.bancodevenezuela.bdvdigital',
    String? accountId,
    String? preferredCurrency,
  }) async {
    return result;
  }
}

Widget _wrapForFlow(Widget child) {
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

Future<void> _ensureCurrency(AppDB db, String code) async {
  final existing = await (db.select(
    db.currencies,
  )..where((c) => c.code.equals(code))).getSingleOrNull();

  if (existing != null) return;

  await db
      .into(db.currencies)
      .insert(
        CurrenciesCompanion.insert(
          code: code,
          symbol: r'$',
          name: code,
          decimalPlaces: 2,
          isDefault: false,
          type: 0,
        ),
      );
}

Future<void> _upsertAccount(
  AppDB db,
  String accountId,
  String currencyId,
) async {
  await (db.delete(db.accounts)..where((a) => a.id.equals(accountId))).go();

  await db
      .into(db.accounts)
      .insert(
        AccountsCompanion.insert(
          id: accountId,
          name: 'Receipt Flow Test Account',
          iniValue: 0,
          date: DateTime(2026, 1, 1),
          type: AccountType.normal,
          iconId: 'wallet',
          displayOrder: 0,
          currencyId: currencyId,
        ),
      );
}

Future<void> _upsertCategory(AppDB db, String categoryId) async {
  await (db.delete(db.categories)..where((c) => c.id.equals(categoryId))).go();

  await db
      .into(db.categories)
      .insert(
        CategoriesCompanion.insert(
          id: categoryId,
          name: 'Receipt Flow Category',
          iconId: 'food',
          displayOrder: 0,
          color: const drift.Value('FF8C00'),
          type: const drift.Value(CategoryType.E),
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

    tempRoot = await Directory.systemTemp.createTemp('nitido_flow_4_13_');

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, (MethodCall call) async {
          if (call.method == 'getApplicationDocumentsDirectory') {
            return tempRoot.path;
          }
          if (call.method == 'getTemporaryDirectory') {
            return tempRoot.path;
          }
          return tempRoot.path;
        });
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, null);

    if (await tempRoot.exists()) {
      try {
        await tempRoot.delete(recursive: true);
      } on FileSystemException {
        // Ignore Windows file locks from open DB handles in widget tests.
      }
    }
  });

  testWidgets(
    '4.13 mocked pick -> review -> save persists transaction and attachment',
    (tester) async {
      final db = AppDB.instance;
      const accountId = 'acc-receipt-flow-413';
      const categoryId = 'cat-receipt-flow-413';
      const marker = 'receipt-flow-413-marker';

      await tester.runAsync(() async {
        await _ensureCurrency(db, 'USD');
        await _upsertAccount(db, accountId, 'USD');
        await _upsertCategory(db, categoryId);
      });

      final raster = img.Image(width: 120, height: 120);
      for (var y = 0; y < 120; y++) {
        for (var x = 0; x < 120; x++) {
          raster.setPixelRgba(x, y, 180, 120, 90, 255);
        }
      }
      final pickedFile = File('${tempRoot.path}/picked_413.jpg')
        ..writeAsBytesSync(img.encodeJpg(raster, quality: 90));

      final proposal = TransactionProposal.newProposal(
        amount: 42.5,
        currencyId: 'USD',
        date: DateTime(2026, 4, 17, 10, 30),
        type: TransactionType.expense,
        counterpartyName: 'Mocked Receipt Merchant',
        bankRef: 'FLOW-413-REF',
        rawText: marker,
        channel: CaptureChannel.receiptImage,
        sender: 'receipt-flow-test',
        confidence: 0.95,
        accountId: accountId,
        proposedCategoryId: categoryId,
      );

      final extraction = ExtractionResult.success(
        proposal: proposal,
        ocrText: marker,
        currencyAmbiguous: false,
        extractedCurrencyCode: 'USD',
      );

      final imageService = _FakeReceiptImageService(pickedFile.path);
      final extractor = _FakeReceiptExtractorService(extraction);

      final picked = await tester.runAsync(
        () => imageService.pickAndCompress(source: ImageSource.gallery),
      );
      expect(picked, isNotNull);
      final pickedFileForFlow = picked!;

      final extracted = await tester.runAsync(
        () => extractor.extractFromImage(pickedFileForFlow),
      );
      expect(extracted, isNotNull);
      final extractedResult = extracted!;
      expect(extractedResult.isSuccess, isTrue);

      TransactionProposal? reviewedProposal;

      await tester.pumpWidget(
        _wrapForFlow(
          ReceiptReviewPage(
            pendingAttachmentPath: pickedFileForFlow.path,
            extraction: extractedResult,
            showPreview: false,
            onContinue: (updated) async {
              reviewedProposal = updated;
            },
          ),
        ),
      );

      expect(find.byType(ReceiptReviewPage), findsOneWidget);
      await tester.tap(find.byIcon(Icons.arrow_forward));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(reviewedProposal, isNotNull);

      final txId = 'tx-flow-413-${DateTime.now().microsecondsSinceEpoch}';

      await tester.runAsync(() async {
        await db
            .into(db.transactions)
            .insert(
              TransactionsCompanion.insert(
                id: txId,
                date: reviewedProposal!.date,
                accountID: accountId,
                value: -reviewedProposal!.amount.abs(),
                type: reviewedProposal!.type,
                categoryID: drift.Value(categoryId),
                notes: drift.Value(marker),
                title: drift.Value(reviewedProposal!.counterpartyName),
                createdAt: drift.Value(DateTime.now()),
              ),
            );

        await AttachmentsService.instance.attach(
          ownerType: AttachmentOwnerType.transaction,
          ownerId: txId,
          sourceFile: pickedFileForFlow,
          role: 'receipt',
        );

        if (pickedFileForFlow.existsSync()) {
          pickedFileForFlow.deleteSync();
        }
      });

      await tester.runAsync(() async {
        final txRows = await (db.select(
          db.transactions,
        )..where((t) => t.notes.equals(marker))).get();
        expect(txRows.length, 1);

        final tx = txRows.first;
        expect(tx.accountID, accountId);
        expect(tx.type, TransactionType.expense);

        final attachments = await AttachmentsService.instance.listByOwner(
          ownerType: AttachmentOwnerType.transaction,
          ownerId: tx.id,
        );
        expect(attachments.length, 1);
        expect(attachments.first.role, 'receipt');

        final persisted = await AttachmentsService.instance.resolveFile(
          attachments.first,
        );
        expect(persisted.existsSync(), isTrue);
        expect(pickedFile.existsSync(), isFalse);

        await AttachmentsService.instance.deleteByOwner(
          ownerType: AttachmentOwnerType.transaction,
          ownerId: tx.id,
        );
        await (db.delete(
          db.transactions,
        )..where((tbl) => tbl.id.equals(tx.id))).go();
      });
    },
  );
}
