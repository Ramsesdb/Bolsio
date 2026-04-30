import 'package:bolsio/core/services/ai/tools/ai_tool_registry.dart';

/// Immutable description of an agent's configuration: system prompt, scoped
/// tool registry, loop cap, tool-choice policy, and approval predicate.
///
/// A profile does NOT own the loop runner — agents (see `QuickExpenseAgent`,
/// `BolsioAiAgent`) compose a profile with the shared tool-loop algorithm.
/// Keeping this layer inert makes it trivial to add new agents without
/// duplicating loop plumbing.
class AgentProfile {
  /// Stable name, used in debug logs only.
  final String name;

  /// System prompt injected as the first `role:'system'` message.
  final String systemPrompt;

  /// Tools this agent is allowed to call. Scoping the registry at construction
  /// enforces ai-tools spec §Agent Profile Isolation — a profile cannot
  /// dispatch tools it did not whitelist even if the model hallucinates them.
  final AiToolRegistry toolRegistry;

  /// Either the string `'auto' | 'none' | 'required'` or a map of shape
  /// `{'type':'function','function':{'name':'create_transaction'}}` to force
  /// a specific tool. Forwarded verbatim to the gateway.
  final Object toolChoice;

  /// Maximum round-trips between model and tools before the loop terminates
  /// with [AiCompletionFinishReason.loopCap].
  final int maxLoops;

  /// Sampling temperature. Defaults to 0.2 for tool-calling reliability.
  final double temperature;

  /// Maximum output tokens per model call. Kept modest by default so free-tier
  /// upstream providers (OpenRouter) don't reject the request. Tool-calling
  /// agents rarely need more than ~2k; conversational agents may push to ~4k.
  final int maxTokens;

  /// Optional model override. `null` = use provider default / user setting.
  final String? modelOverride;

  /// Names of mutating tools that require explicit user approval before
  /// execution. Non-mutating reads bypass approval.
  final Set<String> approvalRequiredTools;

  const AgentProfile({
    required this.name,
    required this.systemPrompt,
    required this.toolRegistry,
    this.toolChoice = 'auto',
    this.maxLoops = 3,
    this.temperature = 0.2,
    this.maxTokens = 2048,
    this.modelOverride,
    this.approvalRequiredTools = const {},
  });

  /// Whether the given tool name must pass through the approval gate before
  /// being executed by the runner.
  bool requiresApproval(String toolName) =>
      approvalRequiredTools.contains(toolName);
}

/// Marker for a pending tool call waiting on user approval. Surfaced by the
/// agent runner to the UI; when the user decides, the caller re-invokes the
/// agent's `resume(...)` pathway with the decision.
class PendingApproval {
  final String toolCallId;
  final String toolName;
  final Map<String, dynamic> arguments;

  const PendingApproval({
    required this.toolCallId,
    required this.toolName,
    required this.arguments,
  });
}
