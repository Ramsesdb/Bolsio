/// A single tool call emitted by the model in a non-streaming response.
class AiToolCall {
  final String id;
  final String name;
  final String argumentsJson;

  /// True when [argumentsJson] failed to parse as JSON during stream
  /// accumulation (e.g. truncated stream, strict-mode hiccup, malformed delta).
  /// Defensive flag so the agent runner can surface a visible error instead of
  /// silently swallowing the call.
  final bool hasInvalidArguments;

  const AiToolCall({
    required this.id,
    required this.name,
    required this.argumentsJson,
    this.hasInvalidArguments = false,
  });

  @override
  String toString() =>
      'AiToolCall(id: $id, name: $name, argumentsJson: $argumentsJson, '
      'hasInvalidArguments: $hasInvalidArguments)';
}

/// Reason the tool loop terminated.
enum AiCompletionFinishReason {
  /// Model returned a final textual answer with no tool_calls.
  stop,

  /// Model requested tool invocation(s).
  toolCalls,

  /// Loop hit the `AgentProfile.maxToolLoops` cap before a textual answer.
  loopCap,

  /// Network, HTTP, or parse error during the loop. [AiCompletionResult.error]
  /// carries details; the caller decides how to surface it.
  error,

  /// API key missing or provider unavailable.
  unavailable,
}

/// Result shape for `NexusAiService.completeWithTools` + agent tool loop.
class AiCompletionResult {
  /// Final textual content from the last assistant turn, if any. May be empty
  /// when the loop terminated due to [AiCompletionFinishReason.toolCalls] (i.e.
  /// caller should dispatch and re-invoke) or [AiCompletionFinishReason.loopCap].
  final String? content;

  /// Tool calls requested on the last turn. Empty when [finishReason] is
  /// [AiCompletionFinishReason.stop].
  final List<AiToolCall> toolCalls;

  /// Why the model stopped on this turn. Callers route behavior off this.
  final AiCompletionFinishReason finishReason;

  /// Full running message history including any tool messages appended by the
  /// loop. Carried so callers can persist or replay the conversation context.
  final List<Map<String, dynamic>> messages;

  /// Error details when [finishReason] is [AiCompletionFinishReason.error] or
  /// [AiCompletionFinishReason.unavailable].
  final String? error;

  const AiCompletionResult({
    this.content,
    this.toolCalls = const [],
    required this.finishReason,
    this.messages = const [],
    this.error,
  });
}
