import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:bolsio/app/categories/selectors/category_picker.dart';
import 'package:bolsio/app/transactions/form/dialogs/transaction_status_selector.dart';
import 'package:bolsio/core/database/services/transaction/transaction_service.dart';
import 'package:bolsio/core/models/category/category.dart';
import 'package:bolsio/core/models/transaction/transaction.dart';
import 'package:bolsio/core/presentation/helpers/snackbar.dart';
import 'package:bolsio/core/presentation/widgets/modal_container.dart';
import 'package:bolsio/core/presentation/widgets/outlined_button_stacked.dart';
import 'package:bolsio/core/routes/route_utils.dart';
import 'package:bolsio/core/utils/date_time_picker.dart';
import 'package:bolsio/i18n/generated/translations.g.dart';

class BulkEditTransactionModal extends StatelessWidget {
  const BulkEditTransactionModal({
    super.key,
    required this.transactionsToEdit,
    required this.onSuccess,
  });

  final List<MoneyTransaction> transactionsToEdit;

  final void Function() onSuccess;

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);

    return ModalContainer(
      title: t.transaction.edit_multiple,
      subtitle: t.transaction.list.selected_long(n: transactionsToEdit.length),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          children: [
            _buildSelectOption(
              text: t.transaction.list.bulk_edit.dates,
              iconData: Icons.calendar_month,
              onTap: () =>
                  openDateTimePicker(
                    context,
                    showTimePickerAfterDate: true,
                  ).then((date) {
                    if (date == null) {
                      return;
                    }
                    if (!context.mounted) return;

                    performUpdates(
                      context,
                      futures: transactionsToEdit.map(
                        (e) => TransactionService.instance.updateTransaction(
                          e.copyWith(date: date),
                        ),
                      ),
                    );
                  }),
            ),
            const SizedBox(height: 8),
            _buildSelectOption(
              text: t.transaction.list.bulk_edit.categories,
              iconData: Icons.category_rounded,
              onTap: () {
                showCategoryPickerModal(
                  context,
                  modal: CategoryPicker(
                    selectedCategory: null,
                    categoryType: CategoryType.values,
                  ),
                ).then((modalRes) {
                  if (modalRes == null) {
                    return;
                  }
                  if (!context.mounted) return;

                  performUpdates(
                    context,
                    futures: transactionsToEdit.map(
                      (e) => TransactionService.instance.updateTransaction(
                        e.copyWith(categoryID: Value(modalRes.id)),
                      ),
                    ),
                  );
                });
              },
            ),
            const SizedBox(height: 8),
            _buildSelectOption(
              text: t.transaction.list.bulk_edit.status,
              iconData: Icons.fullscreen_rounded,
              onTap: () {
                showTransactioStatusModal(context, initialStatus: null).then((
                  modalRes,
                ) {
                  if (modalRes == null) {
                    return;
                  }
                  if (!context.mounted) return;

                  performUpdates(
                    context,
                    futures: transactionsToEdit.map(
                      (e) => TransactionService.instance.updateTransaction(
                        e.copyWith(status: Value(modalRes.result)),
                      ),
                    ),
                  );
                });
              },
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  OutlinedButtonStacked _buildSelectOption({
    required void Function()? onTap,
    required String text,
    required IconData iconData,
  }) {
    return OutlinedButtonStacked(
      text: text,
      onTap: onTap,
      alignLeft: true,
      alignBeside: true,
      fontSize: 18,
      padding: const EdgeInsets.all(16),
      iconData: iconData,
    );
  }

  void performUpdates(
    BuildContext context, {
    required Iterable<Future<int>> futures,
  }) {
    RouteUtils.popRoute();

    Future.wait(futures)
        .then((value) {
          BolsioSnackbar.success(
            transactionsToEdit.length <= 1
                ? SnackbarParams(t.transaction.edit_success)
                : SnackbarParams(
                    t.transaction.edit_multiple_success(
                      x: transactionsToEdit.length,
                    ),
                  ),
          );

          onSuccess();
        })
        .catchError((err) {
          BolsioSnackbar.error(SnackbarParams.fromError(err));
        });
  }
}
