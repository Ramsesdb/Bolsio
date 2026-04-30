import 'dart:async';

import 'package:flutter/material.dart';
import 'package:bolsio/app/transactions/voice_input/voice_record_overlay.dart';
import 'package:bolsio/app/transactions/voice_input/voice_review_sheet.dart';
import 'package:bolsio/core/models/auto_import/capture_channel.dart';
import 'package:bolsio/core/models/auto_import/transaction_proposal.dart';
import 'package:bolsio/core/presentation/helpers/snackbar.dart';
import 'package:bolsio/core/services/ai/agents/agent_run_result.dart';
import 'package:bolsio/core/services/ai/agents/quick_expense_agent.dart';
import 'package:bolsio/core/services/voice/voice_permission_dialog.dart';
import 'package:bolsio/i18n/generated/translations.g.dart';

/// End-to-end voice quick-expense flow for the FAB mic action.
///
/// Pipeline:
///  1. Request/verify microphone permission (explainer + MIUI settings CTA).
///  2. Open [showVoiceRecordOverlay] -> captures final transcript.
///  3. Runs [QuickExpenseAgent.run] with a loading dialog on top.
///  4. Opens [showVoiceReviewSheet] with the emitted [TransactionProposal].
///     The review sheet commits to the DB itself (auto or manual).
///
/// Mirrors `ReceiptImportFlow.start`'s shape so the FAB fan button can call it
/// with one line.
abstract class VoiceCaptureFlow {
  static Future<void> start(
    BuildContext context, {
    QuickExpenseAgent? agent,
  }) async {
    final permission = await ensureMicPermissionWithExplainer(context);
    if (permission != VoicePermissionOutcome.granted) {
      if (permission == VoicePermissionOutcome.denied && context.mounted) {
        showMicPermissionDeniedSnackbar(context);
      }
      return;
    }
    if (!context.mounted) return;
    final t = Translations.of(context);

    final transcript = await showVoiceRecordOverlay(context);
    if (transcript == null) return;
    final trimmed = transcript.trim();

    if (!context.mounted) return;

    if (trimmed.isEmpty) {
      BolsioSnackbar.warning(
        SnackbarParams(t.bolsio_ai.voice_empty_transcript),
      );
      return;
    }

    final runner = agent ?? QuickExpenseAgent();

    BuildContext? capturedDialogCtx;
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        useRootNavigator: true,
        builder: (dialogContext) {
          capturedDialogCtx = dialogContext;
          return AlertDialog(
            content: Row(
              children: [
                const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(t.bolsio_ai.voice_processing)),
              ],
            ),
          );
        },
      ),
    );

    void dismissLoader() {
      final dCtx = capturedDialogCtx;
      if (dCtx != null && Navigator.canPop(dCtx)) {
        Navigator.pop(dCtx);
      }
      capturedDialogCtx = null;
    }

    AgentRunResult result;
    try {
      result = await runner.run(trimmed);
    } catch (e) {
      dismissLoader();
      if (!context.mounted) return;
      BolsioSnackbar.error(SnackbarParams.fromError(e));
      return;
    }
    dismissLoader();

    if (!context.mounted) return;

    if (result.status == AgentRunStatus.error) {
      // Distinguish "gateway / upstream LLM transient failure" (502/503/504,
      // surfaced by NexusAiService as 'gateway_unavailable') from genuine
      // comprehension failures — the former is a server issue, not the user's
      // fault, so we show a clearer message instead of "no pude interpretar".
      final isGatewayDown = result.error == 'gateway_unavailable';
      BolsioSnackbar.error(
        SnackbarParams(
          isGatewayDown
              ? t.bolsio_ai.voice_flow_gateway_unavailable_title
              : t.bolsio_ai.voice_flow_error_title,
          message: isGatewayDown
              ? t.bolsio_ai.voice_flow_gateway_unavailable
              : result.error,
        ),
      );
      return;
    }

    if (result.proposals.isEmpty) {
      BolsioSnackbar.warning(
        SnackbarParams(t.bolsio_ai.voice_flow_no_proposal),
      );
      return;
    }

    var proposal = result.proposals.first;
    // Ensure channel + rawText are stamped (tool defaults to voice already,
    // but belt-and-suspenders for future CreateTransactionTool refactors).
    if (proposal.channel != CaptureChannel.voice ||
        proposal.rawText.trim().isEmpty) {
      proposal = proposal.copyWith(
        channel: CaptureChannel.voice,
        rawText: trimmed,
      );
    }

    await showVoiceReviewSheet(context, proposal: proposal);
  }
}
