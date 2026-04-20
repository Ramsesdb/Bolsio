import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:wallex/core/models/auto_import/transaction_proposal.dart';
import 'package:wallex/core/services/ai/agents/agent_profile.dart';
import 'package:wallex/core/services/ai/agents/agent_run_result.dart';
import 'package:wallex/core/services/ai/ai_completion_result.dart';
import 'package:wallex/core/services/ai/nexus_ai_service.dart';
import 'package:wallex/core/services/ai/tools/ai_tool.dart';

/// Shared tool-loop runner used by every agent.
///
/// Iterates up to `profile.maxLoops` times:
///  1. Call `NexusAiService.completeWithTools` with current messages + tools.
///  2. If the response has `tool_calls`:
///     - For each call: if the profile gates it for approval, stop and return
///       the pending approvals to the caller (UI decides).
///     - Otherwise dispatch through the scoped registry, append a `role:'tool'`
///       message with the JSON-encoded result, and loop again.
///     - Collect any `AiToolResultProposal` payloads (quick-expense path).
///  3. If the response has NO `tool_calls` on the first iteration and the
///     caller opted into streaming (`streamFinalWhenNoToolsFirstTurn = true`),
///     short-circuit with [AgentRunStatus.streamFinalText] so the UI re-invokes
///     `streamComplete`.
///  4. Otherwise return the model's textual content as final.
///
/// The runner never touches the UI — all user-facing decisions flow through
/// [AgentRunResult].
class AgentRunner {
  final NexusAiService _nexus;

  AgentRunner({NexusAiService? nexus})
      : _nexus = nexus ?? NexusAiService.instance;

  Future<AgentRunResult> run({
    required AgentProfile profile,
    required List<Map<String, dynamic>> initialMessages,
    bool streamFinalWhenNoToolsFirstTurn = false,
  }) async {
    final messages = List<Map<String, dynamic>>.from(initialMessages);
    final proposals = <TransactionProposal>[];
    final toolsJson = profile.toolRegistry.toOpenAiTools();

    for (var iteration = 0; iteration < profile.maxLoops; iteration++) {
      final r = await _nexus.completeWithTools(
        messages: messages,
        tools: toolsJson,
        toolChoice: profile.toolChoice,
        model: profile.modelOverride,
        temperature: profile.temperature,
        maxTokens: profile.maxTokens,
      );

      if (r.finishReason == AiCompletionFinishReason.error ||
          r.finishReason == AiCompletionFinishReason.unavailable) {
        return AgentRunResult.fromCompletionError(r);
      }

      if (r.finishReason == AiCompletionFinishReason.stop) {
        if (iteration == 0 && streamFinalWhenNoToolsFirstTurn) {
          return AgentRunResult(
            status: AgentRunStatus.streamFinalText,
            messages: messages,
          );
        }
        if (proposals.isNotEmpty) {
          return AgentRunResult(
            status: AgentRunStatus.proposal,
            proposals: proposals,
            messages: messages,
            finalText: r.content,
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
        Map<String, dynamic> args;
        try {
          final decoded = jsonDecode(call.argumentsJson);
          args = decoded is Map<String, dynamic>
              ? decoded
              : <String, dynamic>{};
        } catch (e) {
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

        final result = await profile.toolRegistry.dispatch(call.name, args);

        if (result is AiToolResultProposal) {
          proposals.add(result.proposal);
        }

        messages.add(<String, dynamic>{
          'role': 'tool',
          'tool_call_id': call.id,
          'content': result.toModelJson(),
        });
      }
    }

    debugPrint(
      'AgentRunner[${profile.name}] loop cap ${profile.maxLoops} reached',
    );
    if (proposals.isNotEmpty) {
      return AgentRunResult(
        status: AgentRunStatus.proposal,
        proposals: proposals,
        messages: messages,
      );
    }
    return AgentRunResult(
      status: AgentRunStatus.loopCapReached,
      messages: messages,
    );
  }
}
