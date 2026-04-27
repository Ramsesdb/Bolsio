import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:wallex/core/services/ai/ai_completion_result.dart';
import 'package:wallex/core/services/ai/ai_credentials_store.dart';
import 'package:wallex/core/services/ai/ai_provider_type.dart';

typedef LoadSecret = Future<String?> Function();

/// Default Nexus credentials reader backed by the new BYOK store.
/// Returns the stored API key for the Nexus provider, or `null` when the
/// user has not configured Nexus credentials.
@Deprecated('Use AiService.instance instead')
Future<String?> _defaultNexusApiKeyLoader() async {
  final creds = await AiCredentialsStore.instance
      .loadCredentials(AiProviderType.nexus);
  return creds?.apiKey;
}

/// Default Nexus model reader backed by the new BYOK store. Falls back to
/// the legacy multimodal default (`openai/gpt-4.1-mini`) when nothing is
/// stored — preserving the pre-BYOK behaviour for the multimodal/tools
/// codepaths that still live on this service.
@Deprecated('Use AiService.instance instead')
Future<String?> _defaultNexusModelLoader() async {
  final creds = await AiCredentialsStore.instance
      .loadCredentials(AiProviderType.nexus);
  final model = creds?.model;
  if (model == null || model.trim().isEmpty) {
    return 'openai/gpt-4.1-mini';
  }
  return model;
}

@Deprecated('Use AiService.instance instead')
class NexusAiService {
  static final instance = NexusAiService._();
  NexusAiService._({
    http.Client? client,
    LoadSecret? loadApiKey,
    LoadSecret? loadModel,
    Duration requestTimeout = const Duration(seconds: 15),
  })  : _client = client ?? http.Client(),
        _loadApiKey = loadApiKey ?? _defaultNexusApiKeyLoader,
        _loadModel = loadModel ?? _defaultNexusModelLoader,
        _requestTimeout = requestTimeout;

  factory NexusAiService.forTesting({
    required http.Client client,
    required LoadSecret loadApiKey,
    LoadSecret? loadModel,
    Duration requestTimeout = const Duration(seconds: 15),
  }) {
    return NexusAiService._(
      client: client,
      loadApiKey: loadApiKey,
      loadModel: loadModel,
      requestTimeout: requestTimeout,
    );
  }

  static const _baseUrl = 'https://api.ramsesdb.tech';
  static const _endpoint = '/v1/chat/completions';
  static const _defaultMultimodalModel = 'openai/gpt-4.1-mini';

  final http.Client _client;
  final LoadSecret _loadApiKey;
  final LoadSecret _loadModel;
  final Duration _requestTimeout;

  Future<String?> complete({
    required List<Map<String, String>> messages,
    double temperature = 0.2,
    int maxTokens = 2048,
  }) async {
    final apiKey = await _loadApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      debugPrint('NexusAiService.complete ABORT: no API key configured');
      return null;
    }

    final startedAt = DateTime.now();

