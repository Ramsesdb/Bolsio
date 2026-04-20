import 'package:wallex/core/services/ai/agents/agent_profile.dart';
import 'package:wallex/core/services/ai/agents/agent_run_result.dart';
import 'package:wallex/core/services/ai/agents/agent_runner.dart';
import 'package:wallex/core/services/ai/financial_context_builder.dart';
import 'package:wallex/core/services/ai/tools/ai_tool.dart';
import 'package:wallex/core/services/ai/tools/ai_tool_registry.dart';
import 'package:wallex/core/services/ai/tools/impl/create_transaction_tool.dart';
import 'package:wallex/core/services/ai/tools/impl/create_transfer_tool.dart';
import 'package:wallex/core/services/ai/tools/impl/get_balance_tool.dart';
import 'package:wallex/core/services/ai/tools/impl/get_budgets_tool.dart';
import 'package:wallex/core/services/ai/tools/impl/get_stats_by_category_tool.dart';
import 'package:wallex/core/services/ai/tools/impl/list_transactions_tool.dart';

/// Full chat agent for `WallexChatPage`.
///
/// Contract:
///  - `maxLoops = 3` — enough for "list → stats → budget" multi-tool chains
///    without runaway cost.
///  - `tool_choice = 'auto'` — model decides.
///  - Whitelist: all read-only tools + `create_transaction` (commit) +
///    `create_transfer`.
///  - `requiresApproval` gates `create_transaction` and `create_transfer` —
///    chat UI renders an approval bubble; read-only tools bypass.
///  - On a first-iteration stop with no tool_calls, the runner surfaces
///    [AgentRunStatus.streamFinalText] so the chat page can call
///    `streamComplete(messages)` for byte-for-byte token streaming UX.
class WallexAiAgent {
  final AgentProfile profile;
  final AgentRunner _runner;

  WallexAiAgent._({required this.profile, required AgentRunner runner})
      : _runner = runner;

  factory WallexAiAgent({
    AgentRunner? runner,
    String? modelOverride,
    double temperature = 0.3,
  }) {
    final registry = AiToolRegistry([
      GetBalanceTool(),
      ListTransactionsTool(),
      GetStatsByCategoryTool(),
      GetBudgetsTool(),
      CreateTransactionTool(execMode: AiToolExecMode.commit),
      CreateTransferTool(),
    ]);
    final profile = AgentProfile(
      name: 'wallexAssistant',
      systemPrompt: _systemPrompt,
      toolRegistry: registry,
      toolChoice: 'auto',
      maxLoops: 3,
      temperature: temperature,
      modelOverride: modelOverride,
      approvalRequiredTools: const {'create_transaction', 'create_transfer'},
    );
    return WallexAiAgent._(
      profile: profile,
      runner: runner ?? AgentRunner(),
    );
  }

  /// Run the chat agent with the current message history. If [history] is
  /// empty (plain new prompt) the runner may return [AgentRunStatus.streamFinalText]
  /// so the chat UI reuses `streamComplete` for the first no-tool reply.
  ///
  /// [history] must already contain any prior user/assistant turns but must
  /// NOT include the system prompt — the agent prepends that.
  Future<AgentRunResult> run({
    required List<Map<String, dynamic>> history,
  }) async {
    final ctx = await FinancialContextBuilder.instance.buildContext();
    final messages = <Map<String, dynamic>>[
      {
        'role': 'system',
        'content': '${profile.systemPrompt}\n\n$ctx',
      },
      ...history,
    ];
    return _runner.run(
      profile: profile,
      initialMessages: messages,
      streamFinalWhenNoToolsFirstTurn: true,
    );
  }

  /// Resume the loop after the UI resolved pending approvals. The caller must
  /// have appended `role:'tool'` messages with either the tool's commit result
  /// (on approve) or a `{"status":"user_rejected"}` payload (on reject) for
  /// each tool call that was gated.
  Future<AgentRunResult> resume({
    required List<Map<String, dynamic>> messages,
  }) async {
    return _runner.run(
      profile: profile,
      initialMessages: messages,
    );
  }

  static const String _systemPrompt =
      'Eres Wallex AI, asistente financiero personal. Respondes SIEMPRE en '
      'espanol (dialecto venezolano). Nunca inventes cifras: consulta saldos, '
      'transacciones, estadisticas y presupuestos con las tools provistas. '
      'Si el usuario pide crear una transaccion o transferencia, llama la '
      'tool correspondiente con los datos que tengas; la UI pedira confirmacion '
      'al usuario antes de escribir. Formato: negritas para montos '
      '(**\$432.50**), cursivas para porcentajes (*12% menos*), tablas con | '
      'para datos tabulares, listas con - para enumerar, 2 decimales.';
}
