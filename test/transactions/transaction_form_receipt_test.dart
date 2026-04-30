import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bolsio/app/transactions/form/transaction_form.page.dart';
import 'package:bolsio/core/database/services/user-setting/user_setting_service.dart';
import 'package:bolsio/core/models/auto_import/capture_channel.dart';
import 'package:bolsio/core/models/auto_import/transaction_proposal.dart';
import 'package:bolsio/core/models/transaction/transaction_type.enum.dart';
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

TransactionProposal _proposalWithoutAccount() {
  return TransactionProposal.newProposal(
    amount: 15,
    currencyId: 'USD',
    date: DateTime(2026, 4, 17, 11, 0),
    type: TransactionType.expense,
    counterpartyName: 'Sin Cuenta',
    bankRef: 'ABCD',
    rawText: 'raw',
    channel: CaptureChannel.receiptImage,
    sender: 'test',
    confidence: 0.7,
    accountId: null,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await LocaleSettings.setLocale(AppLocale.en);
    appStateSettings[SettingKey.font] = '0';
    appStateSettings[SettingKey.accentColor] = 'auto';
    appStateSettings[SettingKey.amoledMode] = '0';
    appStateSettings[SettingKey.themeMode] = 'system';
  });

  testWidgets('4.11 save button disabled until account is selected', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        TransactionFormPage.fromReceipt(
          receiptPrefill: _proposalWithoutAccount(),
          pendingAttachmentPath: 'tmp/receipt.jpg',
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));

    final saveButtonFinder = find.byKey(
      const ValueKey('transaction_form_save_button'),
    );
    expect(
      saveButtonFinder,
      findsOneWidget,
      reason:
          'TransactionFormPage must expose the Guardar/Save button via the '
          '"transaction_form_save_button" key.',
    );

    final saveButton = tester.widget<ButtonStyleButton>(saveButtonFinder);
    expect(
      saveButton.onPressed,
      isNull,
      reason:
          'Save button must be disabled when fromAccount is null after receipt '
          'prefill (scenario 4.11).',
    );
  });
}
