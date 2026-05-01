import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart';
import 'package:nitido/app/accounts/account_form.dart';
import 'package:nitido/app/accounts/details/account_details.dart';
import 'package:nitido/app/accounts/statement_import/statement_import_flow.dart';
import 'package:nitido/app/transactions/form/transaction_form.page.dart';
import 'package:nitido/core/database/services/account/account_service.dart';
import 'package:nitido/core/models/account/account.dart';
import 'package:nitido/core/presentation/helpers/snackbar.dart';
import 'package:nitido/core/presentation/widgets/confirm_dialog.dart';
import 'package:nitido/core/routes/route_utils.dart';
import 'package:nitido/core/utils/list_tile_action_item.dart';
import 'package:nitido/i18n/generated/translations.g.dart';

import '../../../core/models/transaction/transaction_type.enum.dart';

abstract class AccountDetailsActions {
  static List<ListTileActionItem> getAccountDetailsActions(
    BuildContext context, {
    required Account account,
    bool navigateBackOnDelete = false,
  }) {
    final t = Translations.of(context);

    return [
      ListTileActionItem(
        label: t.ui_actions.edit,
        icon: Icons.edit,
        onClick: () => RouteUtils.pushRoute(AccountFormPage(account: account)),
      ),
      if (!account.isClosed)
        ListTileActionItem(
          label: t.statement_import.entry_point,
          icon: Icons.file_download_outlined,
          onClick: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => StatementImportFlow(account: account),
            ),
          ),
        ),
      ListTileActionItem(
        label: t.transfer.create,
        icon: TransactionType.transfer.icon,
        onClick: account.isClosed
            ? null
            : () async {
                showAccountsWarn() async => await confirmDialog(
                  context,
                  dialogTitle: t.transfer.need_two_accounts_warning_header,
                  contentParagraphs: [
                    Text(t.transfer.need_two_accounts_warning_message),
                  ],
                );

                navigateToTransferForm() => RouteUtils.pushRoute(
                  TransactionFormPage(
                    fromAccount: account,
                    mode: TransactionType.transfer,
                  ),
                );

                final numberOfAccounts =
                    (await AccountService.instance
                            .getAccounts(
                              predicate: (acc, curr) =>
                                  acc.closingDate.isNull(),
                            )
                            .first)
                        .length;

                if (numberOfAccounts <= 1) {
                  await showAccountsWarn();
                } else {
                  await navigateToTransferForm();
                }
              },
      ),
      ListTileActionItem(
        label: account.isClosed
            ? t.account.reopen_short
            : t.account.close.title_short,
        icon: account.isClosed
            ? Icons.unarchive_rounded
            : Icons.archive_rounded,
        role: ListTileActionRole.warn,
        onClick: () async {
          if (account.isClosed) {
            showReopenAccountDialog(context, account);
            return;
          }

          final currentBalance = await AccountService.instance
              .getAccountMoney(account: account)
              .first;

          if (!context.mounted) return;
          await showCloseAccountDialog(
            context,
            account: account,
            currentBalance: currentBalance,
          );
        },
      ),
      ListTileActionItem(
        label: t.ui_actions.delete,
        icon: Icons.delete,
        role: ListTileActionRole.delete,
        onClick: () {
          deleteAccountWithAlertAndSnackBar(
            context,
            accountId: account.id,
            navigateBack: navigateBackOnDelete,
          );
        },
      ),
    ];
  }

  static void showReopenAccountDialog(BuildContext context, Account account) {
    confirmDialog(
      context,
      showCancelButton: true,
      dialogTitle: t.account.reopen,
      contentParagraphs: [Text(t.account.reopen_descr)],
      confirmationText: t.ui_actions.confirm,
    ).then((isConfirmed) {
      AccountService.instance
          .updateAccount(account.copyWith(closingDate: const drift.Value(null)))
          .then((value) {
            if (value) {
              NitidoSnackbar.success(
                SnackbarParams(t.account.close.unarchive_succes),
              );
            }
          })
          .catchError((err) {
            NitidoSnackbar.error(SnackbarParams.fromError(err));
          });
    });
  }

  static Future<bool?> showCloseAccountDialog(
    BuildContext context, {
    required Account account,
    required double currentBalance,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) =>
          ArchiveWarnDialog(currentBalance: currentBalance, account: account),
    );
  }

  static void deleteAccountWithAlertAndSnackBar(
    BuildContext context, {
    required String accountId,
    required bool navigateBack,
  }) {
    confirmDialog(
      context,
      dialogTitle: t.account.delete.warning_header,
      contentParagraphs: [Text(t.account.delete.warning_text)],
      confirmationText: t.ui_actions.continue_text,
      showCancelButton: true,
      icon: Icons.delete,
    ).then((isConfirmed) {
      if (isConfirmed != true) return;

      AccountService.instance
          .deleteAccount(accountId)
          .then((value) {
            if (navigateBack) {
              RouteUtils.popRoute();
            }

            NitidoSnackbar.success(SnackbarParams(t.account.delete.success));
          })
          .catchError((err) {
            NitidoSnackbar.error(SnackbarParams.fromError(err));
          });
    });
  }
}
