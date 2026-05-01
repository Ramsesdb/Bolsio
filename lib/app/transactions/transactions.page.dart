// ignore_for_file: unnecessary_string_interpolations, prefer_single_quotes

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nitido/app/home/widgets/new_transaction_fl_button.dart';
import 'package:nitido/app/layout/page_context.dart';
import 'package:nitido/app/layout/page_framework.dart';
import 'package:nitido/app/transactions/widgets/bulk_edit_transaction_modal.dart';
import 'package:nitido/app/transactions/widgets/transaction_list.dart';
import 'package:nitido/app/transactions/widgets/transaction_list_tile.dart';
import 'package:nitido/core/database/services/account/account_service.dart';
import 'package:nitido/core/database/services/transaction/transaction_service.dart';
import 'package:nitido/core/database/services/user-setting/hidden_mode_service.dart';
import 'package:nitido/core/models/account/account.dart';
import 'package:nitido/core/extensions/padding.extension.dart';
import 'package:nitido/core/models/transaction/transaction.dart';
import 'package:nitido/core/presentation/animations/animated_expanded.dart';
import 'package:nitido/core/presentation/helpers/snackbar.dart';
import 'package:nitido/core/presentation/widgets/confirm_dialog.dart';
import 'package:nitido/core/presentation/widgets/filter_row_indicator.dart';
import 'package:nitido/core/presentation/widgets/nitido_popup_menu_button.dart';
import 'package:nitido/app/transactions/auto_import/pending_imports.page.dart';
import 'package:nitido/core/database/services/pending_import/pending_import_service.dart';
import 'package:nitido/core/presentation/widgets/no_results.dart';
import 'package:nitido/core/presentation/widgets/number_ui_formatters/currency_displayer.dart';
import 'package:nitido/core/presentation/widgets/transaction_filter/transaction_filter_sheet_modal.dart';
import 'package:nitido/core/presentation/widgets/transaction_filter/transaction_filter_set.dart';
import 'package:nitido/core/routes/route_utils.dart';
import 'package:nitido/core/utils/list_tile_action_item.dart';
import 'package:nitido/i18n/generated/translations.g.dart';
import 'package:rxdart/rxdart.dart';
import 'package:skeletonizer/skeletonizer.dart';

class TransactionsPage extends StatefulWidget {
  const TransactionsPage({super.key, this.filters});

  final TransactionFilterSet? filters;

  @override
  State<TransactionsPage> createState() => TransactionsPageState();
}

class TransactionsPageState extends State<TransactionsPage> {
  late TransactionFilterSet filters;

  bool searchActive = false;

  FocusNode searchFocusNode = FocusNode();
  final searchController = TextEditingController();
  final ScrollController listScrollController = ScrollController();

  List<MoneyTransaction> selectedTransactions = [];

  void resetScroll() {
    if (listScrollController.hasClients) {
      listScrollController.jumpTo(0);
    }
  }

  @override
  void initState() {
    super.initState();

    filters = widget.filters ?? const TransactionFilterSet();

    debugPrint("INITIAL FILTERS: $filters");

    searchFocusNode.addListener(() {
      if (!searchFocusNode.hasFocus && searchController.text.isEmpty) {
        setState(() {
          searchActive = false;
        });
      }
    });
  }

  @override
  void dispose() {
    searchFocusNode.dispose();
    searchController.dispose();
    super.dispose();
  }

  bool get canPop => !searchActive && selectedTransactions.isEmpty;

