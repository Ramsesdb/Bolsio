import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:kilatex/app/accounts/account_selector.dart';
import 'package:kilatex/app/categories/selectors/category_picker.dart';
import 'package:kilatex/app/transactions/auto_import/widgets/proposal_origin_chip.dart';
import 'package:kilatex/app/transactions/auto_import/widgets/proposal_status_chip.dart';
import 'package:kilatex/core/database/app_db.dart';
import 'package:kilatex/core/database/services/account/account_service.dart';
import 'package:kilatex/core/database/services/category/category_service.dart';
import 'package:kilatex/core/database/services/pending_import/pending_import_service.dart';
import 'package:kilatex/core/database/services/transaction/transaction_service.dart';
import 'package:kilatex/core/models/account/account.dart';
import 'package:kilatex/core/models/auto_import/transaction_proposal_status.dart';
import 'package:kilatex/core/models/category/category.dart';
import 'package:kilatex/core/models/transaction/transaction_status.enum.dart';
import 'package:kilatex/core/models/transaction/transaction_type.enum.dart';
import 'package:kilatex/core/utils/uuid.dart';

/// Review page for a single pending import proposal.
///
/// Pre-fills a form with the captured data and allows the user to
/// edit, confirm (creating a real transaction), reject, or postpone.
class ProposalReviewPage extends StatefulWidget {
  const ProposalReviewPage({super.key, required this.pendingImport});

  final PendingImportInDB pendingImport;

  @override
  State<ProposalReviewPage> createState() => _ProposalReviewPageState();
}

class _ProposalReviewPageState extends State<ProposalReviewPage> {
  final _formKey = GlobalKey<FormState>();

  late TransactionType _type;
  late TextEditingController _amountController;
  late TextEditingController _counterpartyController;
  late TextEditingController _notesController;
  late String _currencyId;
  late DateTime _date;
  Account? _selectedAccount;
  Category? _selectedCategory;
  bool _categoryIsAiSuggested = false;
  bool _isSaving = false;
  Account? _selectedTransferAccount;
  late TextEditingController _valueInDestinyController;

  @override
  void initState() {
    super.initState();
    final pi = widget.pendingImport;

    _type = pi.type == 'T'
        ? TransactionType.transfer
        : pi.type == 'I'
            ? TransactionType.income
            : TransactionType.expense;
    _amountController =
        TextEditingController(text: pi.amount.toStringAsFixed(2));
    _counterpartyController =
        TextEditingController(text: pi.counterpartyName ?? '');
    _currencyId = pi.currencyId;
    _date = pi.date;

    // Handle transfer type from pending import
    if (pi.type == 'T') {
      _type = TransactionType.transfer;
      if (pi.receivingAccountId != null) {
        _resolveTransferAccount(pi.receivingAccountId!);
      }
      if (pi.valueInDestiny != null) {
        _valueInDestinyController = TextEditingController(
          text: pi.valueInDestiny!.toStringAsFixed(2),
        );
      } else {
        _valueInDestinyController = TextEditingController(
          text: pi.amount.toStringAsFixed(2),
        );
      }
    } else {
      _valueInDestinyController = TextEditingController(
        text: pi.amount.toStringAsFixed(2),
      );
    }

    // Build auto-populated notes
    final channelTag = pi.channel;
    final bankTag = _bankTagFromSender(pi.sender);
    final refTag = pi.bankRef ?? '-';
    _notesController = TextEditingController(
      text: '[auto:$channelTag:$bankTag] ref=$refTag',
    );

    // Resolve the account if accountId is present
    if (pi.accountId != null) {
      _resolveAccount(pi.accountId!);
    } else {
      _resolveOrCreateSuggestedAccount();
    }

    _resolveInitialCategorySuggestion();
  }

  String _bankTagFromSender(String? sender) {
    if (sender == null) return 'unknown';
    if (sender.contains('bdv') || sender == '2661') return 'bdv';
    if (sender.contains('binance')) return 'binance';
    if (sender.contains('zinli')) return 'zinli';
    return sender;
  }

