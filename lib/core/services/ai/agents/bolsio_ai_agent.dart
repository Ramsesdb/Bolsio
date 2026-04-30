import 'package:bolsio/core/services/ai/agents/agent_profile.dart';
import 'package:bolsio/core/services/ai/agents/agent_run_result.dart';
import 'package:bolsio/core/services/ai/agents/agent_runner.dart';
import 'package:bolsio/core/services/ai/financial_context_builder.dart';
import 'package:bolsio/core/services/ai/tools/ai_tool.dart';
import 'package:bolsio/core/services/ai/tools/ai_tool_registry.dart';
import 'package:bolsio/core/services/ai/tools/impl/create_transaction_tool.dart';
import 'package:bolsio/core/services/ai/tools/impl/create_transfer_tool.dart';
import 'package:bolsio/core/services/ai/tools/impl/get_balance_tool.dart';
import 'package:bolsio/core/services/ai/tools/impl/get_budgets_tool.dart';
import 'package:bolsio/core/services/ai/tools/impl/get_stats_by_category_tool.dart';
import 'package:bolsio/core/services/ai/tools/impl/list_transactions_tool.dart';

/// Full chat agent for `BolsioChatPage`.
///
/// Contract:
///  - `maxLoops = 3` — enough for "list → stats → budget" multi-tool chains
///    without runaway cost.
///  - `tool_choice = 'auto'` — model decides.
///  - Whitelist: all read-only tools + `create_transaction` (commit) +
///    `create_transfer`.
///  - `requiresApproval` gates `create_transaction` and `create_transfer` —
///    chat UI renders an approval bubble; read-only tools bypass.
///  - The runner streams text chunks live via the `onTextChunk` callback the
///    chat page wires up, so plain-text replies render token-by-token without
///    a second roundtrip to the gateway.
class BolsioAiAgent {
  final AgentProfile profile;
  final AgentRunner _runner;

  BolsioAiAgent._({required this.profile, required AgentRunner runner})
      : _runner = runner;

  factory BolsioAiAgent({
    AgentRunner? runner,
    String? modelOverride,
    double temperature = 0.3,
    int maxTokens = 4096,
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
      name: 'bolsioAssistant',
      systemPrompt: '',
      toolRegistry: registry,
      toolChoice: 'auto',
      maxLoops: 3,
      temperature: temperature,
      // Conversational replies + occasional multi-tool chains. 4k stays well
      // under free-tier upstream caps while leaving room for long answers.
      maxTokens: maxTokens,
      modelOverride: modelOverride,
      approvalRequiredTools: const {'create_transaction', 'create_transfer'},
    );
    return BolsioAiAgent._(
      profile: profile,
      runner: runner ?? AgentRunner(),
    );
  }

  /// Run the chat agent with the current message history.
  ///
  /// [history] must already contain any prior user/assistant turns but must
  /// NOT include the system prompt — the agent prepends that.
  ///
  /// Pass [onTextChunk] to receive streamed text deltas live (token-by-token
  /// UX). The same callback is invoked across every iteration of the tool
  /// loop, so the UI sees the model's textual reply as soon as it starts
  /// arriving — no second gateway roundtrip required.
  Future<AgentRunResult> run({
    required List<Map<String, dynamic>> history,
    void Function(String chunk)? onTextChunk,
  }) async {
    final ctx = await FinancialContextBuilder.instance.buildContext();
    final messages = <Map<String, dynamic>>[
      {
        'role': 'system',
        'content': '${_buildSystemPrompt(DateTime.now())}\n\n$ctx',
      },
      ...history,
    ];
    return _runner.run(
      profile: profile,
      initialMessages: messages,
      onTextChunk: onTextChunk,
    );
  }

  /// Resume the loop after the UI resolved pending approvals. The caller must
  /// have appended `role:'tool'` messages with either the tool's commit result
  /// (on approve) or a `{"status":"user_rejected"}` payload (on reject) for
  /// each tool call that was gated.
  Future<AgentRunResult> resume({
    required List<Map<String, dynamic>> messages,
    void Function(String chunk)? onTextChunk,
  }) async {
    return _runner.run(
      profile: profile,
      initialMessages: messages,
      onTextChunk: onTextChunk,
    );
  }