  /// Hidden-Mode-aware view of the page filters.
  ///
  /// We intentionally do **not** intersect [TransactionFilterSet.accountsIDs]
  /// with the visible account ids (as dashboard/stats do). The default
  /// account filter uses OR semantics across origin/destiny accounts, which
  /// would still show a transfer from a visible account into a saving
  /// account — exactly what Hidden Mode needs to hide.
  ///
  /// Instead we populate [TransactionFilterSet.excludeAccountsIDs] with the
  /// complement of the visible set (i.e. the saving accounts the user opted
  /// to hide). That filter applies with AND semantics to both sides of every
  /// transfer, so a transaction/transfer is dropped as soon as *either* side
  /// is hidden.
  TransactionFilterSet _applyHiddenAccountsFilter(
    TransactionFilterSet base,
    List<String>? visibleIds,
    List<Account>? allAccounts,
  ) {
    if (visibleIds == null || allAccounts == null) return base;

    final visibleSet = visibleIds.toSet();
    final hidden = allAccounts
        .map((a) => a.id)
        .where((id) => !visibleSet.contains(id))
        .toList(growable: false);

    if (hidden.isEmpty) return base;

    // Preserve any exclude set the caller already provided (there is none
    // today, but this keeps the helper composable).
    final baseExcluded = base.excludeAccountsIDs;
    final merged = baseExcluded == null
        ? hidden
        : <String>{...baseExcluded, ...hidden}.toList(growable: false);

    return base.copyWith(excludeAccountsIDs: merged);
  }

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);

    return PopScope(
      canPop: canPop,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;

        if (selectedTransactions.isNotEmpty) {
          cleanSelectedTransactions();
          return;
        }

        if (searchActive ||
            searchController.text.isNotEmpty ||
            searchFocusNode.hasFocus) {
          if (searchFocusNode.hasFocus) {
            searchFocusNode.unfocus();
          }

          closeSearch();

          return;
        }
      },
      child: PageFramework(
        title: t.transaction.display(n: 10),
        appBarBuilder: (_, _, _) => selectedTransactions.isNotEmpty
            ? selectedTransactionsAppbar()
            : transactionsPageDefaultAppBar(t, context),
        floatingActionButton: ifIsInTabs(context)
            ? null
            : NewTransactionButton(scrollController: listScrollController),
        floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
        body: Column(
          children: [
            AnimatedExpanded(
              expand: filters.hasFilter,
              duration: const Duration(milliseconds: 250),
              child: FilterRowIndicator(
                filters: filters.copyWith(searchValue: searchController.text),
                onChange: (newFilters) {
                  setState(() {
                    filters = newFilters;
                  });
                },
              ),
            ),
            // Hidden-Mode gate. While the feature is locked the inner stream
            // emits the complement of visible accounts via `excludeAccountsIDs`
            // on both the count/balance card and the list below, so savings
            // transactions AND transfers touching savings disappear at the SQL
            // level — no client-side filtering needed.
            Expanded(
              child: StreamBuilder<({List<String>? visible, List<Account>? all})>(
                stream: Rx.combineLatest2<List<String>, List<Account>,
                    ({List<String>? visible, List<Account>? all})>(
                  HiddenModeService.instance.visibleAccountIdsStream,
                  AccountService.instance.getAccounts(),
                  (v, a) => (visible: v, all: a),
                ),
                builder: (context, hiddenSnapshot) {
                  final effectiveFilters = _applyHiddenAccountsFilter(
                    filters.copyWith(searchValue: searchController.text),
                    hiddenSnapshot.data?.visible,
                    hiddenSnapshot.data?.all,
                  );

                  return Column(
                    children: [
                      StreamBuilder<TransactionQueryStatResultWithMissing>(
                        stream: TransactionService.instance
                            .getTransactionsCountAndBalanceWithMissing(
                              filters: effectiveFilters,
                            ),
                        builder: (context, snapshot) {
                          final stat = snapshot.data;
                          final trCountAndBalance = stat == null
                              ? null
                              : (
                                  count: stat.numberOfRes,
                                  value: stat.valueSum,
                                );
                          final hasMissingRates =
                              stat?.hasMissingRates ?? false;
                          final missingCurrencies =
                              stat?.missingRateCurrencies ?? const <String>{};

                          const smallerTextStyle = TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w300,
                          );

                          return Skeletonizer(
                            enabled: trCountAndBalance == null,
                            child: Card(
                              elevation: 2,
                              margin: const EdgeInsets.all(8),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 8,
                                  horizontal: 14,
                                ),
                                child: DefaultTextStyle(
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleMedium!,
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      if (trCountAndBalance == null)
                                        const SizedBox.shrink(),
                                      if (trCountAndBalance != null)
                                        Text.rich(
                                          TextSpan(
                                            text:
                                                selectedTransactions.isNotEmpty
                                                ? ('${selectedTransactions.length.toStringAsFixed(0)}')
                                                : '',
                                            children: [
                                              TextSpan(
                                                text:
                                                    '${selectedTransactions.isNotEmpty ? ' / ' : ''}${trCountAndBalance.count} ',
                                                style:
                                                    selectedTransactions
                                                        .isNotEmpty
                                                    ? smallerTextStyle
                                                    : null,
                                              ),
                                              if (selectedTransactions
                                                  .isNotEmpty)
                                                const TextSpan(text: " "),
                                              TextSpan(
                                                text: t.transaction
                                                    .display(
                                                      n: trCountAndBalance
                                                          .count,
                                                    )
                                                    .toLowerCase(),
                                              ),
                                            ],
                                          ),
                                        ),
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          if (selectedTransactions
                                              .isNotEmpty) ...[
                                            CurrencyDisplayer(
                                              amountToConvert:
                                                  selectedTransactions
                                                      .map(
                                                        (e) =>
                                                            e.getCurrentBalanceInPreferredCurrency() ??
                                                            0.0,
                                                      )
                                                      .sum,
                                              showDecimals: false,
                                            ),
                                            const Text(
                                              " / ",
                                              style: smallerTextStyle,
                                            ),
                                          ],
                                          CurrencyDisplayer(
                                            amountToConvert:
                                                trCountAndBalance?.value ?? 0,
                                            showDecimals:
                                                selectedTransactions.isEmpty,
                                            integerStyle:
                                                selectedTransactions.isEmpty
                                                ? const TextStyle(
                                                    inherit: true,
                                                  )
                                                : smallerTextStyle,
                                          ),
                                          if (hasMissingRates) ...[
                                            const SizedBox(width: 6),
                                            Tooltip(
                                              message:
                                                  'Tasa no configurada para: ${missingCurrencies.join(', ')}',
                                              child: Icon(
                                                Icons.info_outline,
                                                size: 16,
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .error,
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                      Expanded(
                        child: TransactionListComponent(
                          scrollController: listScrollController,
                          isScrollable: true,
                          listPadding: const EdgeInsets.only(
                            bottom: 64,
                          ).withSafeBottom(context),
                          tileBuilder: (tr) => TransactionListTile(
                            transaction: tr,
                            heroTag:
                                'transactions-page__tr-icon-${tr.id}',
                            onLongPress: selectedTransactions.isNotEmpty
                                ? null
                                : () => toggleTransaction(tr),
                            onTap: selectedTransactions.isEmpty
                                ? null
                                : () => toggleTransaction(tr),
                            isSelected: selectedTransactions.any(
                              (element) => element.id == tr.id,
                            ),
                            showDateTime: false,
                            applySwipeActions: true,
                          ),
                          filters: effectiveFilters,
                          onEmptyList: NoResults(
                            title: filters.hasFilter
                                ? null
                                : t.general.empty_warn,
                            description: filters.hasFilter
                                ? t.transaction.list.searcher_no_results
                                : t.transaction.list.empty,
                            noSearchResultsVariation: filters.hasFilter,
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void closeSearch() {
    setState(() {
      searchController.text = "";
      searchFocusNode.unfocus();
    });
  }

  AppBar transactionsPageDefaultAppBar(Translations t, BuildContext context) {
    return AppBar(
      leading: searchActive
          ? IconButton(onPressed: closeSearch, icon: const Icon(Icons.close))
          : null,
      title: AnimatedSwitcher(
        duration: const Duration(milliseconds: 175),
        child: searchActive
            ? TextField(
                controller: searchController,
                focusNode: searchFocusNode,
                decoration: InputDecoration(
                  hintText: t.transaction.list.searcher_placeholder,
                  border: const UnderlineInputBorder(),
                  filled: true,
                  contentPadding: const EdgeInsets.symmetric(
                    vertical: 16,
                    horizontal: 8,
                  ),
                ),
                onChanged: (text) {
                  setState(() {});
                },
              )
            : Text(t.transaction.display(n: 10)),
      ),
      actions: [
        if (!searchActive)
          StreamBuilder<int>(
            stream: PendingImportService.instance.watchPendingCount(),
            initialData: 0,
            builder: (context, snapshot) {
              final count = snapshot.data ?? 0;
              return IconButton(
                icon: count > 0
                    ? Badge.count(count: count, child: const Icon(Icons.inbox))
                    : const Icon(Icons.inbox_outlined),
                tooltip: 'Auto-import',
                onPressed: () {
                  RouteUtils.pushRoute(const PendingImportsPage());
                },
              );
            },
          ),
        if (!searchActive)
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () {
              searchActive = true;
              searchFocusNode.requestFocus();
              setState(() {});
            },
          ),
        IconButton(
          onPressed: () async {
            final modalRes = await openFilterSheetModal(
              context,
              FilterSheetModal(preselectedFilter: filters),
            );

            if (modalRes != null) {
              setState(() {
                filters = modalRes;
              });
            }
          },
          icon: const Icon(Icons.filter_alt_outlined),
        ),
      ],
    );
  }

  AppBar selectedTransactionsAppbar() {
    return AppBar(
      backgroundColor: Theme.of(context).colorScheme.primary,
      foregroundColor: Theme.of(context).colorScheme.onPrimary,
      leading: IconButton(
        onPressed: () {
          cleanSelectedTransactions();
        },
        icon: const Icon(Icons.close),
      ),
      title: Text(
        t.transaction.list.selected_short(n: selectedTransactions.length),
      ),
      actions: [
        NitidoPopupMenuButton(
          actionItems: [
            ListTileActionItem(
              label: t.ui_actions.edit,
              icon: Icons.edit_rounded,
              onClick: () {
                showModalBottomSheet(
                  context: context,
                  showDragHandle: true,
                  builder: (context) {
                    return BulkEditTransactionModal(
                      transactionsToEdit: selectedTransactions,
                      onSuccess: () {
                        selectedTransactions = [];
                      },
                    );
                  },
                );
              },
            ),
            ListTileActionItem(
              label: t.ui_actions.delete,
              icon: Icons.delete_rounded,
              onClick: () {
                confirmDialog(
                  context,
                  dialogTitle: selectedTransactions.length <= 1
                      ? t.transaction.delete
                      : t.transaction.delete_multiple,
                  confirmationText: t.ui_actions.confirm,
                  showCancelButton: true,
                  icon: Icons.delete_rounded,
                  contentParagraphs: [
                    Text(
                      selectedTransactions.length <= 1
                          ? t.transaction.delete_warning_message
                          : t.transaction.delete_multiple_warning_message(
                              x: selectedTransactions.length,
                            ),
                    ),
                  ],
                ).then((value) {
                  if (value != true) {
                    return;
                  }

                  final futures = selectedTransactions.map(
                    (e) => TransactionService.instance.deleteTransaction(e.id),
                  );

                  Future.wait(futures)
                      .then((value) {
                        NitidoSnackbar.success(
                          SnackbarParams(
                            selectedTransactions.length <= 1
                                ? t.transaction.delete_success
                                : t.transaction.delete_multiple_success(
                                    x: selectedTransactions.length,
                                  ),
                          ),
                        );

                        cleanSelectedTransactions();
                      })
                      .catchError((err) {
                        NitidoSnackbar.error(SnackbarParams.fromError(err));
                      });
                });
              },
              role: ListTileActionRole.delete,
            ),
          ],
        ),
      ],
    );
  }

  /// Clear all the selected transactions (remove the selection)
  void cleanSelectedTransactions() {
    setState(() {
      selectedTransactions = [];
    });
  }

  void toggleTransaction(MoneyTransaction tr) {
    HapticFeedback.lightImpact();

    if (selectedTransactions.any((element) => element.id == tr.id)) {
      selectedTransactions.removeWhere((element) => element.id == tr.id);
    } else {
      selectedTransactions.add(tr);
    }

    setState(() {});
  }
}