  Future<void> _resolveAccount(String accountId) async {
    final accounts = await AccountService.instance.getAccounts().first;
    final match = accounts.where((a) => a.id == accountId).toList();
    if (match.isNotEmpty && mounted) {
      setState(() {
        _selectedAccount = match.first;
      });

      final sender = (widget.pendingImport.sender ?? '').toLowerCase();
      final isBdv = sender.contains('bdv') || sender == '2661' || sender == '2662';
      final selectedCurrency = match.first.currency.code.toUpperCase();
      if (isBdv && selectedCurrency != _currencyId.toUpperCase()) {
        await _resolveOrCreateSuggestedAccount();
      }
    }
  }

  Future<void> _resolveTransferAccount(String accountId) async {
    final accounts = await AccountService.instance.getAccounts().first;
    final match = accounts.where((a) => a.id == accountId).toList();
    if (match.isNotEmpty && mounted) {
      setState(() => _selectedTransferAccount = match.first);
    }
  }

  Future<void> _resolveOrCreateSuggestedAccount() async {
    final pi = widget.pendingImport;
    final sender = (pi.sender ?? '').toLowerCase();
    final isBdv = sender.contains('bdv') || sender == '2661' || sender == '2662';
    if (!isBdv) return;

    final currency = _currencyId.toUpperCase();
    if (currency != 'USD' && currency != 'VES') return;

    final accounts = await AccountService.instance.getAccounts().first;

    Account? match = accounts.where((a) {
      final name = a.name.toLowerCase();
      return name.startsWith('banco de venezuela') &&
          a.currency.code.toUpperCase() == currency;
    }).firstOrNull;

    if (match == null) {
      final nextOrder = accounts.isEmpty
          ? 1
          : (accounts.map((a) => a.displayOrder).reduce((a, b) => a > b ? a : b) + 1);

      final accountName = currency == 'VES'
          ? 'Banco de Venezuela'
          : 'Banco de Venezuela $currency';

      final newAccount = AccountInDB(
        id: generateUUID(),
        name: accountName,
        displayOrder: nextOrder,
        type: AccountType.normal,
        currencyId: currency,
        iniValue: 0,
        date: DateTime.now(),
        iconId: 'account_balance',
        color: '1A237E',
      );

      await AccountService.instance.insertAccount(newAccount);

      final refreshed = await AccountService.instance.getAccounts().first;
      match = refreshed.where((a) => a.id == newAccount.id).firstOrNull;
    }

    if (match != null && mounted) {
      setState(() => _selectedAccount = match);
    }
  }

