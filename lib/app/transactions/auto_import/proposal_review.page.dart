import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:wallex/app/accounts/account_selector.dart';
import 'package:wallex/app/categories/selectors/category_picker.dart';
import 'package:wallex/app/transactions/auto_import/widgets/proposal_origin_chip.dart';
import 'package:wallex/app/transactions/auto_import/widgets/proposal_status_chip.dart';
import 'package:wallex/core/database/app_db.dart';
import 'package:wallex/core/database/services/account/account_service.dart';
import 'package:wallex/core/database/services/pending_import/pending_import_service.dart';
import 'package:wallex/core/database/services/transaction/transaction_service.dart';
import 'package:wallex/core/models/account/account.dart';
import 'package:wallex/core/models/auto_import/transaction_proposal_status.dart';
import 'package:wallex/core/models/category/category.dart';
import 'package:wallex/core/models/transaction/transaction_type.enum.dart';
import 'package:wallex/core/utils/uuid.dart';

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
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final pi = widget.pendingImport;

    _type = pi.type == 'I' ? TransactionType.income : TransactionType.expense;
    _amountController =
        TextEditingController(text: pi.amount.toStringAsFixed(2));
    _counterpartyController =
        TextEditingController(text: pi.counterpartyName ?? '');
    _currencyId = pi.currencyId;
    _date = pi.date;

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
    }
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
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    _counterpartyController.dispose();
    _notesController.dispose();
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
              ],
              selected: {_type},
              onSelectionChanged: isReviewable
                  ? (selected) {
                      setState(() => _type = selected.first);
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

            // Category selector
            Text(
              'Categoria (opcional)',
              style: Theme.of(context).textTheme.labelLarge,
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
            const SizedBox(height: 16),

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
      const AccountSelectorModal(
        allowMultiSelection: false,
        filterSavingAccounts: false,
      ),
    );
    if (result != null && result.isNotEmpty && mounted) {
      setState(() => _selectedAccount = result.first);
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
      setState(() => _selectedCategory = result);
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

    setState(() => _isSaving = true);

    try {
      final amount = double.parse(_amountController.text);
      final value = _type == TransactionType.expense ? -amount : amount;

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
        categoryID: _selectedCategory?.id,
        isHidden: false,
        createdAt: DateTime.now(),
      );

      await TransactionService.instance.insertTransaction(transaction);
      await PendingImportService.instance.updatePendingImportStatus(
        widget.pendingImport.id,
        TransactionProposalStatus.confirmed,
        createdTransactionId: newTxId,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Transaccion registrada'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context, true);
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
