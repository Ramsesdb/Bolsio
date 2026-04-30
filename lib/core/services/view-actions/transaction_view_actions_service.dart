import 'package:drift/drift.dart';
import 'package:flutter/material.dart';
import 'package:bolsio/app/transactions/form/transaction_form.page.dart';
import 'package:bolsio/core/database/app_db.dart';
import 'package:bolsio/core/database/services/debts/debt_service.dart';
import 'package:bolsio/core/database/services/tags/tags_service.dart';
import 'package:bolsio/core/database/services/transaction/transaction_service.dart';
import 'package:bolsio/core/models/transaction/transaction.dart';
import 'package:bolsio/core/models/transaction/transaction_status.enum.dart';
import 'package:bolsio/core/presentation/helpers/snackbar.dart';
import 'package:bolsio/core/presentation/widgets/confirm_dialog.dart';
import 'package:bolsio/core/routes/route_utils.dart';
import 'package:bolsio/core/utils/list_tile_action_item.dart';
import 'package:bolsio/core/utils/uuid.dart';

import '../../../i18n/generated/translations.g.dart';

class TransactionViewActionService {
  final TransactionService transactionService = TransactionService.instance;

  TransactionViewActionService();

  List<ListTileActionItem> transactionDetailsActions(
    BuildContext context, {
    required MoneyTransaction transaction,
    bool navigateBackOnDelete = false,
  }) {
    final isRecurrent = transaction.recurrentInfo.isRecurrent;

    return [
      ListTileActionItem(
        label: t.ui_actions.edit,
        icon: Icons.edit,
        onClick: () => RouteUtils.pushRoute(
          TransactionFormPage(
            transactionToEdit: transaction,
            mode: transaction.type,
          ),
        ),
      ),
      if (transaction.recurrentInfo.isNoRecurrent)
        ListTileActionItem(
          label: t.transaction.duplicate_short,
          icon: Icons.control_point_duplicate_rounded,
          onClick: () => TransactionViewActionService()
              .cloneTransactionWithAlertAndSnackBar(
                context,
                transaction: transaction,
              ),
        ),
      ListTileActionItem(
        label: t.ui_actions.delete,
        icon: Icons.delete,
        role: ListTileActionRole.delete,
        onClick: () => TransactionViewActionService()
            .deleteTransactionWithAlertAndSnackBar(
              context,
              transactionId: transaction.id,
              isRecurrent: isRecurrent,
              navigateBack: navigateBackOnDelete,
            ),
      ),
    ];
  }

  void deleteTransactionWithAlertAndSnackBar(
    BuildContext context, {
    required String transactionId,
    bool isRecurrent = false,
    required bool navigateBack,
  }) {
    final t = Translations.of(context);

    confirmDialog(
      context,
      icon: Icons.delete,
      dialogTitle: !isRecurrent
          ? t.transaction.delete
          : t.recurrent_transactions.details.delete_header,
      contentParagraphs: [
        Text(
          !isRecurrent
              ? t.transaction.delete_warning_message
              : t.recurrent_transactions.details.delete_message,
        ),
      ],
      confirmationText: t.ui_actions.continue_text,
    ).then((isConfirmed) {
      if (isConfirmed != true) return;

      transactionService
          .deleteTransaction(transactionId)
          .then((value) {
            if (value == 0) {
              BolsioSnackbar.error(
                SnackbarParams('Error removing the transaction'),
              );

              return;
            }

            if (navigateBack && context.mounted) {
              RouteUtils.popRoute();
            }

            BolsioSnackbar.success(
              SnackbarParams(t.transaction.delete_success),
            );
          })
          .catchError((err) {
            BolsioSnackbar.error(SnackbarParams.fromError(err));
          });
    });
  }

  void cloneTransactionWithAlertAndSnackBar(
    BuildContext context, {
    required MoneyTransaction transaction,
  }) {
    final t = Translations.of(context);

    confirmDialog(
      context,
      icon: Icons.control_point_duplicate_rounded,
      dialogTitle: t.transaction.duplicate,
      contentParagraphs: [Text(t.transaction.duplicate_warning_message)],
      confirmationText: t.ui_actions.continue_text,
    ).then((isConfirmed) async {
      if (isConfirmed != true) return;

      final newTrId = generateUUID();

      try {
        await _duplicateTransaction(transaction, newTrId);

        BolsioSnackbar.success(
          SnackbarParams(t.transaction.duplicate_success),
        );
      } catch (error) {
        BolsioSnackbar.error(SnackbarParams.fromError(error));
      }
    });
  }

  Future<void> _duplicateTransaction(
    MoneyTransaction transaction,
    String newTrId,
  ) async {
    await transactionService.insertTransaction(
      transaction.copyWith(id: newTrId),
    );

    await TagService.instance.linkTagsToTransaction(
      transactionId: newTrId,
      tagIds: transaction.tags.map((t) => t.id).toList(),
    );
  }

  Future<int> updateTransactionStatus(
    String transactionId,
    TransactionStatus? statusCodeString,
  ) {
    final db = AppDB.instance;

    return (db.update(db.transactions)
          ..where((transaction) => transaction.id.equals(transactionId)))
        .write(TransactionsCompanion(status: Value(statusCodeString)));
  }

  void unlinkTransactionFromDebtWithAlertAndSnackbar(
    BuildContext context, {
    required String transactionId,
  }) {
    final t = Translations.of(context);

    confirmDialog(
      context,
      icon: Icons.link_off_rounded,
      dialogTitle: t.debts.actions.unlink_transaction.title,
      contentParagraphs: [
        Text(t.debts.actions.unlink_transaction.warning_text),
      ],
      confirmationText: t.ui_actions.continue_text,
    ).then((isConfirmed) {
      if (isConfirmed != true) return;

      DebtService.instance
          .unlinkTransactionFromDebt(transactionId)
          .then((value) {
            BolsioSnackbar.success(
              SnackbarParams(t.debts.actions.unlink_transaction.success),
            );
          })
          .catchError((err) {
            BolsioSnackbar.error(SnackbarParams.fromError(err));
          });
    });
  }
}