  Future<void> _resolveInitialCategorySuggestion() async {
    final pi = widget.pendingImport;

    if (pi.proposedCategoryId != null) {
      final proposed = await CategoryService.instance
          .getCategoryById(pi.proposedCategoryId!)
          .first;
      if (proposed != null && mounted) {
        setState(() {
          _selectedCategory = proposed;
          _categoryIsAiSuggested = true;
        });
      }
      return;
    }

    final raw = pi.rawText.toLowerCase();
    final sender = (pi.sender ?? '').toLowerCase();
    final counterparty = (pi.counterpartyName ?? '').toLowerCase();
    final isBdv = sender.contains('bdv') || sender == '2661' || sender == '2662';
    final looksLikeBinanceTransfer =
        raw.contains('binance') || sender.contains('binance') || counterparty.contains('binance');
    final looksLikeBdvUsdSavingMove = isBdv &&
      _currencyId.toUpperCase() == 'USD' &&
      _type == TransactionType.expense;

    if (_type != TransactionType.expense ||
      (!looksLikeBinanceTransfer && !looksLikeBdvUsdSavingMove)) {
      return;
    }

    final ahorroCategory = await _findOrCreateSavingsCategory();

    if (ahorroCategory != null && mounted) {
      setState(() {
        _selectedCategory = ahorroCategory;
        _categoryIsAiSuggested = false;
      });
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    _counterpartyController.dispose();
    _notesController.dispose();
    _valueInDestinyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pi = widget.pendingImport;
    final status = TransactionProposalStatus.fromDbValue(pi.status);
    final isDuplicate = status == TransactionProposalStatus.duplicate;
    final isReviewable = status == TransactionProposalStatus.pending ||
        status == TransactionProposalStatus.duplicate;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Revisar propuesta'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Duplicate warning banner
            if (isDuplicate)
              Card(
                color: Colors.amber.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Icon(Icons.warning_amber_rounded,
                          color: Colors.amber.shade800),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Posible duplicado -- puede que ya hayas registrado '
                          'esta operacion manualmente. Revisa y decide.',
                          style: TextStyle(
                            color: Colors.amber.shade900,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (isDuplicate) const SizedBox(height: 12),

            // Origin chip + status chip
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ProposalOriginChip(
                  channel: pi.channel,
                  sender: pi.sender,
                ),
                ProposalStatusChip(status: status),
              ],
            ),
            const SizedBox(height: 20),

            // Account selector
            Text(
              'Cuenta origen *',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 8),
            InkWell(
              onTap: isReviewable ? _selectAccount : null,
              borderRadius: BorderRadius.circular(8),
              child: InputDecorator(
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                  suffixIcon:
                      isReviewable ? const Icon(Icons.arrow_drop_down) : null,
                ),
                child: Text(
                  _selectedAccount?.name ?? 'Seleccionar cuenta',
                  style: TextStyle(
                    color: _selectedAccount != null
                        ? null
                        : Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.5),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Type toggle
            Text(
              'Tipo de transaccion',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 8),
            SegmentedButton<TransactionType>(
              segments: const [
                ButtonSegment(
                  value: TransactionType.income,
                  label: Text('Ingreso'),
                  icon: Icon(Icons.south_east_rounded),
                ),
                ButtonSegment(
                  value: TransactionType.expense,
                  label: Text('Gasto'),
                  icon: Icon(Icons.north_east_rounded),
                ),
                ButtonSegment(
                  value: TransactionType.transfer,
                  label: Text('Transfer.'),
                  icon: Icon(Icons.swap_horiz),
                ),
              ],
              selected: {_type},
              onSelectionChanged: isReviewable
                  ? (selected) {
                      final newType = selected.first;
                      setState(() {
                        // When switching to transfer: if the current account
                        // looks like the destination (e.g. Binance income),
                        // move it to destination and clear origin so the user
                        // picks the real source account.
                        if (newType == TransactionType.transfer &&
                            _type != TransactionType.transfer &&
                            _selectedAccount != null &&
                            _selectedTransferAccount == null) {
                          final wasIncome = _type == TransactionType.income;
                          if (wasIncome) {
                            _selectedTransferAccount = _selectedAccount;
                            _selectedAccount = null;
                          }
                        }
                        _type = newType;
                      });
                    }
                  : null,
            ),
            const SizedBox(height: 16),

            // Amount + currency
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _amountController,
                    readOnly: !isReviewable,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Monto',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Requerido';
                      }
                      final parsed = double.tryParse(value);
                      if (parsed == null || parsed <= 0) {
                        return 'Monto invalido';
                      }
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 110,
                  child: DropdownButtonFormField<String>(
                    // ignore: deprecated_member_use
                    value: _currencyId,
                    isExpanded: true,
                    items: const [
                      DropdownMenuItem(value: 'VES', child: Text('VES')),
                      DropdownMenuItem(value: 'USD', child: Text('USD')),
                      DropdownMenuItem(value: 'USDT', child: Text('USDT')),
                    ],
                    onChanged: isReviewable
                        ? (v) {
                            if (v != null) setState(() => _currencyId = v);
                          }
                        : null,
                    decoration: const InputDecoration(
                      labelText: 'Moneda',
                      border: OutlineInputBorder(),
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 8, vertical: 14),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Date + time picker
            Text(
              'Fecha y hora',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 8),
            InkWell(
              onTap: isReviewable ? _selectDateTime : null,
              borderRadius: BorderRadius.circular(8),
              child: InputDecorator(
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  suffixIcon: Icon(Icons.calendar_today),
                ),
                child: Text(
                  DateFormat('dd/MM/yyyy HH:mm').format(_date),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Transfer destination account (only shown for transfers)
            if (_type == TransactionType.transfer) ...[
              Text(
                'Cuenta destino *',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 8),
              InkWell(
                onTap: isReviewable ? _selectTransferAccount : null,
                borderRadius: BorderRadius.circular(8),
                child: InputDecorator(
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                    suffixIcon:
                        isReviewable ? const Icon(Icons.arrow_drop_down) : null,
                  ),
                  child: Text(
                    _selectedTransferAccount?.name ?? 'Seleccionar cuenta destino',
                    style: TextStyle(
                      color: _selectedTransferAccount != null
                          ? null
                          : Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.5),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Amount received at destination
              TextFormField(
                controller: _valueInDestinyController,
                readOnly: !isReviewable,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Monto recibido (neto)',
                  helperText: 'Monto que llega a la cuenta destino (sin comision)',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (_type != TransactionType.transfer) return null;
                  if (value == null || value.isEmpty) return 'Requerido';
                  final parsed = double.tryParse(value);
                  if (parsed == null || parsed <= 0) return 'Monto invalido';
                  return null;
                },
              ),
              const SizedBox(height: 16),
            ],

            // Category selector (hidden for transfers)
            if (_type != TransactionType.transfer) ...[
              Row(
                children: [
                  Text(
                    'Categoria (opcional)',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  if (_categoryIsAiSuggested) ...[
                    const SizedBox(width: 8),
                    Icon(
                      Icons.auto_awesome,
                      size: 16,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 8),
              InkWell(
                onTap: isReviewable ? _selectCategory : null,
                borderRadius: BorderRadius.circular(8),
                child: InputDecorator(
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                    suffixIcon:
                        isReviewable ? const Icon(Icons.arrow_drop_down) : null,
                  ),
                  child: Text(
                    _selectedCategory?.name ?? 'Sin categoria',
                    style: TextStyle(
                      color: _selectedCategory != null
                          ? null
                          : Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.5),
                    ),
                  ),
                ),
              ),
              if (_categoryIsAiSuggested && isReviewable) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    TextButton.icon(
                      onPressed: () {
                        setState(() => _categoryIsAiSuggested = false);
                      },
                      icon: const Icon(Icons.check, size: 18),
                      label: const Text('Aceptar sugerencia'),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: () async {
                        await _selectCategory();
                        if (!mounted) return;
                        setState(() => _categoryIsAiSuggested = false);
                      },
                      icon: const Icon(Icons.edit, size: 18),
                      label: const Text('Cambiar'),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 16),
            ],

            // Counterparty
            TextFormField(
              controller: _counterpartyController,
              readOnly: !isReviewable,
              decoration: const InputDecoration(
                labelText: 'Contraparte',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),

            // Notes
            TextFormField(
              controller: _notesController,
              readOnly: !isReviewable,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Notas',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),

            // Collapsible raw text section
            ExpansionTile(
              title: const Text('Ver texto original capturado'),
              tilePadding: EdgeInsets.zero,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SelectableText(
                    pi.rawText,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Action buttons
            if (isReviewable) ...[
              FilledButton.icon(
                onPressed: _isSaving ? null : _confirmAndSave,
                icon: const Icon(Icons.check),
                label: const Text('Confirmar y guardar'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _isSaving ? null : _reject,
                icon: const Icon(Icons.block),
                label: const Text('Rechazar'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red,
                  minimumSize: const Size.fromHeight(48),
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _isSaving ? null : () => Navigator.pop(context),
                child: const Text('Posponer'),
              ),
            ],
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Future<void> _selectAccount() async {
    final result = await showAccountSelectorBottomSheet(
      context,
      AccountSelectorModal(
        allowMultiSelection: false,
        filterSavingAccounts: false,
        currencyCode: _currencyId,
      ),
    );
    if (result != null && result.isNotEmpty && mounted) {
      setState(() => _selectedAccount = result.first);
    }
  }

  Future<void> _selectTransferAccount() async {
    final result = await showAccountSelectorBottomSheet(
      context,
      AccountSelectorModal(
        allowMultiSelection: false,
        filterSavingAccounts: false,
      ),
    );
    if (result != null && result.isNotEmpty && mounted) {
      setState(() => _selectedTransferAccount = result.first);
    }
  }

  Future<void> _selectCategory() async {
    final categoryTypes = _type == TransactionType.income
        ? [CategoryType.I, CategoryType.B]
        : [CategoryType.E, CategoryType.B];

    final result = await showCategoryPickerModal(
      context,
      modal: CategoryPicker(
        selectedCategory: _selectedCategory,
        categoryType: categoryTypes,
      ),
    );
    if (result != null && mounted) {
      setState(() {
        _selectedCategory = result;
        _categoryIsAiSuggested = false;
      });
    }
  }

  Future<void> _selectDateTime() async {
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (pickedDate == null || !mounted) return;

    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_date),
    );
    if (pickedTime == null || !mounted) return;

    setState(() {
      _date = DateTime(
        pickedDate.year,
        pickedDate.month,
        pickedDate.day,
        pickedTime.hour,
        pickedTime.minute,
      );
    });
  }

  Future<void> _confirmAndSave() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedAccount == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecciona una cuenta')),
      );
      return;
    }

    // Binance double-count check (applies to all types)
    final sender = (widget.pendingImport.sender ?? '').toLowerCase();
    if (sender.startsWith('binance:') && _selectedAccount != null) {
      final countRow = await AppDB.instance.customSelect(
        '''
        SELECT COUNT(1) AS txCount
        FROM transactions
        WHERE accountID = ? OR receivingAccountID = ?
        ''',
        variables: [
          Variable.withString(_selectedAccount!.id),
          Variable.withString(_selectedAccount!.id),
        ],
        readsFrom: {AppDB.instance.transactions},
      ).getSingle();

      final txCount = (countRow.data['txCount'] as int?) ?? 0;
      final isBinanceBalanceMode =
          _selectedAccount!.name.toLowerCase().contains('binance') &&
          _selectedAccount!.currency.code.toUpperCase() == 'USD' &&
          txCount == 0;

      if (isBinanceBalanceMode) {
        await PendingImportService.instance.updatePendingImportStatus(
          widget.pendingImport.id,
          TransactionProposalStatus.rejected,
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Movimiento Binance omitido para evitar doble conteo (saldo ya sincronizado por API).',
              ),
            ),
          );
          Navigator.pop(context, true);
        }
        return;
      }
    }

    setState(() => _isSaving = true);

    try {
      final amount = double.parse(_amountController.text);

      if (_type == TransactionType.transfer) {
        // Transfer: no category, requires destination account
        if (_selectedTransferAccount == null) {
          if (mounted) {
            setState(() => _isSaving = false);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Selecciona una cuenta destino')),
            );
          }
          return;
        }

        final valueInDestiny = double.tryParse(_valueInDestinyController.text);

        final newTxId = generateUUID();
        final transaction = TransactionInDB(
          id: newTxId,
          date: _date,
          accountID: _selectedAccount!.id,
          value: amount,
          title: _counterpartyController.text.isNotEmpty
              ? _counterpartyController.text
              : null,
          notes: _notesController.text.isNotEmpty
              ? _notesController.text
              : null,
          type: TransactionType.transfer,
          receivingAccountID: _selectedTransferAccount!.id,
          valueInDestiny: valueInDestiny,
          isHidden: false,
          createdAt: DateTime.now(),
        );

        await AppDB.instance.transaction(() async {
          await TransactionService.instance.insertTransaction(transaction);
          await PendingImportService.instance.updatePendingImportStatus(
            widget.pendingImport.id,
            TransactionProposalStatus.confirmed,
            createdTransactionId: newTxId,
          );
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Transferencia registrada'),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.pop(context, true);
        }
      } else {
        // Income or expense: existing logic
        final value = _type == TransactionType.expense ? -amount : amount;

        Category? effectiveCategory = _selectedCategory;
        if (effectiveCategory == null) {
          effectiveCategory = await _resolveFallbackCategoryForType(_type);
          if (effectiveCategory != null && mounted) {
            setState(() => _selectedCategory = effectiveCategory);
          }
        }

        if (effectiveCategory == null) {
          if (mounted) {
            setState(() => _isSaving = false);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Selecciona una categoria para guardar')),
            );
          }
          return;
        }

        final newTxId = generateUUID();
        final transaction = TransactionInDB(
          id: newTxId,
          date: _date,
          accountID: _selectedAccount!.id,
          value: value,
          title: _counterpartyController.text.isNotEmpty
              ? _counterpartyController.text
              : null,
          notes: _notesController.text.isNotEmpty
              ? _notesController.text
              : null,
          type: _type,
          categoryID: effectiveCategory.id,
          isHidden: false,
          // Always set an explicit status. Leaving it NULL silently excludes
          // the transaction from stats/budgets/goals (SQL `status IN (...)`
          // never matches NULL). Mirrors the convention used by the manual
          // transaction form: pending for future-dated rows, reconciled
          // otherwise.
          status: _date.isAfter(DateTime.now())
              ? TransactionStatus.pending
              : TransactionStatus.reconciled,
          createdAt: DateTime.now(),
        );

        await AppDB.instance.transaction(() async {
          await TransactionService.instance.insertTransaction(transaction);
          await PendingImportService.instance.updatePendingImportStatus(
            widget.pendingImport.id,
            TransactionProposalStatus.confirmed,
            createdTransactionId: newTxId,
          );
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Transaccion registrada'),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.pop(context, true);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al guardar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<Category?> _resolveFallbackCategoryForType(TransactionType type) async {
    final categories = await CategoryService.instance.getCategories().first;

    final normalized = categories.where((category) {
      if (type == TransactionType.income) {
        return category.type == CategoryType.I ||
            category.type == CategoryType.B;
      }

      return category.type == CategoryType.E ||
          category.type == CategoryType.B;
    }).toList();

    if (normalized.isEmpty) return null;

    if (type == TransactionType.expense) {
      final savings = await _findOrCreateSavingsCategory();
      if (savings != null) {
        return savings;
      }
    }

    return normalized.first;
  }

  Future<Category?> _findOrCreateSavingsCategory() async {
    final categories = await CategoryService.instance.getCategories().first;

    for (final category in categories) {
      final name = category.name.toLowerCase();
      final isExpenseLike = category.type == CategoryType.E ||
          category.type == CategoryType.B;
      if (isExpenseLike && (name.contains('ahorro') || name.contains('ahorros'))) {
        return category;
      }
    }

    final maxOrder = categories.isEmpty
        ? 1
        : (categories.map((e) => e.displayOrder).reduce((a, b) => a > b ? a : b) + 1);

    final toInsert = CategoryInDB(
      id: generateUUID(),
      name: 'Ahorros',
      iconId: 'savings',
      color: '0277BD',
      type: CategoryType.E,
      displayOrder: maxOrder,
    );

    await CategoryService.instance.insertCategory(toInsert);

    final refreshed = await CategoryService.instance.getCategories().first;
    return refreshed.where((e) => e.id == toInsert.id).firstOrNull;
  }

  Future<void> _reject() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rechazar propuesta'),
        content: const Text(
          'Rechazar esta propuesta? No se registrara ninguna transaccion.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Rechazar'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    await PendingImportService.instance.updatePendingImportStatus(
      widget.pendingImport.id,
      TransactionProposalStatus.rejected,
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Propuesta rechazada')),
      );
      Navigator.pop(context, true);
    }
  }
}
