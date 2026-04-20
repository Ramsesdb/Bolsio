import 'dart:convert';

import 'package:wallex/core/models/auto_import/transaction_proposal.dart';

/// Execution mode for mutating tools (create_transaction, create_transfer).
///
/// - [propose] returns a [TransactionProposal] without touching the database.
///   Used by the quick-expense agent so the user can review/edit before commit.
/// - [commit] writes directly to Drift. Used by the chat agent after the
///   user explicitly approves the tool call from the chat UI.
enum AiToolExecMode { propose, commit }

/// Contract implemented by every AI tool the assistant can call.
///
/// Tools MUST be pure Dart (no `BuildContext`, no UI) so they are safe to
/// dispatch from the agent loop in any isolate. Argument validation happens
/// inside [execute]; invalid args should return
/// [AiToolResult.error] rather than throw.
abstract class AiTool {
  /// Stable machine-readable tool name matching the JSON Schema.
  /// Must match `^[a-z_][a-z0-9_]*$`.
  String get name;

  /// One-line description passed verbatim to the LLM.
  String get description;

  /// JSON Schema describing [execute] arguments. Serialized as-is into the
  /// OpenAI `tools[].function.parameters` field.
  Map<String, dynamic> get parametersSchema;

  /// Whether calling this tool changes persisted state.
  /// Drives the approval gate in the `wallexAssistant` profile.
  bool get isMutating;

  /// Dispatch the tool with a JSON-decoded arguments map.
  Future<AiToolResult> execute(Map<String, dynamic> args);
}

/// Typed result wrapper returned by [AiTool.execute].
///
/// The sealed hierarchy mirrors the three shapes the agent loop expects:
///  - [AiToolResultOk] — arbitrary JSON-serializable payload, re-injected as
///    a `role:"tool"` message.
///  - [AiToolResultProposal] — carries a [TransactionProposal] for the
///    quick-expense flow; the runner consumes it without re-injecting.
///  - [AiToolResultError] — structured error surfaced to the model so it can
///    correct itself (argument validation, missing account, etc.).
sealed class AiToolResult {
  const AiToolResult();

  factory AiToolResult.ok(Object payload) = AiToolResultOk;

  factory AiToolResult.proposal(TransactionProposal proposal) =
      AiToolResultProposal;

  factory AiToolResult.error(String message, {String code = 'tool_error'}) =>
      AiToolResultError(message, code: code);

  /// Encode this result into the JSON string sent back to the LLM as the
  /// `tool` message `content`. [AiToolResultProposal] is encoded as a
  /// best-effort summary (the runner typically short-circuits before this
  /// is reached).
  String toModelJson() {
    switch (this) {
      case AiToolResultOk(:final payload):
        return jsonEncode({'status': 'ok', 'data': payload});
      case AiToolResultProposal(:final proposal):
        return jsonEncode({
          'status': 'proposed',
          'proposal': {
            'id': proposal.id,
            'amount': proposal.amount,
            'currencyId': proposal.currencyId,
            'type': proposal.type.databaseValue,
            'accountId': proposal.accountId,
            'proposedCategoryId': proposal.proposedCategoryId,
            'date': proposal.date.toIso8601String(),
            'counterpartyName': proposal.counterpartyName,
            'rawText': proposal.rawText,
          },
        });
      case AiToolResultError(:final code, :final message):
        return jsonEncode({
          'status': 'error',
          'error': code,
          'message': message,
        });
    }
  }
}

final class AiToolResultOk extends AiToolResult {
  final Object payload;
  const AiToolResultOk(this.payload);
}

final class AiToolResultProposal extends AiToolResult {
  final TransactionProposal proposal;
  const AiToolResultProposal(this.proposal);
}

final class AiToolResultError extends AiToolResult {
  final String message;
  final String code;
  const AiToolResultError(this.message, {this.code = 'tool_error'});
}