  static String _buildSystemPrompt(DateTime now) {
    final fecha = _formatFechaLarga(now);
    final mesActual = _nombreMes(now.month);
    final anio = now.year;
    return 'Eres Bolsi, el asistente financiero personal de Bolsio. Hablas de forma cálida y cercana, como un compañero de bolsillo que ayuda al usuario a entender sus finanzas. Respondes SIEMPRE en '
        'espanol (dialecto venezolano).\n\n'
        'CONTEXTO TEMPORAL (autoridad maxima sobre fechas):\n'
        '- Hoy es $fecha.\n'
        '- "este mes" = del 1 de $mesActual de $anio hasta hoy.\n'
        '- "mes pasado" = el mes calendario anterior completo.\n'
        '- "este ano" = del 1 de enero de $anio hasta hoy.\n'
        '- Cuando llames a herramientas con fromDate/toDate, calcula esas '
        'fechas a partir de hoy. NUNCA uses fechas anteriores a 2024 salvo '
        'que el usuario las pida explicitamente.\n\n'
        'REGLAS CRITICAS DE USO DE TOOLS (zero excepciones):\n'
        '- Para CUALQUIER pregunta sobre saldos, totales de cuentas, cuanto dinero '
        'tiene el usuario, o "cuanto tengo" → SIEMPRE llama get_balance primero. '
        'Nunca inventes ni estimes saldos.\n'
        '- Para CUALQUIER pregunta sobre gastos, ingresos, desglose de gastos, '
        '"en que gaste", "como van mis gastos" o "donde se fue mi dinero" → '
        'SIEMPRE llama get_stats_by_category. Nunca escribas tablas markdown '
        'de categorias de tu cosecha.\n'
        '- Para CUALQUIER pregunta sobre transacciones especificas o historial → '
        'SIEMPRE llama list_transactions.\n'
        '- Para CUALQUIER pregunta sobre presupuestos → SIEMPRE llama get_budgets.\n'
        '- Para mutaciones (create_transaction, create_transfer) llama la tool; '
        'la UI pedira confirmacion.\n'
        '- Resuelve las fechas con el contexto temporal del usuario. Si no tienes '
        'un periodo explicito, usa el mes en curso.\n\n'
        'PROHIBIDO ABSOLUTAMENTE:\n'
        '- Fabricar cifras financieras, nombres de categorias, montos, totales, '
        'fechas o cualquier dato numerico.\n'
        '- Responder con tablas markdown (lineas con `|` y `|---|`), listas '
        'largas con montos (\$...) o desgloses por categoria cuando NO llamaste '
        'una tool en este mismo turno.\n'
        '- Si una tool devuelve vacio: responde UNA sola frase breve (ej. "No '
        'encontre movimientos en ese periodo") sin tabla vacia.\n\n'
        'FORMATO DE RESPUESTA TRAS LLAMAR UNA TOOL DE LECTURA '
        '(get_balance / get_stats_by_category / list_transactions / get_budgets):\n'
        '- La UI ya renderiza una tarjeta con los datos.\n'
        '- Tu respuesta textual debe ser 1 sola frase corta de contexto '
        '(<=200 caracteres), o vacia. Nada de repetir cifras.\n'
        '- NUNCA generes tablas markdown ni listas largas con los datos de la tool.\n\n'
        'PARA PREGUNTAS NO FINANCIERAS (uso de la app, ayuda general, saludos '
        'como "hola"/"gracias"): responde en prosa breve sin llamar tools.\n\n'
        'Estilo: negritas para montos (**\$432.50**), cursivas para porcentajes '
        '(*12% menos*), 2 decimales.';
  }

  static String _formatFechaLarga(DateTime d) {
    return '${_nombreDia(d.weekday)} ${d.day} de ${_nombreMes(d.month)} de ${d.year}';
  }

  static String _nombreDia(int weekday) {
    switch (weekday) {
      case DateTime.monday:
        return 'lunes';
      case DateTime.tuesday:
        return 'martes';
      case DateTime.wednesday:
        return 'miercoles';
      case DateTime.thursday:
        return 'jueves';
      case DateTime.friday:
        return 'viernes';
      case DateTime.saturday:
        return 'sabado';
      case DateTime.sunday:
        return 'domingo';
      default:
        return '';
    }
  }

  static String _nombreMes(int month) {
    switch (month) {
      case 1:
        return 'enero';
      case 2:
        return 'febrero';
      case 3:
        return 'marzo';
      case 4:
        return 'abril';
      case 5:
        return 'mayo';
      case 6:
        return 'junio';
      case 7:
        return 'julio';
      case 8:
        return 'agosto';
      case 9:
        return 'septiembre';
      case 10:
        return 'octubre';
      case 11:
        return 'noviembre';
      case 12:
        return 'diciembre';
      default:
        return '';
    }
  }
}
