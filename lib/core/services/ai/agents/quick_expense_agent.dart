import 'package:wallex/core/services/ai/agents/agent_profile.dart';
import 'package:wallex/core/services/ai/agents/agent_run_result.dart';
import 'package:wallex/core/services/ai/agents/agent_runner.dart';
import 'package:wallex/core/services/ai/financial_context_builder.dart';
import 'package:wallex/core/services/ai/tools/ai_tool.dart';
import 'package:wallex/core/services/ai/tools/ai_tool_registry.dart';
import 'package:wallex/core/services/ai/tools/impl/create_transaction_tool.dart';

/// Agent that converts a Spanish voice transcript into a single
/// `TransactionProposal` via a forced `create_transaction` tool call.
///
/// Contract:
///  - `maxLoops = 1` — one shot, no back-and-forth.
///  - `tool_choice` is forced to `create_transaction` so the model cannot
///    refuse silently.
///  - Whitelisted tools: `[create_transaction]` only.
///  - `requiresApproval` returns `false` — the review sheet (Tanda 5) is the
///    approval UI; the proposal never hits the DB at this stage.
///  - `execMode = propose` on the tool, so `TransactionService.insertTransaction`
///    is NOT called here.
class QuickExpenseAgent {
  final AgentProfile profile;
  final AgentRunner _runner;

  QuickExpenseAgent._({required this.profile, required AgentRunner runner})
      : _runner = runner;

  factory QuickExpenseAgent({
    CreateTransactionTool? createTransactionTool,
    AgentRunner? runner,
    String? modelOverride,
  }) {
    final tool = createTransactionTool ??
        CreateTransactionTool(execMode: AiToolExecMode.propose);
    final registry = AiToolRegistry([tool]);
    final profile = AgentProfile(
      name: 'quickExpense',
      systemPrompt: _systemPrompt,
      toolRegistry: registry,
      toolChoice: <String, dynamic>{
        'type': 'function',
        'function': <String, dynamic>{'name': 'create_transaction'},
      },
      maxLoops: 1,
      temperature: 0.1,
      modelOverride: modelOverride,
      approvalRequiredTools: const <String>{},
    );
    return QuickExpenseAgent._(
      profile: profile,
      runner: runner ?? AgentRunner(),
    );
  }

  /// Run the agent against a single voice transcript and return a run result
  /// carrying the emitted `TransactionProposal` (when successful).
  ///
  /// Callers (voice FAB flow) consume `result.proposals.first` and pass it to
  /// `VoiceReviewSheet` without hitting the DB.
  Future<AgentRunResult> run(String transcript) async {
    final ctx = await FinancialContextBuilder.instance.buildContext();
    final messages = <Map<String, dynamic>>[
      {
        'role': 'system',
        'content': '${profile.systemPrompt}\n\n$ctx',
      },
      {
        'role': 'user',
        'content': transcript,
      },
    ];
    return _runner.run(
      profile: profile,
      initialMessages: messages,
    );
  }

  static const String _systemPrompt =
      'Eres un extractor de gastos de voz para Wallex. Recibes una sola '
      'transcripcion en espanol venezolano (ej: "gaste 20 en uber", "compre '
      'comida por 35 dolares"). Tu unica accion permitida es llamar la tool '
      'create_transaction con los campos amount (positivo), type (income o '
      'expense), y categoryId cuando sea claro. Si el texto NO describe una '
      'transaccion financiera clara, llama la tool igualmente con amount=0 '
      'y type=expense — el review sheet rechazara o corregira. Nunca '
      'respondas texto libre; siempre tool call.';
}