    try {
      final response = await _client
          .post(
            Uri.parse('$_baseUrl$_endpoint'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $apiKey',
            },
            body: jsonEncode({
              'stream': false,
              'temperature': temperature,
              'max_tokens': maxTokens,
              'messages': messages,
            }),
          )
          .timeout(_requestTimeout);

      final latencyMs = DateTime.now().difference(startedAt).inMilliseconds;
      debugPrint('NexusAiService.complete status=${response.statusCode} latencyMs=$latencyMs');

      if (response.statusCode < 200 || response.statusCode >= 300) {
        return null;
      }

      final data = jsonDecode(response.body);
      final choices = data is Map<String, dynamic> ? data['choices'] : null;
      if (choices is! List || choices.isEmpty) return null;

      final firstChoice = choices.first;
      if (firstChoice is! Map<String, dynamic>) return null;

      final message = firstChoice['message'];
      if (message is! Map<String, dynamic>) return null;

      final content = message['content'];
      if (content is String && content.trim().isNotEmpty) {
        return content.trim();
      }

      return null;
    } catch (e, st) {
      debugPrint('NexusAiService.complete ERROR: $e');
      debugPrint('$st');
      return null;
    }
  }

  Future<String?> completeMultimodal({
    required String systemPrompt,
    required String userPrompt,
    required String imageBase64,
    double temperature = 0.1,
    int maxTokens = 2048,
  }) async {
    final apiKey = await _loadApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      debugPrint('NexusAiService.completeMultimodal ABORT: no API key configured');
      return null;
    }

    final model = (await _loadModel())?.trim();
    final startedAt = DateTime.now();

    try {
      final response = await _client
          .post(
            Uri.parse('$_baseUrl$_endpoint'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $apiKey',
            },
            body: jsonEncode({
              'model': (model == null || model.isEmpty)
                  ? _defaultMultimodalModel
                  : model,
              'stream': false,
              'temperature': temperature,
              'max_tokens': maxTokens,
              'messages': [
                {
                  'role': 'system',
                  'content': systemPrompt,
                },
                {
                  'role': 'user',
                  'content': [
                    {
                      'type': 'text',
                      'text': userPrompt,
                    },
                    {
                      'type': 'image_url',
                      'image_url': {
                        'url': 'data:image/jpeg;base64,$imageBase64',
                      },
                    },
                  ],
                },
              ],
            }),
          )
          .timeout(_requestTimeout);

      final latencyMs = DateTime.now().difference(startedAt).inMilliseconds;
      debugPrint(
        'NexusAiService.completeMultimodal status=${response.statusCode} latencyMs=$latencyMs',
      );

      if (response.statusCode < 200 || response.statusCode >= 300) {
        final bodyPreview = response.body.length > 200
            ? '${response.body.substring(0, 200)}…'
            : response.body;
        debugPrint(
          'NexusAiService.completeMultimodal non-200 status=${response.statusCode} body=$bodyPreview',
        );
        return null;
      }

      final dynamic data;
      try {
        data = jsonDecode(response.body);
      } catch (_) {
        final bodyPreview = response.body.length > 200
            ? '${response.body.substring(0, 200)}…'
            : response.body;
        debugPrint(
          'NexusAiService.completeMultimodal response body not JSON: $bodyPreview',
        );
        return null;
      }

      final choices = data is Map<String, dynamic> ? data['choices'] : null;
      if (choices is! List || choices.isEmpty) {
        debugPrint(
          'NexusAiService.completeMultimodal response missing choices[] — returning null',
        );
        return null;
      }

      final firstChoice = choices.first;
      if (firstChoice is! Map<String, dynamic>) {
        debugPrint(
          'NexusAiService.completeMultimodal choices[0] not a Map — returning null',
        );
        return null;
      }

      final message = firstChoice['message'];
      if (message is! Map<String, dynamic>) {
        debugPrint(
          'NexusAiService.completeMultimodal choices[0].message not a Map — returning null',
        );
        return null;
      }

      final content = message['content'];
      if (content is String && content.trim().isNotEmpty) {
        return content.trim();
      }

      debugPrint(
        'NexusAiService.completeMultimodal choices[0].message.content empty or non-string — returning null',
      );
      return null;
    } on TimeoutException {
      rethrow;
    } catch (e, st) {
      debugPrint('NexusAiService.completeMultimodal ERROR: $e');
      debugPrint('$st');
      return null;
    }
  }

  /// Non-streaming chat completion with tool-calling support.
  ///
  /// Sends [messages] (free-form OpenAI-compatible shape) along with [tools]
  /// and [toolChoice] to the gateway. Returns an [AiCompletionResult] whose
  /// [AiCompletionResult.finishReason] tells the caller what to do next:
  /// dispatch tool calls ([AiCompletionFinishReason.toolCalls]) or render the
  /// final textual content ([AiCompletionFinishReason.stop]).
  ///
  /// This method does NOT run the tool loop itself — the agent layer owns the
  /// loop so it can interleave approval gating and UI events.
  ///
  /// [toolChoice] accepts either the string sentinels `'auto' | 'none' |
  /// 'required'` or a map like
  /// `{'type':'function','function':{'name':'create_transaction'}}`.
  Future<AiCompletionResult> completeWithTools({
    required List<Map<String, dynamic>> messages,
    required List<Map<String, dynamic>> tools,
    Object toolChoice = 'auto',
    String? model,
    double temperature = 0.2,
    int maxTokens = 2048,
  }) async {
    final apiKey = await _loadApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      debugPrint(
        'NexusAiService.completeWithTools ABORT: no API key configured',
      );
      return const AiCompletionResult(
        finishReason: AiCompletionFinishReason.unavailable,
        error: 'missing_api_key',
      );
    }

    final resolvedModel = (model?.trim().isNotEmpty ?? false)
        ? model!.trim()
        : ((await _loadModel())?.trim().isNotEmpty ?? false
            ? (await _loadModel())!.trim()
            : _defaultMultimodalModel);

    final startedAt = DateTime.now();

    final body = <String, dynamic>{
      'model': resolvedModel,
      'stream': false,
      'temperature': temperature,
      'max_tokens': maxTokens,
      'messages': messages,
      'tools': tools,
      'tool_choice': toolChoice,
    };

    final encodedBody = jsonEncode(body);
    final uri = Uri.parse('$_baseUrl$_endpoint');
    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $apiKey',
    };

    try {
      // Retry once on transient 5xx (502/503/504 — Nexus gateway / upstream
      // provider hiccups) with a short backoff. Anything else is returned
      // verbatim so the agent layer can decide what to do.
      http.Response response = await _client
          .post(uri, headers: headers, body: encodedBody)
          .timeout(_requestTimeout);

      if (_isRetryableGatewayError(response.statusCode)) {
        debugPrint(
          'NexusAiService.completeWithTools transient status=${response.statusCode} — retrying once in 500ms',
        );
        await Future<void>.delayed(const Duration(milliseconds: 500));
        response = await _client
            .post(uri, headers: headers, body: encodedBody)
            .timeout(_requestTimeout);
        debugPrint(
          'NexusAiService.completeWithTools retry status=${response.statusCode}',
        );
      }

      final latencyMs = DateTime.now().difference(startedAt).inMilliseconds;
      debugPrint(
        'NexusAiService.completeWithTools status=${response.statusCode} latencyMs=$latencyMs',
      );

      if (response.statusCode < 200 || response.statusCode >= 300) {
        final preview = response.body.length > 200
            ? '${response.body.substring(0, 200)}…'
            : response.body;
        debugPrint(
          'NexusAiService.completeWithTools non-2xx body=$preview',
        );
        // Tag gateway-level transient failures distinctly so the UI can show
        // a "servicio no disponible" message instead of confusing the user
        // with a generic "couldn't understand you" error.
        final code = response.statusCode;
        final errorTag = _isRetryableGatewayError(code)
            ? 'gateway_unavailable'
            : 'http_$code';
        return AiCompletionResult(
          finishReason: AiCompletionFinishReason.error,
          error: errorTag,
          messages: messages,
        );
      }

      final dynamic data;
      try {
        data = jsonDecode(response.body);
      } catch (_) {
        return AiCompletionResult(
          finishReason: AiCompletionFinishReason.error,
          error: 'invalid_json_response',
          messages: messages,
        );
      }

      if (data is! Map<String, dynamic>) {
        return AiCompletionResult(
          finishReason: AiCompletionFinishReason.error,
          error: 'response_not_object',
          messages: messages,
        );
      }

      final choices = data['choices'];
      if (choices is! List || choices.isEmpty) {
        return AiCompletionResult(
          finishReason: AiCompletionFinishReason.error,
          error: 'missing_choices',
          messages: messages,
        );
      }

      final firstChoice = choices.first;
      if (firstChoice is! Map<String, dynamic>) {
        return AiCompletionResult(
          finishReason: AiCompletionFinishReason.error,
          error: 'choice_not_object',
          messages: messages,
        );
      }

      final message = firstChoice['message'];
      if (message is! Map<String, dynamic>) {
        return AiCompletionResult(
          finishReason: AiCompletionFinishReason.error,
          error: 'message_not_object',
          messages: messages,
        );
      }

      final rawContent = message['content'];
      final content = rawContent is String ? rawContent : null;

      final rawToolCalls = message['tool_calls'];
      final toolCalls = <AiToolCall>[];
      if (rawToolCalls is List) {
        for (final call in rawToolCalls) {
          if (call is! Map) continue;
          final rawId = call['id'];
          final fn = call['function'];
          if (fn is! Map) continue;
          final fnName = fn['name'];
          final fnArgs = fn['arguments'];
          if (fnName is! String || fnName.isEmpty) continue;
          // Some providers (or malformed proxies) return an empty/missing id.
          // Both Groq and OpenAI reject `role:'tool'` messages without a
          // matching `tool_call_id`, so synthesize a stable placeholder here
          // and mirror it on the assistant message so the pair stays in sync.
          final String id = (rawId is String && rawId.isNotEmpty)
              ? rawId
              : 'call_${DateTime.now().microsecondsSinceEpoch}_${toolCalls.length}';
          // Providers sometimes return arguments as a String (OpenAI style) and
          // sometimes as an already-decoded Map (some proxies). Normalize to a
          // JSON string — the registry dispatcher re-decodes it.
          final String argumentsJson;
          if (fnArgs is String) {
            argumentsJson = fnArgs.isEmpty ? '{}' : fnArgs;
          } else if (fnArgs is Map) {
            argumentsJson = jsonEncode(fnArgs);
          } else {
            argumentsJson = '{}';
          }
          toolCalls.add(AiToolCall(
            id: id,
            name: fnName,
            argumentsJson: argumentsJson,
          ));
        }
      }

      if (toolCalls.isNotEmpty) {
        return AiCompletionResult(
          content: content,
          toolCalls: toolCalls,
          finishReason: AiCompletionFinishReason.toolCalls,
          messages: messages,
        );
      }

      return AiCompletionResult(
        content: (content != null && content.trim().isNotEmpty)
            ? content.trim()
            : null,
        finishReason: AiCompletionFinishReason.stop,
        messages: messages,
      );
    } on TimeoutException {
      return AiCompletionResult(
        finishReason: AiCompletionFinishReason.error,
        error: 'timeout',
        messages: messages,
      );
    } catch (e, st) {
      debugPrint('NexusAiService.completeWithTools ERROR: $e');
      debugPrint('$st');
      return AiCompletionResult(
        finishReason: AiCompletionFinishReason.error,
        error: '$e',
        messages: messages,
      );
    }
  }

  /// Streaming chat completion with tool-calling support — single-roundtrip.
  ///
  /// Sends ONE POST with `stream: true` + `tools` enabled. As SSE chunks arrive
  /// it dispatches them to the right callback at runtime:
  ///
  ///  - `onTextChunk(delta)` — fired for every non-empty `delta.content` piece
  ///    so the UI can render token-by-token.
  ///  - `onToolCalls(calls)` — fired exactly once when the stream closes with
  ///    `finish_reason: "tool_calls"`. The accumulator merges fragmented
  ///    `delta.tool_calls` entries by index (first chunk carries id/name,
  ///    subsequent chunks append `function.arguments`).
  ///
  /// The future resolves with an [AiCompletionResult] whose [finishReason] is
  /// either [AiCompletionFinishReason.stop] (plain text reply, fully streamed
  /// via `onTextChunk`) or [AiCompletionFinishReason.toolCalls] (tools were
  /// emitted; caller must dispatch and re-invoke the loop).
  ///
  /// This replaces the old two-call flow (`completeWithTools` non-streaming +
  /// a separate `streamComplete` for the final text) with a single API call.
  Future<AiCompletionResult> streamWithTools({
    required List<Map<String, dynamic>> messages,
    required List<Map<String, dynamic>> tools,
    Object toolChoice = 'auto',
    String? model,
    double temperature = 0.2,
    int maxTokens = 2048,
    void Function(String chunk)? onTextChunk,
    void Function(List<AiToolCall> calls)? onToolCalls,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final apiKey = await _loadApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      debugPrint(
        'NexusAiService.streamWithTools ABORT: no API key configured',
      );
      return const AiCompletionResult(
        finishReason: AiCompletionFinishReason.unavailable,
        error: 'missing_api_key',
      );
    }

    final resolvedModel = (model?.trim().isNotEmpty ?? false)
        ? model!.trim()
        : ((await _loadModel())?.trim().isNotEmpty ?? false
            ? (await _loadModel())!.trim()
            : _defaultMultimodalModel);

    final startedAt = DateTime.now();

    final body = <String, dynamic>{
      'model': resolvedModel,
      'stream': true,
      'temperature': temperature,
      'max_tokens': maxTokens,
      'messages': messages,
      'tools': tools,
      'tool_choice': toolChoice,
    };

    try {
      final request = http.Request('POST', Uri.parse('$_baseUrl$_endpoint'));
      request.headers.addAll({
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiKey',
      });
      request.body = jsonEncode(body);

      final response = await _client.send(request).timeout(timeout);

      final latencyMs = DateTime.now().difference(startedAt).inMilliseconds;
      debugPrint(
        'NexusAiService.streamWithTools status=${response.statusCode} latencyMs=$latencyMs',
      );

      if (response.statusCode < 200 || response.statusCode >= 300) {
        // Drain the body for a small preview so the UI/logs know what failed.
        String preview = '';
        try {
          final bytes = await response.stream.toBytes();
          final raw = utf8.decode(bytes, allowMalformed: true);
          preview = raw.length > 200 ? '${raw.substring(0, 200)}…' : raw;
        } catch (_) {}
        debugPrint(
          'NexusAiService.streamWithTools non-2xx body=$preview',
        );
        final code = response.statusCode;
        final errorTag = _isRetryableGatewayError(code)
            ? 'gateway_unavailable'
            : 'http_$code';
        return AiCompletionResult(
          finishReason: AiCompletionFinishReason.error,
          error: errorTag,
          messages: messages,
        );
      }

      // Accumulators.
      final contentBuffer = StringBuffer();
      final toolAcc = <int, _ToolCallAccumulator>{};
      String? finishReason;
      String pending = '';

      void handleSseLine(String rawLine) {
        final payload = _extractSseContent(rawLine);
        if (payload == null) return;
        if (payload == '[DONE]') {
          finishReason ??= 'stop';
          return;
        }

        final Map<String, dynamic>? data;
        try {
          final decoded = jsonDecode(payload);
          data = decoded is Map<String, dynamic> ? decoded : null;
        } catch (_) {
          return;
        }
        if (data == null) return;

        final choices = data['choices'];
        if (choices is! List || choices.isEmpty) return;
        final first = choices.first;
        if (first is! Map<String, dynamic>) return;

        final fr = first['finish_reason'];
        if (fr is String && fr.isNotEmpty) {
          finishReason = fr;
        }

        final delta = first['delta'];
        if (delta is! Map<String, dynamic>) return;

        final contentPiece = delta['content'];
        if (contentPiece is String && contentPiece.isNotEmpty) {
          contentBuffer.write(contentPiece);
          if (onTextChunk != null) onTextChunk(contentPiece);
        }

        final tcDeltas = delta['tool_calls'];
        if (tcDeltas is List) {
          for (final entry in tcDeltas) {
            if (entry is! Map) continue;
            final idx = entry['index'];
            if (idx is! int) continue;
            final acc = toolAcc.putIfAbsent(
              idx,
              () => _ToolCallAccumulator(),
            );

            final id = entry['id'];
            if (id is String && id.isNotEmpty) acc.id = id;

            final fn = entry['function'];
            if (fn is Map) {
              final name = fn['name'];
              if (name is String && name.isNotEmpty) acc.name = name;
              final args = fn['arguments'];
              if (args is String && args.isNotEmpty) {
                acc.argumentsBuffer.write(args);
              }
            }
          }
        }
      }

      await for (final chunk in response.stream.transform(utf8.decoder)) {
        pending += chunk;
        final lines = pending.split('\n');
        pending = lines.removeLast();
        for (final line in lines) {
          handleSseLine(line);
        }
      }
      if (pending.isNotEmpty) {
        handleSseLine(pending);
      }

      // Build the tool-call list ordered by index.
      final orderedIndexes = toolAcc.keys.toList()..sort();
      final toolCalls = <AiToolCall>[];
      for (final idx in orderedIndexes) {
        final acc = toolAcc[idx]!;
        final name = acc.name;
        if (name == null || name.isEmpty) continue;
        final id = (acc.id != null && acc.id!.isNotEmpty)
            ? acc.id!
            : 'call_${DateTime.now().microsecondsSinceEpoch}_$idx';
        final argsJson = acc.argumentsBuffer.toString();
        final isValid = acc.finalizeIsValid();
        if (!isValid) {
          debugPrint(
            'NexusAiService.streamWithTools tool="$name" '
            'invalid_arguments_json bufferLen=${argsJson.length}',
          );
        }
        toolCalls.add(AiToolCall(
          id: id,
          name: name,
          argumentsJson: argsJson.isEmpty ? '{}' : argsJson,
          hasInvalidArguments: !isValid,
        ));
      }

      // Decide finish reason.
      // Some providers omit finish_reason but emit tool_calls — detect by
      // presence of accumulated calls. Likewise, treat absent finish_reason
      // with content as a normal stop.
      final isToolCalls = (finishReason == 'tool_calls') ||
          (finishReason == null && toolCalls.isNotEmpty);

      if (isToolCalls) {
        if (onToolCalls != null && toolCalls.isNotEmpty) {
          onToolCalls(toolCalls);
        }
        return AiCompletionResult(
          content: contentBuffer.isEmpty ? null : contentBuffer.toString(),
          toolCalls: toolCalls,
          finishReason: AiCompletionFinishReason.toolCalls,
          messages: messages,
        );
      }

      final finalText = contentBuffer.toString();
      return AiCompletionResult(
        content: finalText.trim().isEmpty ? null : finalText,
        finishReason: AiCompletionFinishReason.stop,
        messages: messages,
      );
    } on TimeoutException {
      return AiCompletionResult(
        finishReason: AiCompletionFinishReason.error,
        error: 'timeout',
        messages: messages,
      );
    } catch (e, st) {
      debugPrint('NexusAiService.streamWithTools ERROR: $e');
      debugPrint('$st');
      return AiCompletionResult(
        finishReason: AiCompletionFinishReason.error,
        error: '$e',
        messages: messages,
      );
    }
  }

  /// Returns `true` when [status] is one of the transient gateway/upstream
  /// failures (502/503/504) that are worth retrying exactly once. The Nexus
  /// gateway relays these as-is when the upstream LLM provider hiccups.
  static bool _isRetryableGatewayError(int status) {
    return status == 502 || status == 503 || status == 504;
  }

  String? _extractSseContent(String rawLine) {
    final line = rawLine.trim();
    if (line.isEmpty) return null;
    if (line.startsWith(':')) return null;
    if (!line.startsWith('data:')) return null;

    final data = line.substring(5).trim();
    if (data.isEmpty) return null;
    return data;
  }
}

/// Internal mutable accumulator for one streamed `tool_call` indexed slot.
class _ToolCallAccumulator {
  String? id;
  String? name;
  final StringBuffer argumentsBuffer = StringBuffer();

  /// Validates the accumulated arguments buffer once the stream closes.
  /// An empty buffer is treated as a valid `{}` (some providers omit
  /// `arguments` for parameterless tools). A non-empty buffer that fails
  /// `jsonDecode` is flagged so callers can surface the error.
  bool finalizeIsValid() {
    final raw = argumentsBuffer.toString();
    if (raw.isEmpty) return true;
    try {
      jsonDecode(raw);
      return true;
    } catch (_) {
      return false;
    }
  }
}
