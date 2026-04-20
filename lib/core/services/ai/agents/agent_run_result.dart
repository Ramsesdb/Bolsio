import 'package:wallex/core/models/auto_import/transaction_proposal.dart';
import 'package:wallex/core/services/ai/agents/agent_profile.dart';
import 'package:wallex/core/services/ai/ai_completion_result.dart';

/// Outcome of one agent run.
enum AgentRunStatus {
  /// The model returned a final textual answer — ready to show the user.
  finalText,

  /// The model wants to stream a plain-text reply (no tool_calls on first
  /// iteration). Caller should re-invoke `NexusAiService.streamComplete` with
  /// [AgentRunResult.messages] to preserve byte-for-byte streaming UX.
  streamFinalText,

  /// One or more tool calls need user approval before execution. Consume
  /// [AgentRunResult.pendingApprovals], surface the UI, then re-run the agent
  /// with the user's decision applied to `messages`.
  needsApproval,

  /// One or more proposals (quick-expense flow) were generated; the caller
  /// consumes [AgentRunResult.proposals] for the review sheet.
  proposal,

  /// Loop cap reached without a final text. UI should render a fallback.
  loopCapReached,

  /// Network, HTTP, or configuration error. [AgentRunResult.error] carries
  /// details.
  error,
}

/// Result of running an [AgentProfile]-backed loop.
///
/// The runner returns this instead of streaming events so the UI layer can
/// decide whether to:
///  - render [finalText] directly,
///  - re-call `streamComplete(messages)` for byte-for-byte streaming,
///  - show approval UI from [pendingApprovals],
///  - hand [proposals] to the review sheet.
class AgentRunResult {
  final AgentRunStatus status;

  /// Final textual answer (when [status] is [AgentRunStatus.finalText]).
  final String? finalText;

  /// Running message history, including any tool messages appended during the
  /// loop. Callers that want to stream the final turn pass this back to
  /// `streamComplete` so the UX mirrors the pre-tool era.
  final List<Map<String, dynamic>> messages;

  /// Tool calls that need user approval (for `wallexAssistant`).
  final List<PendingApproval> pendingApprovals;

  /// Proposals emitted by tools run in propose mode (for `quickExpense`).
  final List<TransactionProposal> proposals;

  /// Error code when [status] is [AgentRunStatus.error].
  final String? error;

  const AgentRunResult({
    required this.status,
    this.finalText,
    this.messages = const [],
    this.pendingApprovals = const [],
    this.proposals = const [],
    this.error,
  });

  factory AgentRunResult.fromCompletionError(AiCompletionResult r) {
    return AgentRunResult(
      status: AgentRunStatus.error,
      error: r.error ?? 'unknown_error',
      messages: r.messages,
    );
  }
}
