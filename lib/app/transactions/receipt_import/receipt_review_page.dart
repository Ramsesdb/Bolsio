import 'dart:io';

import 'package:flutter/material.dart';
import 'package:wallex/app/transactions/form/transaction_form.page.dart';
import 'package:wallex/core/models/auto_import/transaction_proposal.dart';
import 'package:wallex/core/models/transaction/transaction_type.enum.dart';
import 'package:wallex/core/presentation/helpers/snackbar.dart';
import 'package:wallex/core/routes/route_utils.dart';
import 'package:wallex/core/services/receipt_ocr/receipt_extractor_service.dart';
import 'package:wallex/i18n/generated/translations.g.dart';

class ReceiptReviewPage extends StatefulWidget {
  const ReceiptReviewPage({
    super.key,
    required this.pendingAttachmentPath,
    required this.extraction,
    this.showPreview = true,
    this.showDuplicateWarning = false,
    this.onContinue,
    this.onDiscard,
  });

  final String pendingAttachmentPath;
  final ExtractionResult extraction;
  final bool showPreview;
  final bool showDuplicateWarning;
  final Future<void> Function(TransactionProposal updatedProposal)? onContinue;
  final Future<void> Function()? onDiscard;

  @override
  State<ReceiptReviewPage> createState() => _ReceiptReviewPageState();
}

class _ReceiptReviewPageState extends State<ReceiptReviewPage> {
  late final TextEditingController _amountController;
  late final TextEditingController _counterpartyController;
  late final TextEditingController _referenceController;

  late DateTime _date;
  late TransactionType _type;
  late String _currency;

  bool _cleaned = false;

  @override
  void initState() {
    super.initState();
    final proposal = widget.extraction.proposal!;

    _amountController = TextEditingController(
      text: proposal.amount.toStringAsFixed(2),
    );
    _counterpartyController = TextEditingController(
      text: proposal.counterpartyName ?? '',
    );
    _referenceController = TextEditingController(text: proposal.bankRef ?? '');

    _date = proposal.date;
    _type = proposal.type;
    _currency = proposal.currencyId;
  }

  @override
  void dispose() {
    _amountController.dispose();
    _counterpartyController.dispose();
    _referenceController.dispose();
    super.dispose();
  }

  Future<void> _cleanupPendingFile() async {
    if (_cleaned) return;

    _cleaned = true;
    final file = File(widget.pendingAttachmentPath);
    try {
      if (file.existsSync()) {
        file.deleteSync();
      }
    } on FileSystemException {
      // Ignore cleanup races on test/dev environments.
    }
  }

  Future<void> _closeAndDiscard() async {
    await _cleanupPendingFile();
    if (widget.onDiscard != null) {
      await widget.onDiscard!.call();
      return;
    }
    if (!mounted) return;
    RouteUtils.popRoute();
  }

  Future<void> _continueToForm() async {
    final t = Translations.of(context);
    final amount = double.tryParse(_amountController.text.replaceAll(',', '.'));

    if (amount == null || amount <= 0) {
      WallexSnackbar.warning(
        SnackbarParams(t.transaction.form.validators.zero),
      );
      return;
    }

    final updated = widget.extraction.proposal!.copyWith(
      amount: amount,
      currencyId: _currency,
      date: _date,
      type: _type,
      counterpartyName: _counterpartyController.text.trim().isEmpty
          ? null
          : _counterpartyController.text.trim(),
      bankRef: _referenceController.text.trim().isEmpty
          ? null
          : _referenceController.text.trim(),
    );

    if (widget.onContinue != null) {
      await widget.onContinue!(updated);
      return;
    }

    await RouteUtils.pushRoute(
      TransactionFormPage.fromReceipt(
        receiptPrefill: updated,
        pendingAttachmentPath: widget.pendingAttachmentPath,
      ),
      withReplacement: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);

    return PopScope(
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) {
          await _cleanupPendingFile();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(t.transaction.receipt_import.review_title),
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: _closeAndDiscard,
          ),
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                t.transaction.receipt_import.review_subtitle,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              if (widget.showDuplicateWarning) ...[
                const SizedBox(height: 12),
                Card(
                  color: Colors.amber.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Icon(
                          Icons.warning_amber_rounded,
                          color: Colors.amber.shade800,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Posible duplicado -- puede que ya hayas registrado esta operacion manualmente. Revisa y decide.',
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
              ],
              const SizedBox(height: 12),
              if (widget.showPreview) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.file(
                    File(widget.pendingAttachmentPath),
                    fit: BoxFit.cover,
                    height: 220,
                    errorBuilder: (_, _, _) {
                      return const SizedBox(
                        height: 220,
                        child: Center(child: Icon(Icons.broken_image_outlined)),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 16),
              ],
              TextField(
                controller: _amountController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: t.transaction.receipt_import.field.amount,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _currency,
                decoration: InputDecoration(
                  labelText: t.transaction.receipt_import.field.currency,
                  border: const OutlineInputBorder(),
                  suffixIcon: widget.extraction.currencyAmbiguous
                      ? Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: Tooltip(
                            message: t
                                .transaction
                                .receipt_import
                                .error
                                .ambiguous_currency,
                            child: const CircleAvatar(
                              radius: 10,
                              child: Text('?'),
                            ),
                          ),
                        )
                      : null,
                ),
                items: const [
                  DropdownMenuItem(value: 'USD', child: Text('USD')),
                  DropdownMenuItem(value: 'VES', child: Text('VES')),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => _currency = value);
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<TransactionType>(
                initialValue: _type,
                decoration: InputDecoration(
                  labelText: t.transaction.receipt_import.field.type,
                  border: const OutlineInputBorder(),
                ),
                items: [
                  DropdownMenuItem(
                    value: TransactionType.expense,
                    child: Text(t.transaction.types.expense(n: 1)),
                  ),
                  DropdownMenuItem(
                    value: TransactionType.income,
                    child: Text(t.transaction.types.income(n: 1)),
                  ),
                  DropdownMenuItem(
                    value: TransactionType.transfer,
                    child: Text(t.transaction.types.transfer(n: 1)),
                  ),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => _type = value);
                },
              ),
              const SizedBox(height: 12),
              ListTile(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: BorderSide(color: Theme.of(context).dividerColor),
                ),
                title: Text(t.transaction.receipt_import.field.date),
                subtitle: Text(
                  '${_date.day}/${_date.month}/${_date.year} ${_date.hour.toString().padLeft(2, '0')}:${_date.minute.toString().padLeft(2, '0')}',
                ),
                trailing: const Icon(Icons.calendar_today_outlined),
                onTap: () async {
                  final date = await showDatePicker(
                    context: context,
                    firstDate: DateTime(2000),
                    lastDate: DateTime.now().add(const Duration(days: 3650)),
                    initialDate: _date,
                  );
                  if (date == null || !mounted) return;
                  setState(() {
                    _date = DateTime(
                      date.year,
                      date.month,
                      date.day,
                      _date.hour,
                      _date.minute,
                    );
                  });
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _counterpartyController,
                decoration: InputDecoration(
                  labelText: t.transaction.receipt_import.field.counterparty,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _referenceController,
                decoration: InputDecoration(
                  labelText: t.transaction.receipt_import.field.reference,
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _closeAndDiscard,
                    child: Text(t.ui_actions.cancel),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _continueToForm,
                    icon: const Icon(Icons.arrow_forward),
                    label: Text(
                      t.transaction.receipt_import.review_cta_continue,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
