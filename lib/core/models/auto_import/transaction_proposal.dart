import 'package:drift/drift.dart';
import 'package:bolsio/core/database/app_db.dart';
import 'package:bolsio/core/models/auto_import/capture_channel.dart';
import 'package:bolsio/core/models/auto_import/transaction_proposal_status.dart';
import 'package:bolsio/core/models/transaction/transaction_type.enum.dart';
import 'package:bolsio/core/utils/uuid.dart';

/// A pure Dart model representing a parsed bank transaction proposal.
///
/// This is NOT a Drift table — it is an in-memory model produced by bank profile
/// parsers. Use [toCompanion] to convert it into a Drift companion for INSERT
/// into the `pending_imports` table.
class TransactionProposal {
  /// Unique identifier (UUID v4).
  final String id;

  /// Account ID resolved by the bank profile (nullable if unknown).
  final String? accountId;

  /// Monetary amount (always positive).
  final double amount;

  /// ISO currency code (e.g. 'VES', 'USD').
  final String currencyId;

  /// Date/time of the transaction.
  final DateTime date;

  /// Whether this is income or expense.
  final TransactionType type;

  /// Name or identifier of the counterparty (phone, merchant, etc.).
  final String? counterpartyName;

  /// Bank reference number for cross-channel deduplication.
  final String? bankRef;

  /// Original raw text from the SMS or notification.
  final String rawText;

  /// Which channel captured this event.
  final CaptureChannel channel;

  /// Sender identifier (SMS shortcode or package name).
  final String? sender;

  /// Parser confidence score (0.0 to 1.0).
  final double confidence;

  /// Suggested category ID (if the profile can determine one).
  final String? proposedCategoryId;

  /// Whether the dedupe checker found a matching existing transaction.
  final bool dedupeMatched;

  /// Identifier of the sender profile that parsed this event (e.g. 'bdv_sms').
  final String? parsedBySender;

  /// (Transfer only) Destination account ID.
  final String? receivingAccountId;

  /// (Transfer only) Amount arriving at destination (net of fees).
  final double? valueInDestiny;

  const TransactionProposal({
    required this.id,
    this.accountId,
    required this.amount,
    required this.currencyId,
    required this.date,
    required this.type,
    this.counterpartyName,
    this.bankRef,
    required this.rawText,
    required this.channel,
    this.sender,
    required this.confidence,
    this.proposedCategoryId,
    this.dedupeMatched = false,
    this.parsedBySender,
    this.receivingAccountId,
    this.valueInDestiny,
  });

  TransactionProposal copyWith({
    String? id,
    String? accountId,
    double? amount,
    String? currencyId,
    DateTime? date,
    TransactionType? type,
    String? counterpartyName,
    String? bankRef,
    String? rawText,
    CaptureChannel? channel,
    String? sender,
    double? confidence,
    String? proposedCategoryId,
    bool? dedupeMatched,
    String? parsedBySender,
    String? receivingAccountId,
    double? valueInDestiny,
  }) {
    return TransactionProposal(
      id: id ?? this.id,
      accountId: accountId ?? this.accountId,
      amount: amount ?? this.amount,
      currencyId: currencyId ?? this.currencyId,
      date: date ?? this.date,
      type: type ?? this.type,
      counterpartyName: counterpartyName ?? this.counterpartyName,
      bankRef: bankRef ?? this.bankRef,
      rawText: rawText ?? this.rawText,
      channel: channel ?? this.channel,
      sender: sender ?? this.sender,
      confidence: confidence ?? this.confidence,
      proposedCategoryId: proposedCategoryId ?? this.proposedCategoryId,
      dedupeMatched: dedupeMatched ?? this.dedupeMatched,
      parsedBySender: parsedBySender ?? this.parsedBySender,
      receivingAccountId: receivingAccountId ?? this.receivingAccountId,
      valueInDestiny: valueInDestiny ?? this.valueInDestiny,
    );
  }

  /// Create a new proposal with an auto-generated UUID.
  factory TransactionProposal.newProposal({
    String? accountId,
    required double amount,
    required String currencyId,
    required DateTime date,
    required TransactionType type,
    String? counterpartyName,
    String? bankRef,
    required String rawText,
    required CaptureChannel channel,
    String? sender,
    required double confidence,
    String? proposedCategoryId,
    bool dedupeMatched = false,
    String? parsedBySender,
    String? receivingAccountId,
    double? valueInDestiny,
  }) {
    return TransactionProposal(
      id: generateUUID(),
      accountId: accountId,
      amount: amount,
      currencyId: currencyId,
      date: date,
      type: type,
      counterpartyName: counterpartyName,
      bankRef: bankRef,
      rawText: rawText,
      channel: channel,
      sender: sender,
      confidence: confidence,
      proposedCategoryId: proposedCategoryId,
      dedupeMatched: dedupeMatched,
      parsedBySender: parsedBySender,
      receivingAccountId: receivingAccountId,
      valueInDestiny: valueInDestiny,
    );
  }

  /// Convert this proposal into a Drift [PendingImportsCompanion] ready for INSERT.
  ///
  /// The [status] parameter determines the initial status of the pending import row.
  PendingImportsCompanion toCompanion({
    required TransactionProposalStatus status,
  }) {
    return PendingImportsCompanion(
      id: Value(id),
      accountId: Value(accountId),
      amount: Value(amount),
      currencyId: Value(currencyId),
      date: Value(date),
      type: Value(type.databaseValue),
      counterpartyName: Value(counterpartyName),
      bankRef: Value(bankRef),
      rawText: Value(rawText),
      channel: Value(channel.dbValue),
      sender: Value(sender),
      confidence: Value(confidence),
      proposedCategoryId: Value(proposedCategoryId),
      status: Value(status.dbValue),
      receivingAccountId: Value(receivingAccountId),
      valueInDestiny: Value(valueInDestiny),
    );
  }

  @override
  String toString() {
    return 'TransactionProposal('
        'id: $id, '
        'amount: $amount $currencyId, '
        'type: ${type.databaseValue}, '
        'channel: ${channel.dbValue}, '
        'bankRef: $bankRef, '
        'confidence: $confidence'
        '${receivingAccountId != null ? ', receivingAccountId: $receivingAccountId' : ''}'
        '${valueInDestiny != null ? ', valueInDestiny: $valueInDestiny' : ''}'
        ')';
  }
}
