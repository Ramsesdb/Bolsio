import 'dart:async';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:nitido/app/transactions/form/transaction_form.page.dart';
import 'package:nitido/app/transactions/receipt_import/receipt_review_page.dart';
import 'package:nitido/core/database/services/pending_import/pending_import_service.dart';
import 'package:nitido/core/presentation/helpers/snackbar.dart';
import 'package:nitido/core/routes/route_utils.dart';
import 'package:nitido/core/services/receipt_ocr/receipt_extractor_service.dart';
import 'package:nitido/core/services/receipt_ocr/receipt_image_service.dart';
import 'package:nitido/i18n/generated/translations.g.dart';

abstract class ReceiptImportFlow {
  static Future<void> start(
    BuildContext context,
    ImageSource source, {
    ReceiptImageService? imageService,
    ReceiptExtractorService? extractor,
  }) async {
    final t = Translations.of(context);

    final resolvedImageService = imageService ?? ReceiptImageService();
    final resolvedExtractor = extractor ?? ReceiptExtractorService();

    final file = await resolvedImageService.pickAndCompress(source: source);
    if (file == null) return;

    if (!context.mounted) return;

    final step = ValueNotifier<String>(
      t.transaction.receipt_import.processing_ocr,
    );

    BuildContext? capturedDialogContext;

    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        useRootNavigator: true,
        builder: (dialogContext) {
          capturedDialogContext = dialogContext;
          return AlertDialog(
            content: Row(
              children: [
                const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ValueListenableBuilder<String>(
                    valueListenable: step,
                    builder: (_, value, _) => Text(value),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );

    void dismissLoader() {
      final dCtx = capturedDialogContext;
      if (dCtx != null && Navigator.canPop(dCtx)) {
        Navigator.pop(dCtx);
      }
      capturedDialogContext = null;
    }

    try {
      await Future.delayed(const Duration(milliseconds: 150));
      step.value = t.transaction.receipt_import.processing_ai;

      final extraction = await resolvedExtractor.extractFromImage(file);

      step.value = t.transaction.receipt_import.processing_done;
      await Future.delayed(const Duration(milliseconds: 100));

      if (!context.mounted) {
        dismissLoader();
        return;
      }
      dismissLoader();

      if (extraction.outcome == ExtractionOutcome.imageCorrupt) {
        NitidoSnackbar.error(
          SnackbarParams(t.transaction.receipt_import.error.image_corrupt),
        );
        if (await file.exists()) {
          await file.delete();
        }
        return;
      }

      if (extraction.outcome == ExtractionOutcome.empty) {
        NitidoSnackbar.warning(
          SnackbarParams(t.transaction.receipt_import.error.ocr_empty),
        );
        await RouteUtils.pushRoute(
          TransactionFormPage(pendingAttachmentPath: file.path),
        );
        return;
      }

      if (extraction.outcome == ExtractionOutcome.noAmount) {
        NitidoSnackbar.warning(
          SnackbarParams(t.transaction.receipt_import.error.no_amount),
        );
        await RouteUtils.pushRoute(
          TransactionFormPage(pendingAttachmentPath: file.path),
        );
        return;
      }

      var showDuplicateWarning = false;
      final bankRef = extraction.proposal?.bankRef;
      if (bankRef != null && bankRef.trim().isNotEmpty) {
        final existing = await PendingImportService.instance.findByBankRef(
          bankRef.trim(),
        );
        showDuplicateWarning = existing != null;
      }

      if (!context.mounted) return;
      await RouteUtils.pushRoute(
        ReceiptReviewPage(
          pendingAttachmentPath: file.path,
          extraction: extraction,
          showDuplicateWarning: showDuplicateWarning,
        ),
      );
    } catch (e) {
      dismissLoader();
      if (!context.mounted) return;

      NitidoSnackbar.error(SnackbarParams.fromError(e));
      if (await file.exists()) {
        await file.delete();
      }
    }
  }
}
