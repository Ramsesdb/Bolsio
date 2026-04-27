import 'dart:io';

import 'package:collection/collection.dart';
import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart';
import 'package:wallex/app/accounts/account_selector.dart';
import 'package:wallex/app/categories/selectors/category_picker.dart';
import 'package:wallex/app/layout/page_framework.dart';
import 'package:wallex/app/transactions/form/dialogs/amount_selector.dart';
import 'package:wallex/app/transactions/form/widgets/transaction_account_selector_row.dart';
import 'package:wallex/app/transactions/form/widgets/transaction_amount_display.dart';
import 'package:wallex/app/transactions/form/widgets/transaction_date_selector.dart';
import 'package:wallex/app/transactions/form/widgets/transaction_form_fields.dart';
import 'package:wallex/app/transactions/form/widgets/exchange_rate_selector.dart';
import 'package:wallex/app/transactions/form/widgets/transaction_selectors.dart';
import 'package:wallex/core/database/app_db.dart';
import 'package:wallex/core/database/services/account/account_service.dart';
import 'package:wallex/core/database/services/currency/currency_service.dart';
import 'package:wallex/core/database/services/category/category_service.dart';
import 'package:wallex/core/database/services/tags/tags_service.dart';
import 'package:wallex/core/database/services/transaction/transaction_service.dart';
import 'package:wallex/core/database/services/user-setting/default_transaction_values.service.dart';
import 'package:wallex/core/database/services/user-setting/user_setting_service.dart';
import 'package:wallex/core/database/utils/drift_utils.dart';
import 'package:wallex/core/extensions/color.extensions.dart';
import 'package:wallex/core/models/account/account.dart';
import 'package:wallex/core/models/category/category.dart';
import 'package:wallex/core/models/tags/tag.dart';
import 'package:wallex/core/models/transaction/recurrency_data.dart';
import 'package:wallex/core/models/transaction/transaction.dart';
import 'package:wallex/core/models/transaction/transaction_form_field.enum.dart';
import 'package:wallex/core/models/transaction/transaction_status.enum.dart';
import 'package:wallex/core/models/auto_import/transaction_proposal.dart';
import 'package:wallex/core/presentation/animations/shake_widget.dart';
import 'package:wallex/core/presentation/helpers/snackbar.dart';
import 'package:wallex/core/presentation/responsive/breakpoint_container.dart';
import 'package:wallex/core/presentation/responsive/breakpoints.dart';
import 'package:wallex/core/presentation/widgets/persistent_footer_button.dart';
import 'package:wallex/core/routes/route_utils.dart';
import 'package:wallex/core/services/attachments/attachment_model.dart';
import 'package:wallex/core/services/attachments/attachments_service.dart';
import 'package:wallex/core/utils/uuid.dart';
import 'package:wallex/app/transactions/form/widgets/debt_link_banner.dart';
import 'package:wallex/core/models/debt/debt.dart';
import 'package:wallex/i18n/generated/translations.g.dart';

import '../../../core/models/transaction/transaction_type.enum.dart';

class TransactionFormPage extends StatefulWidget {
  const TransactionFormPage({
    super.key,
    this.mode,
    this.fromAccount,
    this.transactionToEdit,
    this.linkedDebt,
    this.receiptPrefill,
    this.voicePrefill,
    this.pendingAttachmentPath,
  });

  const TransactionFormPage.fromReceipt({
    super.key,
    required this.receiptPrefill,
    required this.pendingAttachmentPath,
  }) : mode = null,
       fromAccount = null,
       transactionToEdit = null,
       linkedDebt = null,
       voicePrefill = null;

  const TransactionFormPage.fromVoice({
    super.key,
    required this.voicePrefill,
  }) : mode = null,
       fromAccount = null,
       transactionToEdit = null,
       linkedDebt = null,
       receiptPrefill = null,
       pendingAttachmentPath = null;

  final TransactionType? mode;

  final MoneyTransaction? transactionToEdit;

