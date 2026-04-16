/// Status of a transaction proposal in the pending imports queue.
enum TransactionProposalStatus {
  pending,
  confirmed,
  rejected,
  duplicate;

  /// Value stored in the database (matches CHECK constraint on `pending_imports.status`).
  String get dbValue {
    switch (this) {
      case TransactionProposalStatus.pending:
        return 'pending';
      case TransactionProposalStatus.confirmed:
        return 'confirmed';
      case TransactionProposalStatus.rejected:
        return 'rejected';
      case TransactionProposalStatus.duplicate:
        return 'duplicate';
    }
  }

  /// Parse a database value back into a [TransactionProposalStatus].
  static TransactionProposalStatus fromDbValue(String value) {
    switch (value) {
      case 'pending':
        return TransactionProposalStatus.pending;
      case 'confirmed':
        return TransactionProposalStatus.confirmed;
      case 'rejected':
        return TransactionProposalStatus.rejected;
      case 'duplicate':
        return TransactionProposalStatus.duplicate;
      default:
        throw ArgumentError(
            'Unknown TransactionProposalStatus dbValue: $value');
    }
  }
}
