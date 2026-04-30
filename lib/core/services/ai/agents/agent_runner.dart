import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:bolsio/core/models/auto_import/transaction_proposal.dart';
import 'package:bolsio/core/services/ai/agents/agent_profile.dart';
import 'package:bolsio/core/services/ai/agents/agent_run_result.dart';
import 'package:bolsio/core/services/ai/ai_completion_result.dart';
import 'package:bolsio/core/services/ai/nexus_ai_service.dart';
import 'package:bolsio/core/services/ai/tools/ai_tool.dart';

/// Shared tool-loop runner used by every agent.
///
/// Iterates up to `profile.maxLoops` times:
///  1. Call `NexusAiService.streamWithTools` (single streaming POST that also
///     carries tool definitions). As SSE chunks arrive:
///     - text deltas are forwarded to [onTextChunk] so the UI can render
///       token-by-token immediately,
///     - `delta.tool_calls` are accumulated by index and surfaced once the
///       stream closes with `finish_reason: tool_calls`.
///  2. If the response carries `tool_calls`:
///     - For each call: if the profile gates it for approval, stop and return
///       the pending approvals to the caller (UI decides).
///     - Otherwise dispatch through the scoped registry, append a `role:'tool'`
///       message with the JSON-encoded result, and loop again.
///     - Collect any `AiToolResultProposal` payloads (quick-expense path).
///  3. Otherwise the model already streamed its final textual answer to the UI
///     during the same call — return [AgentRunStatus.finalText] with the
///     accumulated content and we're done.
///
/// The runner never touches the UI directly — text streaming flows through
/// the [onTextChunk] callback the caller supplies (typically the chat page).
class AgentRunner {
  final NexusAiService _nexus;

  AgentRunner({NexusAiService? nexus})
      : _nexus = nexus ?? NexusAiService.instance;

