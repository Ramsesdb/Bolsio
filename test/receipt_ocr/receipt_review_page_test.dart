import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:nitido/app/transactions/form/transaction_form.page.dart';
import 'package:nitido/app/transactions/receipt_import/receipt_review_page.dart';
import 'package:nitido/core/database/services/user-setting/user_setting_service.dart';
import 'package:nitido/core/models/auto_import/capture_channel.dart';
import 'package:nitido/core/models/auto_import/transaction_proposal.dart';
import 'package:nitido/core/models/transaction/transaction_type.enum.dart';
import 'package:nitido/core/presentation/theme.dart';
import 'package:nitido/core/services/receipt_ocr/receipt_extractor_service.dart';
import 'package:nitido/i18n/generated/translations.g.dart';

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

TransactionProposal _proposal({
  double amount = 10,
  String? counterparty = 'Inicial',
  String? bankRef = '001',
}) {
  return TransactionProposal.newProposal(
    amount: amount,
    currencyId: 'USD',
    date: DateTime(2026, 4, 17, 10, 24),
    type: TransactionType.expense,
    counterpartyName: counterparty,
    bankRef: bankRef,
    rawText: 'raw ocr',
    channel: CaptureChannel.receiptImage,
    sender: 'test',
    confidence: 0.8,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempRoot;

  Future<File> makeImage(String name) async {
    final raster = img.Image(width: 40, height: 40);
    for (var y = 0; y < 40; y++) {
      for (var x = 0; x < 40; x++) {
        raster.setPixelRgba(x, y, 120, 140, 180, 255);
      }
    }

    final file = File('${tempRoot.path}/$name');
    file.writeAsBytesSync(img.encodeJpg(raster, quality: 90));
    return file;
  }

  setUp(() async {
    await LocaleSettings.setLocale(AppLocale.en);
    appStateSettings[SettingKey.font] = '0';
    appStateSettings[SettingKey.accentColor] = 'auto';
    appStateSettings[SettingKey.amoledMode] = '0';
    appStateSettings[SettingKey.themeMode] = 'system';
    tempRoot = await Directory.systemTemp.createTemp(
      'nitido_review_page_test_',
    );
  });

  tearDown(() async {
    if (await tempRoot.exists()) {
      await tempRoot.delete(recursive: true);
    }
  });

  testWidgets('4.9 shows ambiguous currency badge', (tester) async {
    final file = await makeImage('receipt.jpg');

    final extraction = ExtractionResult.success(
      proposal: _proposal(),
      ocrText: 'ocr',
      currencyAmbiguous: true,
      extractedCurrencyCode: null,
    );

    await tester.pumpWidget(
      _wrap(
        ReceiptReviewPage(
          pendingAttachmentPath: file.path,
          extraction: extraction,
          showPreview: false,
          onDiscard: () async {},
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('?'), findsOneWidget);
  });

  testWidgets('4.10 cancel removes pending temp file', (tester) async {
    final file = File('${tempRoot.path}/receipt_cancel.tmp')
      ..writeAsStringSync('temp-receipt');

    final extraction = ExtractionResult.success(
      proposal: _proposal(),
      ocrText: 'ocr',
      currencyAmbiguous: false,
      extractedCurrencyCode: 'USD',
    );

    await tester.pumpWidget(
      _wrap(
        ReceiptReviewPage(
          pendingAttachmentPath: file.path,
          extraction: extraction,
          showPreview: false,
          onDiscard: () async {},
        ),
      ),
    );
    await tester.pump();

    expect(file.existsSync(), isTrue);
    await tester.tap(find.text('Cancel'));
    await tester.pump(const Duration(milliseconds: 250));

    expect(file.existsSync(), isFalse);
  });

  testWidgets('4.12 edited review fields are forwarded to form', (
    tester,
  ) async {
    final file = await makeImage('receipt_forward.jpg');

    final extraction = ExtractionResult.success(
      proposal: _proposal(amount: 10, counterparty: 'Original'),
      ocrText: 'ocr',
      currencyAmbiguous: false,
      extractedCurrencyCode: 'USD',
    );

    TransactionProposal? captured;

    await tester.pumpWidget(
      _wrap(
        ReceiptReviewPage(
          pendingAttachmentPath: file.path,
          extraction: extraction,
          showPreview: false,
          onContinue: (TransactionProposal updated) async {
            captured = updated;
          },
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    await tester.enterText(find.byType(TextField).first, '77.50');
    await tester.tap(find.text('Continue'));
    await tester.pump();

    expect(captured, isNotNull);
    expect(captured!.amount, 77.5);
    expect(find.byType(TransactionFormPage), findsNothing);
  });

  testWidgets('5.9 duplicate warning is shown and continue remains enabled', (
    tester,
  ) async {
    final file = await makeImage('receipt_duplicate.jpg');

    final extraction = ExtractionResult.success(
      proposal: _proposal(amount: 50, counterparty: 'Duplicado Test'),
      ocrText: 'ocr',
      currencyAmbiguous: false,
      extractedCurrencyCode: 'USD',
    );

    TransactionProposal? captured;

    await tester.pumpWidget(
      _wrap(
        ReceiptReviewPage(
          pendingAttachmentPath: file.path,
          extraction: extraction,
          showPreview: false,
          showDuplicateWarning: true,
          onContinue: (updated) async {
            captured = updated;
          },
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.textContaining('Posible duplicado'), findsOneWidget);

    await tester.tap(find.text('Continue'));
    await tester.pump();

    expect(captured, isNotNull);
  });
}
