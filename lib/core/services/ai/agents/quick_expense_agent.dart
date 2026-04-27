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
      // Single forced tool call with short args — 2k is already generous.
      // Keeps us under OpenRouter free-tier affordability caps.
      maxTokens: 2048,
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
    final currentDate = DateTime.now().toIso8601String();
    final systemContent =
        '${profile.systemPrompt}\n\nFecha de hoy: $currentDate.\n\n$ctx';
    final messages = <Map<String, dynamic>>[
      {
        'role': 'system',
        'content': systemContent,
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
      'comida por 35 dolares").\n\n'
      'REGLA DE ORO (no negociable): TU UNICA SALIDA VALIDA ES UNA LLAMADA '
      'A LA TOOL create_transaction. NUNCA respondas con texto libre. NUNCA '
      'devuelvas content vacio ni un string en blanco. Si entiendes amount '
      'y type, INVOCA la tool ya — aunque no puedas llenar los campos '
      'opcionales. Quedarte callado o devolver "" NO es opcion bajo ninguna '
      'circunstancia.\n\n'
      'CAMPOS DE LA TOOL:\n'
      '- Requeridos (siempre incluir): amount (numero positivo), type '
      '("income" o "expense").\n'
      '- Opcionales (incluir SOLO cuando son claros en la transcripcion): '
      'currency, accountId, categoryId, date. Si alguno no es claro, OMITELO '
      'del tool call — NO lo inventes, NO lo dejes vacio, simplemente no lo '
      'pongas en los argumentos.\n'
      '- Si el texto NO describe una transaccion financiera clara, llama la '
      'tool igualmente con amount=0 y type=expense (el review sheet '
      'rechazara o corregira). Nunca te quedes sin invocarla.\n\n'
      'IMPORTANTE sobre la divisa: si el usuario menciona una divisa '
      'explicita (ej: "gaste 10 dolares", "5 euros", "cobre en bolivares"), '
      'incluye el campo currency con el codigo ISO 4217 en mayusculas: '
      'dolares/USD, bolivares/VES, euros/EUR, pesos colombianos/COP. Si NO '
      'menciona divisa, OMITE currency y la app usara la divisa de la cuenta.\n\n'
      'IMPORTANTE sobre la cuenta: elige accountId de la lista de "Cuentas '
      'del usuario" abajo cuya divisa coincida con la que dijo el usuario. '
      'Si dijo "dolares"/"\$"/"USD" -> elige una cuenta USD. Si dijo '
      '"bolivares"/"Bs"/"VES" -> elige una cuenta VES. Si dijo "euros" -> '
      'EUR, etc. Si hay varias cuentas en esa divisa, usa la primera de la '
      'lista. Si no hay ninguna en esa divisa, OMITE accountId (la app '
      'elegira por defecto). Si el usuario NO menciona divisa, tambien '
      'OMITE accountId.\n\n'
      'IMPORTANTE sobre la fecha: si el usuario NO menciona una fecha '
      'explicita (ej: "ayer", "el lunes", "hace 3 dias"), NO incluyas el '
      'campo date en el tool call — dejalo ausente. La aplicacion usara la '
      'fecha de hoy automaticamente. NUNCA inventes una fecha ni uses '
      'fechas de tu entrenamiento; solo incluye date cuando el usuario la '
      'mencione claramente, y entonces usa formato ISO 8601 basado en la '
      '"Fecha de hoy" que se te proporciona abajo.\n\n'
      'IMPORTANTE sobre la categoria: si es un expense, INTENTA mapear la '
      'descripcion del gasto a una categoria de la lista "Categorias de '
      'gasto" que se inyecta mas abajo en el contexto. Ejemplos de mapeo '
      'tipico:\n'
      '- "almuerzo", "comida", "almorce", "cene", "desayune", "cafe", '
      '"restaurante", "mercado", "comi" -> categoria de Alimentacion / '
      'Restaurantes / Comida.\n'
      '- "uber", "taxi", "gasolina", "metro", "bus", "pasaje", "transporte" '
      '-> categoria de Transporte.\n'
      '- "luz", "agua", "internet", "renta", "alquiler", "condominio", '
      '"gas" -> categoria de Vivienda / Servicios.\n'
      '- "doctor", "medicina", "farmacia", "consulta", "medico", "pastillas" '
      '-> categoria de Salud.\n'
      '- "cine", "spotify", "netflix", "concierto", "juego", "fiesta" -> '
      'categoria de Entretenimiento.\n'
      '- "ropa", "zapatos", "tienda" -> categoria de Compras / Ropa si '
      'existe.\n'
      'Usa el categoryId EXACTO tal cual aparece en la lista (los IDs vienen '
      'con formato "- ID: Nombre"). Si ninguna categoria de la lista hace '
      'match claro con la descripcion, OMITE categoryId — la app usara '
      '"Otros Gastos" por default. NO inventes IDs.\n\n'
      'Para income (ingresos), aplica el mismo principio con la lista '
      '"Categorias de ingreso" si la transcripcion es clara (ej: "cobre el '
      'sueldo" -> categoria de Sueldo / Salario; "me pagaron freelance" -> '
      'Freelance / Otros Ingresos). Si no hay match claro, OMITE '
      'categoryId.\n\n'
      'EJEMPLOS DE COMPORTAMIENTO ESPERADO:\n'
      '1) Transcripcion: "gaste 20 en almuerzo"\n'
      '   -> create_transaction(amount=20, type="expense", '
      'categoryId=<id de Alimentacion de la lista>)\n'
      '   (sin currency, sin accountId, sin date — no se mencionan; pero '
      'categoryId SE incluye porque "almuerzo" mapea a Alimentacion.)\n'
      '2) Transcripcion: "compre cafe por 5 dolares"\n'
      '   -> create_transaction(amount=5, type="expense", currency="USD", '
      'categoryId=<id de Alimentacion de la lista>)\n'
      '   (currency claro; categoryId mapea cafe a Alimentacion; accountId '
      'solo si hay una cuenta USD en la lista; date se omite.)\n'
      '3) Transcripcion: "cobre 100 bolivares ayer"\n'
      '   -> create_transaction(amount=100, type="income", currency="VES", '
      'accountId=<id de cuenta VES si existe>, '
      'categoryId=<id de Sueldo/Otros Ingresos si match>, '
      'date=<ISO de ayer>)\n'
      '   (todos los campos claros se incluyen; los que no, se omiten.)\n\n'
      'RECUERDA: aunque la transcripcion sea ambigua, SIEMPRE invocas '
      'create_transaction. Devolver content vacio es un bug — no lo hagas.';
}
