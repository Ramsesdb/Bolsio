import 'ai_tool.dart';

/// Registry of [AiTool] instances keyed by their stable [AiTool.name].
///
/// An [AiToolRegistry] is typically scoped to a single [AgentProfile] so a
/// profile cannot accidentally dispatch tools outside its declared set
/// (ai-tools spec §Agent Profile Isolation).
class AiToolRegistry {
  final Map<String, AiTool> _tools;

  AiToolRegistry._(this._tools);

  factory AiToolRegistry(Iterable<AiTool> tools) {
    final map = <String, AiTool>{};
    for (final tool in tools) {
      if (map.containsKey(tool.name)) {
        throw StateError('Duplicate AiTool name: ${tool.name}');
      }
      map[tool.name] = tool;
    }
    return AiToolRegistry._(map);
  }

  /// Whether the registry contains a tool with this name.
  bool has(String name) => _tools.containsKey(name);

  /// Look up a tool by name. Returns `null` when unknown so the agent loop
  /// can surface a structured `unknown_tool` error back to the model.
  AiTool? lookup(String name) => _tools[name];

  /// All registered tool names (stable ordering, insertion order).
  Iterable<String> get names => _tools.keys;

  /// All registered tools.
  Iterable<AiTool> get tools => _tools.values;

  /// Serialize to the OpenAI `tools[]` JSON shape:
  /// `{type: 'function', function: {name, description, parameters}}`.
  /// Compatible with OpenAI, Groq, OpenRouter, and Nexus tool calling.
  List<Map<String, dynamic>> toOpenAiTools() {
    return _tools.values
        .map((t) => <String, dynamic>{
              'type': 'function',
              'function': <String, dynamic>{
                'name': t.name,
                'description': t.description,
                'parameters': t.parametersSchema,
              },
            })
        .toList(growable: false);
  }

  /// Dispatch a tool call. Returns an `unknown_tool` error result if [name]
  /// is not registered so the agent loop can continue.
  Future<AiToolResult> dispatch(
    String name,
    Map<String, dynamic> args,
  ) async {
    final tool = _tools[name];
    if (tool == null) {
      return AiToolResult.error(
        'Tool "$name" is not registered in this profile.',
        code: 'unknown_tool',
      );
    }
    try {
      return await tool.execute(args);
    } catch (e) {
      return AiToolResult.error(
        'Tool "$name" threw: $e',
        code: 'tool_exception',
      );
    }
  }
}