  Future<AgentRunResult> run({
    required AgentProfile profile,
    required List<Map<String, dynamic>> initialMessages,
    void Function(String chunk)? onTextChunk,
  }) async {
    final messages = List<Map<String, dynamic>>.from(initialMessages);
    final proposals = <TransactionProposal>[];
    final toolsJson = profile.toolRegistry.toOpenAiTools();

    // Defensive tracking: if NO iteration produces visible text and NO tool
    // executes successfully, the run is effectively muted from the user's POV.
    // We surface that as `AgentRunStatus.error` instead of letting the UI hang
    // on an empty assistant bubble.
    var anyTextEmitted = false;
    var anyToolSucceeded = false;
    var anyInvalidArgs = false;
    var anyToolDispatchError = false;

    // Wrap the caller's text-chunk callback so we can detect whether the
    // model actually produced any visible text during the run. Forward every
    // chunk untouched; only flip the flag when a non-empty piece arrives.
    void wrappedOnTextChunk(String chunk) {
      if (chunk.isNotEmpty) anyTextEmitted = true;
      if (onTextChunk != null) onTextChunk(chunk);
    }

    for (var iteration = 0; iteration < profile.maxLoops; iteration++) {
      // Only forward text chunks to the UI on iterations where the model is
      // actually producing the user-facing answer. Intermediate iterations
      // (post tool-execution) sometimes leak chain-of-thought tokens before
      // the next tool call; gating by iteration also keeps things simple —
      // the UI sees a clean single stream of the final answer.
      final r = await _nexus.streamWithTools(
        messages: messages,
        tools: toolsJson,
        toolChoice: profile.toolChoice,
        model: profile.modelOverride,
        temperature: profile.temperature,
        maxTokens: profile.maxTokens,
        onTextChunk: wrappedOnTextChunk,
      );

      if (r.finishReason == AiCompletionFinishReason.error ||
          r.finishReason == AiCompletionFinishReason.unavailable) {
        return AgentRunResult.fromCompletionError(r);
      }

      if (r.finishReason == AiCompletionFinishReason.stop) {
        if (proposals.isNotEmpty) {
          return AgentRunResult(
            status: AgentRunStatus.proposal,
            proposals: proposals,
            messages: messages,
            finalText: r.content,
          );
        }
        // Defensive: model said "stop" but produced no visible text AND
        // nothing useful happened during this run. Surface the error so the
        // chat UI doesn't render a forever-empty bubble.
        final hasContent = (r.content?.trim().isNotEmpty ?? false);
        if (!hasContent && !anyTextEmitted && !anyToolSucceeded) {
          return AgentRunResult(
            status: AgentRunStatus.error,
            error: anyInvalidArgs
                ? 'tool_arguments_invalid'
                : (anyToolDispatchError
                    ? 'tool_dispatch_failed'
                    : 'empty_response'),
            messages: messages,
          );
        }
        return AgentRunResult(
          status: AgentRunStatus.finalText,
          finalText: r.content ?? '',
          messages: messages,
        );
      }

      // finishReason == toolCalls
      messages.add(<String, dynamic>{
        'role': 'assistant',
        'content': r.content ?? '',
        'tool_calls': r.toolCalls
            .map((tc) => <String, dynamic>{
                  'id': tc.id,
                  'type': 'function',
                  'function': <String, dynamic>{
                    'name': tc.name,
                    'arguments': tc.argumentsJson,
                  },
                })
            .toList(),
      });

      final pending = <PendingApproval>[];
      for (final call in r.toolCalls) {
        if (profile.requiresApproval(call.name)) {
          Map<String, dynamic> args;
          try {
            final decoded = jsonDecode(call.argumentsJson);
            args = decoded is Map<String, dynamic>
                ? decoded
                : <String, dynamic>{};
          } catch (_) {
            args = <String, dynamic>{};
          }
          pending.add(PendingApproval(
            toolCallId: call.id,
            toolName: call.name,
            arguments: args,
          ));
        }
      }

      if (pending.isNotEmpty) {
        return AgentRunResult(
          status: AgentRunStatus.needsApproval,
          pendingApprovals: pending,
          messages: messages,
          proposals: proposals,
        );
      }

      for (final call in r.toolCalls) {
        // Stream-layer flag: the SSE accumulator already knows the args buffer
        // failed to parse. Short-circuit instead of re-trying jsonDecode and
        // record the failure so we can surface a UI error if NOTHING
        // productive happens this run.
        if (call.hasInvalidArguments) {
          anyInvalidArgs = true;
          messages.add(<String, dynamic>{
            'role': 'tool',
            'tool_call_id': call.id,
            'content': jsonEncode(<String, dynamic>{
              'status': 'error',
              'error': 'invalid_arguments_json',
              'message':
                  'Tool arguments could not be parsed (stream incomplete or '
                      'malformed JSON).',
            }),
          });
          continue;
        }

        Map<String, dynamic> args;
        try {
          final decoded = jsonDecode(call.argumentsJson);
          args = decoded is Map<String, dynamic>
              ? decoded
              : <String, dynamic>{};
        } catch (e) {
          anyInvalidArgs = true;
          messages.add(<String, dynamic>{
            'role': 'tool',
            'tool_call_id': call.id,
            'content': jsonEncode(<String, dynamic>{
              'status': 'error',
              'error': 'invalid_arguments_json',
              'message': '$e',
            }),
          });
          continue;
        }

        try {
          final result = await profile.toolRegistry.dispatch(call.name, args);

          if (result is AiToolResultProposal) {
            proposals.add(result.proposal);
          }

          messages.add(<String, dynamic>{
            'role': 'tool',
            'tool_call_id': call.id,
            'content': result.toModelJson(),
          });
          anyToolSucceeded = true;
        } catch (e, st) {
          anyToolDispatchError = true;
          debugPrint(
            'AgentRunner[${profile.name}] tool="${call.name}" '
            'dispatch threw: $e\n$st',
          );
          messages.add(<String, dynamic>{
            'role': 'tool',
            'tool_call_id': call.id,
            'content': jsonEncode(<String, dynamic>{
              'status': 'error',
              'error': 'tool_dispatch_failed',
              'message': '$e',
            }),
          });
        }
      }
    }

    debugPrint(
      'AgentRunner[${profile.name}] loop cap ${profile.maxLoops} reached '
      'anyText=$anyTextEmitted anyToolOk=$anyToolSucceeded '
      'anyInvalidArgs=$anyInvalidArgs anyDispatchErr=$anyToolDispatchError',
    );
    if (proposals.isNotEmpty) {
      return AgentRunResult(
        status: AgentRunStatus.proposal,
        proposals: proposals,
        messages: messages,
      );
    }
    // If the loop ran without ever producing visible text or a successful
    // tool, escalate to error so the UI can render a real message instead
    // of falling back to the muted loop-cap bubble.
    if (!anyTextEmitted && !anyToolSucceeded) {
      return AgentRunResult(
        status: AgentRunStatus.error,
        error: anyInvalidArgs
            ? 'tool_arguments_invalid'
            : (anyToolDispatchError
                ? 'tool_dispatch_failed'
                : 'no_progress'),
        messages: messages,
      );
    }
    return AgentRunResult(
      status: AgentRunStatus.loopCapReached,
      messages: messages,
    );
  }
}
