import 'package:flutter/material.dart';
import 'package:bolsio/core/models/auto_import/transaction_proposal_status.dart';

/// Colored chip indicating the status of a pending import proposal.
class ProposalStatusChip extends StatelessWidget {
  const ProposalStatusChip({super.key, required this.status});

  final TransactionProposalStatus status;

  @override
  Widget build(BuildContext context) {
    final (label, color, icon) = _statusData(context);

    return Chip(
      avatar: Icon(icon, size: 16, color: color),
      label: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
      backgroundColor: color.withValues(alpha: 0.12),
      side: BorderSide.none,
      padding: EdgeInsets.zero,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
    );
  }

  (String, Color, IconData) _statusData(BuildContext context) {
    switch (status) {
      case TransactionProposalStatus.pending:
        return ('Pendiente', Colors.orange, Icons.schedule);
      case TransactionProposalStatus.duplicate:
        return ('Posible duplicado', Colors.amber.shade700, Icons.content_copy);
      case TransactionProposalStatus.confirmed:
        return ('Confirmado', Colors.green, Icons.check_circle);
      case TransactionProposalStatus.rejected:
        return ('Rechazado', Colors.grey, Icons.block);
    }
  }
}