  final Account? fromAccount;

  /// When non-null, the transaction being created will be pre-linked to this debt.
  final Debt? linkedDebt;

  /// Optional prefill data when coming from receipt OCR review.
  final TransactionProposal? receiptPrefill;

  /// Optional prefill data when coming from the voice quick-expense flow.
  final TransactionProposal? voicePrefill;

  /// Temporary local image path pending attachment persistence after submit.
  final String? pendingAttachmentPath;

  @override
  State<TransactionFormPage> createState() => _TransactionFormPageState();
}

class _TransactionFormPageState extends State<TransactionFormPage>
    with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _shakeKey = GlobalKey<ShakeWidgetState>();
  late TabController _tabController;

  // --- Form Fields ---

  double transactionValue = 0;

  TextEditingController valueInDestinyController = TextEditingController();
  double? get valueInDestinyToNumber =>
      double.tryParse(valueInDestinyController.text);

  Category? selectedCategory;

  Account? fromAccount;
  Account? transferAccount;

  DateTime date = DateTime.now();

  TransactionStatus? status;

  TextEditingController notesController = TextEditingController();
  TextEditingController titleController = TextEditingController();

  RecurrencyData recurrentRule = const RecurrencyData.noRepeat();

  List<Tag> tags = [];

  // --- FX Fields ---
  double? _selectedExchangeRate;
  String? _selectedExchangeSource;
  String? _preferredCurrencyCode;

  /// Tracks whether the user manually edited the destination amount field.
  /// When true, changes to the exchange rate selector will NOT overwrite the
  /// destination value; instead, the effective rate is recalculated from
  /// valueInDestiny / transactionValue.
  bool _destinyManuallyOverridden = false;

  /// Whether this is a cross-currency transfer (from and to accounts have
  /// different currencies). Used to conditionally show valueInDestiny field.
  bool get _isCrossCurrencyTransfer {
    return transactionType.isTransfer &&
        fromAccount != null &&
        transferAccount != null &&
        fromAccount!.currency.code != transferAccount!.currency.code;
  }

  /// Whether to show the exchange rate selector.
  /// True when the account currency differs from the user's preferred currency
  /// (income/expense) or when transfer accounts have different currencies.
  bool get _showExchangeRateSelector {
    if (_preferredCurrencyCode == null) return false;

    if (transactionType.isTransfer) {
      // Transfer: show when fromAccount and transferAccount have different currencies
      if (fromAccount != null && transferAccount != null) {
        return fromAccount!.currency.code != transferAccount!.currency.code;
      }
      return false;
    } else {
      // Income/Expense: show when account currency differs from preferred
      if (fromAccount != null) {
        return fromAccount!.currency.code != _preferredCurrencyCode;
      }
      return false;
    }
  }

  // --- End Form Fields ---

  bool _isSaving = false;

  bool get isEditMode => widget.transactionToEdit != null;

  late TransactionType transactionType;

  @override
  void initState() {
    super.initState();

    if (widget.transactionToEdit != null) {
      transactionType = widget.transactionToEdit!.type;
    } else if (widget.mode != null) {
      transactionType = widget.mode!;
    } else {
      final defaultTypeStr =
          appStateSettings[SettingKey.defaultTransactionType];

      if (defaultTypeStr != null) {
        transactionType =
            TransactionType.values.firstWhereOrNull(
              (e) => e.name == defaultTypeStr,
            ) ??
            TransactionType.expense;
      } else {
        transactionType = TransactionType.expense;
      }
    }

    _tabController = TabController(
      length: 3,
      initialIndex: transactionType.index,
      vsync: this,
    );

    _tabController.addListener(_onTabSelectionChanged);

    // Load the user's preferred currency code for FX selector logic
    CurrencyService.instance.ensureAndGetPreferredCurrency().first.then((
      currency,
    ) {
      if (mounted) {
        setState(() => _preferredCurrencyCode = currency.code);
      }
    });

    if (widget.transactionToEdit != null) {
      _fillForm(widget.transactionToEdit!);
      return;
    }

    if (widget.receiptPrefill != null) {
      _initializeFromReceipt(widget.receiptPrefill!);
      return;
    }

    if (widget.voicePrefill != null) {
      _initializeFromReceipt(widget.voicePrefill!, fromVoice: true);
      return;
    }

    _initializeFormValues();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _onTabSelectionChanged() {
    transactionType = TransactionType.values.elementAt(_tabController.index);

    // Function to execute when the transaction mode change:
    if (transactionType.isTransfer && transactionValue.isNegative) {
      transactionValue = transactionValue * -1;
    }

    if (selectedCategory != null &&
        !transactionType.isTransfer &&
        !selectedCategory!.type.matchWithTransactionType(transactionType)) {
      // Unselect the selected category if the transactionType don't match
      selectedCategory = null;
    }

    setState(() {});
  }

  /// Set default values when opening the form (in create mode)
  Future<void> _initializeFormValues() async {
    final settings = await DefaultTransactionValuesService.instance
        .getAllSettings()
        .first;
    final lastTr = DefaultTransactionValuesService.lastCreatedTransaction.value;

    bool useLast(TransactionFormField f) =>
        settings.lastUsedFields.contains(f) && lastTr != null;

    // 1. Account
    if (widget.fromAccount != null) {
      fromAccount = widget.fromAccount;
    } else if (useLast(TransactionFormField.account)) {
      final acc = await AccountService.instance
          .getAccountById(lastTr!.transaction.accountID)
          .first;
      if (acc != null) fromAccount = acc;
    }

    // If still null (or not using last), use default logic (first available account)
    if (fromAccount == null) {
      final accounts = await AccountService.instance
          .getAccounts(
            predicate: (acc, curr) => buildDriftExpr([
              acc.type.equalsValue(AccountType.saving).not(),
              acc.closingDate.isNull(),
            ]),
            limit: transactionType.isTransfer ? 2 : 1,
          )
          .first;

      if (accounts.isNotEmpty) {
        fromAccount = accounts[0];
        if (transactionType.isTransfer && accounts.length > 1) {
          transferAccount = accounts[1];
        }
      }
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _displayAmountModal(context);
    });

    // 2. Category
    String? categoryIdToLoad;
    if (useLast(TransactionFormField.category)) {
      categoryIdToLoad = lastTr!.transaction.categoryID;
    } else {
      categoryIdToLoad = settings.values.categoryId;
    }

    if (categoryIdToLoad != null) {
      selectedCategory = await CategoryService.instance
          .getCategoryById(categoryIdToLoad)
          .first;
      // category loaded
    }

    // 3. Status
    if (useLast(TransactionFormField.status)) {
      status = lastTr!.transaction.status;
    } else {
      status = settings.values.status;
    }

    // 4. Tags
    List<String>? tagIdsToLoad;
    if (useLast(TransactionFormField.tags)) {
      tagIdsToLoad = lastTr!.tagIds;
    } else {
      tagIdsToLoad = settings.values.tagIds;
    }

    if (tagIdsToLoad != null && tagIdsToLoad.isNotEmpty) {
      tags = await TagService.instance
          .getTags(filter: (t) => t.id.isIn(tagIdsToLoad!))
          .first;
    }

    // 5. Date
    if (useLast(TransactionFormField.date)) {
      date = lastTr!.transaction.date;
    }

    // 6. Note
    if (useLast(TransactionFormField.note)) {
      notesController.text = lastTr!.transaction.notes ?? '';
    }

    setState(() {});
  }

  void submitForm() {
    if (_isSaving) return; // Prevent duplicate submissions

    final t = Translations.of(context);

    // Defense-in-depth for the XOR CHECK constraint on `transactions`
    // (categoryID vs receivingAccountID). The receipt OCR path always assigns
    // a fallback category, but manual edits could still clear it.
    if (transactionType.isIncomeOrExpense && selectedCategory == null) {
      _shakeKey.currentState?.shake();
      WallexSnackbar.warning(
        SnackbarParams(t.transaction.form.validators.category_required),
      );
      return;
    }

    if (transactionType.isTransfer && transferAccount == null) {
      _shakeKey.currentState?.shake();
      return;
    }

    if (transactionValue == 0) {
      WallexSnackbar.warning(
        SnackbarParams(t.transaction.form.validators.zero),
      );

      return;
    }

    if (transactionValue < 0 && transactionType.isTransfer) {
      WallexSnackbar.warning(
        SnackbarParams(t.transaction.form.validators.negative_transfer),
      );

      return;
    }

    if (fromAccount != null && fromAccount!.date.compareTo(date) > 0) {
      WallexSnackbar.warning(
        SnackbarParams(
          t.transaction.form.validators.date_after_account_creation,
        ),
      );

      return;
    }

    setState(() => _isSaving = true);

    final newTrID = widget.transactionToEdit?.id ?? generateUUID();

    // Determine effective exchange rate and source.
    // If the user manually edited the destination amount, the effective rate
    // is valueInDestiny / transactionValue and the source is 'manual'.
    double? effectiveExchangeRate = _showExchangeRateSelector
        ? _selectedExchangeRate
        : null;
    String? effectiveExchangeSource = _showExchangeRateSelector
        ? _selectedExchangeSource
        : null;

    if (_destinyManuallyOverridden &&
        valueInDestinyToNumber != null &&
        transactionValue > 0) {
      effectiveExchangeRate = valueInDestinyToNumber! / transactionValue;
      effectiveExchangeSource = 'manual';
    }

    final transactionToPost = TransactionInDB(
      id: newTrID,
      date: date,
      type: transactionType,
      accountID: fromAccount!.id,
      value: transactionType == TransactionType.expense
          ? transactionValue * -1
          : transactionValue,
      isHidden: false,
      status: date.compareTo(DateTime.now()) > 0
          ? TransactionStatus.pending
          : (status ??
                TransactionStatus.reconciled), // Default to reconciled if null
      notes: notesController.text.isEmpty ? null : notesController.text,
      title: titleController.text.isEmpty ? null : titleController.text,
      intervalEach: recurrentRule.intervalEach,
      intervalPeriod: recurrentRule.intervalPeriod,
      endDate: recurrentRule.ruleRecurrentLimit?.endDate,
      remainingTransactions:
          recurrentRule.ruleRecurrentLimit?.remainingIterations,
      valueInDestiny: transactionType.isTransfer
          ? valueInDestinyToNumber
          : null,
      categoryID: transactionType.isIncomeOrExpense
          ? selectedCategory?.id
          : null,
      receivingAccountID: transactionType.isTransfer
          ? transferAccount?.id
          : null,
      exchangeRateApplied: effectiveExchangeRate,
      exchangeRateSource: effectiveExchangeSource,
      debtId: widget.linkedDebt?.id,
      createdAt: DateTime.now(),
    );

    Future<int> postCall;

    if (isEditMode) {
      postCall = TransactionService.instance.updateTransaction(
        transactionToPost,
      );
    } else {
      postCall = TransactionService.instance.insertTransaction(
        transactionToPost,
      );
    }

    postCall
        .then((value) async {
          final db = AppDB.instance;

          final existingTags = widget.transactionToEdit?.tags ?? [];

          // Tags to remove: present in the current transaction but not in the new tags list
          final tagsToRemove = existingTags
              .where(
                (existingTag) =>
                    !tags.any((newTag) => newTag.id == existingTag.id),
              )
              .toList();

          // Tags to add: present in the new tags list but not in the current transaction
          final tagsToAdd = tags
              .where(
                (newTag) => !existingTags.any(
                  (existingTag) => existingTag.id == newTag.id,
                ),
              )
              .toList();

          try {
            // Remove tags
            for (final tag in tagsToRemove) {
              await (db.delete(db.transactionTags)..where(
                    (tbl) =>
                        tbl.tagID.isValue(tag.id) &
                        tbl.transactionID.isValue(newTrID),
                  ))
                  .go();
            }

            // Add new tags
            await TagService.instance.linkTagsToTransaction(
              transactionId: newTrID,
              tagIds: tagsToAdd.map((t) => t.id).toList(),
            );

            final pendingPath = widget.pendingAttachmentPath;
            if (!isEditMode && pendingPath != null && pendingPath.isNotEmpty) {
              final pendingFile = File(pendingPath);
              if (pendingFile.existsSync()) {
                await AttachmentsService.instance.attach(
                  ownerType: AttachmentOwnerType.transaction,
                  ownerId: newTrID,
                  sourceFile: pendingFile,
                  role: 'receipt',
                );
                try {
                  pendingFile.deleteSync();
                } on FileSystemException {
                  // Ignore cleanup races; attachment was already persisted.
                }
              }
            }

            DefaultTransactionValuesService.lastCreatedTransaction.value = (
              transaction: transactionToPost,
              tagIds: tags.map((t) => t.id).toList(),
            );

            // Show success message FIRST
            WallexSnackbar.success(
              SnackbarParams(
                isEditMode
                    ? t.transaction.edit_success
                    : t.transaction.new_success,
              ),
            );

            // Delay to show Snackbar, then navigate
            await Future.delayed(const Duration(milliseconds: 800));
            RouteUtils.popRoute();
          } catch (error) {
            if (mounted) {
              setState(() => _isSaving = false);
              RouteUtils.popRoute();
            }
            WallexSnackbar.error(SnackbarParams.fromError(error));
          }
        })
        .catchError((error) {
          if (mounted) setState(() => _isSaving = false);
          WallexSnackbar.error(SnackbarParams.fromError(error));
        });
  }

  Future<void> _initializeFromReceipt(
    TransactionProposal prefill, {
    bool fromVoice = false,
  }) async {
    transactionType = prefill.type;
    _tabController.animateTo(transactionType.index);

    transactionValue = prefill.amount.abs();
    // Defense-in-depth vs. LLM-hallucinated stale dates reaching the full
    // form on the voice flow: if the proposal date is clearly stale (>7
    // days old) treat it as missing and default to now. Receipts can
    // legitimately have old dates (scanning an old invoice) so we only
    // apply this guard when the prefill came from voice capture.
    final nowTs = DateTime.now();
    final proposalDate = prefill.date;
    if (fromVoice &&
        proposalDate.isBefore(nowTs.subtract(const Duration(days: 7)))) {
      date = nowTs;
    } else {
      date = proposalDate;
    }
    notesController.text = prefill.rawText;
    titleController.text = prefill.counterpartyName ?? '';

    if (prefill.accountId != null) {
      fromAccount = await AccountService.instance
          .getAccountById(prefill.accountId!)
          .first;
    }

    // If still null (or account was deleted/archived), fall back to the first
    // available non-saving, non-archived account.
    if (fromAccount == null) {
      final accounts = await AccountService.instance
          .getAccounts(
            predicate: (acc, curr) => buildDriftExpr([
              acc.type.equalsValue(AccountType.saving).not(),
              acc.closingDate.isNull(),
            ]),
            limit: 1,
          )
          .first;

      if (accounts.isNotEmpty) {
        fromAccount = accounts[0];
      }
    }

    if (prefill.proposedCategoryId != null &&
        transactionType.isIncomeOrExpense) {
      selectedCategory = await CategoryService.instance
          .getCategoryById(prefill.proposedCategoryId!)
          .first;
    }

    setState(() {});
  }

  Future<List<Account>?> showAccountSelector(Account? account) {
    return showAccountSelectorBottomSheet(
      context,
      AccountSelectorModal(
        allowMultiSelection: false,
        filterSavingAccounts: transactionType.isIncomeOrExpense,
        includeArchivedAccounts: false,
        selectedAccounts: [?account],
      ),
    );
  }

  Future<void> selectCategory() async {
    final modalRes = await showCategoryPickerModal(
      context,
      modal: CategoryPicker(
        selectedCategory: selectedCategory,
        categoryType: transactionType == TransactionType.expense
            ? [CategoryType.E, CategoryType.B]
            : [CategoryType.I, CategoryType.B],
      ),
    );

    if (modalRes != null) {
      setState(() {
        selectedCategory = modalRes;
      });
    }
  }

  Future<void> _fillForm(MoneyTransaction transaction) async {
    fromAccount = transaction.account;
    transferAccount = transaction.receivingAccount;
    date = transaction.date;
    status = transaction.status;
    selectedCategory = transaction.category;
    recurrentRule = transaction.recurrentInfo;
    tags = [...transaction.tags];

    notesController.text = transaction.notes ?? '';
    titleController.text = transaction.title ?? '';
    transactionValue = transaction.value;
    transactionType = transaction.type;

    if (transactionType == TransactionType.expense) {
      transactionValue = transactionValue * -1;
    }

    valueInDestinyController.text =
        transaction.valueInDestiny?.abs().toString() ?? '';

    // Restore FX fields for editing
    _selectedExchangeRate = transaction.exchangeRateApplied;
    _selectedExchangeSource = transaction.exchangeRateSource;

    // If editing a TX that already had a destination amount, mark as manually
    // overridden so the exchange rate selector won't overwrite it.
    if (transaction.valueInDestiny != null) {
      _destinyManuallyOverridden = true;
    }

    setState(() {});
  }

  Color get foregroundColor {
    return transactionType.color(context).getContrastColor();
  }

  Widget _buildHeader(BuildContext context) {
    final t = Translations.of(context);
    return Column(
      children: [
        TransactionAmountDisplay(
          transactionType: transactionType,
          transactionValue: transactionValue,
          fromAccount: fromAccount,
          onTap: () {
            showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              showDragHandle: true,
              builder: (context) => AmountSelector(
                title: t.transaction.form.value,
                initialAmount: transactionValue,
                enableSignToggleButton: transactionType.isIncomeOrExpense,
                currency: fromAccount?.currency,
                onSubmit: (amount) {
                  setState(() {
                    transactionValue = amount;
                    RouteUtils.popRoute();
                  });
                },
              ),
            );
          },
        ),
        TransactionAccountSelectorRow(
          transactionType: transactionType,
          fromAccount: fromAccount,
          transferAccount: transferAccount,
          selectedCategory: selectedCategory,
          shakeKey: _shakeKey,
          onFromAccountTap: () async {
            final modalRes = await showAccountSelector(fromAccount!);
            if (modalRes != null && modalRes.isNotEmpty) {
              setState(() {
                fromAccount = modalRes.first;
              });
            }
          },
          onTransferAccountTap: () async {
            final modalRes = await showAccountSelector(transferAccount);
            if (modalRes != null && modalRes.isNotEmpty) {
              setState(() {
                transferAccount = modalRes.first;
              });
            }
          },
          onCategoryTap: () => selectCategory(),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);

    final formFieldWithDividers = [
      TransactionTitleField(controller: titleController),
      const Divider(),
      TransactionDateSelector(
        date: date,
        fromAccount: fromAccount,
        onDateChanged: (newDate) => setState(() => date = newDate),
      ),
      const Divider(),
      TransactionRecurrencySelector(
        recurrentRule: recurrentRule,
        onRecurrencyChanged: (newRule) =>
            setState(() => recurrentRule = newRule),
      ),
      const Divider(),
      TransactionStatusSelector(
        date: date,
        status: status,
        onStatusChanged: (newStatus) => setState(() => status = newStatus),
      ),
      const Divider(),
      TransactionTagsSelector(
        tags: tags,
        onTagsChanged: (newTags) => setState(() => tags = newTags),
      ),
      const Divider(),
      if (_isCrossCurrencyTransfer) ...[
        TransactionValueInDestinyField(
          controller: valueInDestinyController,
          transferAccount: transferAccount,
          onChanged: () {
            setState(() {
              _destinyManuallyOverridden = true;
            });
          },
        ),
        const Divider(),
      ],
      if (_showExchangeRateSelector) ...[
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: ExchangeRateSelector(
            fromCurrency: transactionType.isTransfer
                ? (fromAccount?.currency.code ?? 'USD')
                : (fromAccount?.currency.code ?? 'USD'),
            toCurrency: transactionType.isTransfer
                ? (transferAccount?.currency.code ??
                      _preferredCurrencyCode ??
                      'VES')
                : (_preferredCurrencyCode ?? 'VES'),
            initialRate: _selectedExchangeRate,
            initialSource: _selectedExchangeSource,
            onChanged: (rate, source) {
              _selectedExchangeRate = rate;
              _selectedExchangeSource = source;
              // Auto-fill valueInDestiny when not manually overridden
              if (_isCrossCurrencyTransfer && !_destinyManuallyOverridden) {
                final computed = transactionValue * rate;
                valueInDestinyController.text = computed.toStringAsFixed(2);
              }
            },
          ),
        ),
        const Divider(),
      ],
      TransactionDescriptionField(controller: notesController),
      const Divider(),
    ];

    return SafeArea(
      bottom: false,
      left: false,
      right: false,
      top: BreakPoint.of(context).isLargerOrEqualTo(BreakpointID.md),
      child: PageFramework(
        title: isEditMode
            ? t.transaction.edit
            : transactionType == TransactionType.transfer
            ? t.transfer.create
            : transactionType == TransactionType.expense
            ? t.transaction.new_expense
            : t.transaction.new_income,
        appBarBackgroundColor: transactionType
            .color(context)
            .withValues(alpha: 0.85),
        appBarForegroundColor: foregroundColor,
        tabBar: TabBar(
          indicatorColor: foregroundColor,
          labelColor: foregroundColor,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold),
          unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.normal),
          unselectedLabelColor: foregroundColor.withValues(alpha: 0.8),
          tabAlignment: TabAlignment.fill,
          dividerColor: transactionType.color(context).darken(0.3),
          controller: _tabController,
          tabs: TransactionType.values
              .map((tType) => Tab(text: tType.displayName(context)))
              .toList(),
          isScrollable: false,
        ),
        persistentFooterButtons: [
          PersistentFooterButton(
            child: FilledButton.icon(
              key: const ValueKey('transaction_form_save_button'),
              onPressed: _isSaving || fromAccount == null
                  ? null
                  : () {
                      if (_formKey.currentState!.validate()) {
                        _formKey.currentState!.save();

                        submitForm();
                      } else {
                        WallexSnackbar.error(
                          SnackbarParams(t.general.validations.form_error),
                        );
                      }
                    },
              icon: _isSaving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save),
              label: Text(
                _isSaving
                    ? 'Guardando...'
                    : (isEditMode ? t.transaction.edit : t.transaction.create),
              ),
            ),
          ),
        ],
        body: Form(
          key: _formKey,
          child: BreakpointContainer(
            mdChild: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(children: [_buildHeader(context)]),
                  ),
                ),
                const VerticalDivider(thickness: 2),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 0,
                      vertical: 16,
                    ),
                    child: Column(children: formFieldWithDividers),
                  ),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildHeader(context),
                if (widget.linkedDebt != null)
                  DebtLinkBanner(debt: widget.linkedDebt!),
                //   const Divider(),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.only(top: 4, bottom: 12),
                    child: Column(children: formFieldWithDividers),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _displayAmountModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => AmountSelector(
        title: t.transaction.form.value,
        initialAmount: transactionValue,
        enableSignToggleButton: transactionType.isIncomeOrExpense,
        currency: fromAccount?.currency,
        onSubmit: (amount) {
          setState(() {
            transactionValue = amount;
            RouteUtils.popRoute();
          });
        },
      ),
    );
  }
}
