import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:kilatex/app/transactions/auto_import/widgets/proposal_status_chip.dart';
import 'package:kilatex/core/database/app_db.dart';
import 'package:kilatex/core/models/auto_import/capture_channel.dart';
import 'package:kilatex/core/models/auto_import/transaction_proposal_status.dart';

/// A list tile representing a single pending import proposal.
class PendingImportTile extends StatelessWidget {
  const PendingImportTile({
    super.key,
    required this.pendingImport,
    this.onTap,
  });

  final PendingImportInDB pendingImport;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final status =
        TransactionProposalStatus.fromDbValue(pendingImport.status);
    final channel = CaptureChannel.fromDbValue(pendingImport.channel);
    final isIncome = pendingImport.type == 'I';

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: ListTile(
        leading: _buildChannelIcon(channel, context),
        title: Text(
          _buildTitle(isIncome),
          style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
        ),
        subtitle: Text(
          _buildSubtitle(),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        trailing: ProposalStatusChip(status: status),
        onTap: onTap,
      ),
    );
  }

  Widget _buildChannelIcon(CaptureChannel channel, BuildContext context) {
    final (icon, color) = switch (channel) {
      CaptureChannel.sms => (Icons.sms_outlined, Colors.blue),
      CaptureChannel.notification => (Icons.notifications_outlined, Colors.purple),
      CaptureChannel.api => (Icons.sync, Colors.teal),
      CaptureChannel.receiptImage => (Icons.receipt_long, Colors.orange),
      CaptureChannel.voice => (Icons.mic_none_rounded, Colors.deepPurple),
    };

    return CircleAvatar(
      backgroundColor: color.withValues(alpha: 0.12),
      child: Icon(icon, color: color, size: 20),
    );
  }

  String _buildTitle(bool isIncome) {
    final verb = isIncome ? 'Recibiste' : 'Pagaste';
    final formattedAmount = _formatAmount();
    return '$verb $formattedAmount';
  }

  String _formatAmount() {
    final currency = pendingImport.currencyId;
    final amount = pendingImport.amount;

    final formatter = NumberFormat('#,##0.00', 'es_VE');
    final formatted = formatter.format(amount);

    if (currency == 'VES') {
      return 'Bs. $formatted';
    } else if (currency == 'USD') {
      return '\$$formatted';
    }
    return '$formatted $currency';
  }

  String _buildSubtitle() {
    final counterparty =
        pendingImport.counterpartyName ?? 'Sin contraparte';
    final relativeDate = _formatRelativeDate(pendingImport.createdAt);
    return '$counterparty  -  $relativeDate';
  }

  String _formatRelativeDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inMinutes < 1) return 'ahora';
    if (diff.inMinutes < 60) return 'hace ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'hace ${diff.inHours} h';
    if (diff.inDays < 7) return 'hace ${diff.inDays} d';
    return DateFormat('dd/MM/yyyy').format(date);
  }
}
