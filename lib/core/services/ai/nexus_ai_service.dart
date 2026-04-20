import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:wallex/core/services/ai/ai_completion_result.dart';
import 'package:wallex/core/services/ai/nexus_credentials_store.dart';

typedef LoadSecret = Future<String?> Function();

class NexusAiService {
  static final instance = NexusAiService._();
  NexusAiService._({
    http.Client? client,
    LoadSecret? loadApiKey,
    LoadSecret? loadModel,
    Duration requestTimeout = const Duration(seconds: 15),
  })  : _client = client ?? http.Client(),
        _loadApiKey = loadApiKey ?? NexusCredentialsStore.instance.loadApiKey,
        _loadModel = loadModel ?? NexusCredentialsStore.instance.loadModel,
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

  Stream<String> streamComplete({
    required List<Map<String, String>> messages,
    double temperature = 0.7,
    int maxTokens = 4096,
  }) async* {
    final apiKey = await _loadApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      debugPrint('NexusAiService.streamComplete ABORT: no API key configured');
      return;
    }

    final startedAt = DateTime.now();

    try {
      final request = http.Request('POST', Uri.parse('$_baseUrl$_endpoint'));
      request.headers.addAll({
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiKey',
      });
      request.body = jsonEncode({
        'stream': true,
        'temperature': temperature,
        'max_tokens': maxTokens,
        'messages': messages,
        'tool_choice': 'none',
      });

        final response = await _client
          .send(request)
          .timeout(const Duration(seconds: 60));

      final latencyMs = DateTime.now().difference(startedAt).inMilliseconds;
      debugPrint('NexusAiService.streamComplete status=${response.statusCode} latencyMs=$latencyMs');

      if (response.statusCode < 200 || response.statusCode >= 300) {
        debugPrint('NexusAiService.streamComplete ABORT: HTTP ${response.statusCode}');
        return;
      }

      String pendingBuffer = '';

      await for (final chunk in response.stream.transform(utf8.decoder)) {
        pendingBuffer += chunk;
        final lines = pendingBuffer.split('\n');
        pendingBuffer = lines.removeLast();

        for (final rawLine in lines) {
          final parsed = _extractSseContent(rawLine);
          if (parsed == null) continue;
          if (parsed == '[DONE]') return;

          final piece = _extractDeltaContent(parsed);
          if (piece != null && piece.isNotEmpty) {
            yield piece;
          }
        }
      }

      final trailing = _extractSseContent(pendingBuffer);
      if (trailing != null && trailing != '[DONE]') {
        final piece = _extractDeltaContent(trailing);
        if (piece != null && piece.isNotEmpty) {
          yield piece;
        }
      }
    } catch (e, st) {
      debugPrint('NexusAiService.streamComplete ERROR: $e');
      debugPrint('$st');
      return;
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

  String? _extractDeltaContent(String jsonPayload) {
    try {
      final data = jsonDecode(jsonPayload);
      if (data is! Map<String, dynamic>) return null;

      final choices = data['choices'];
      if (choices is! List || choices.isEmpty) return null;

      final firstChoice = choices.first;
      if (firstChoice is! Map<String, dynamic>) return null;

      final delta = firstChoice['delta'];
      if (delta is! Map<String, dynamic>) return null;

      final content = delta['content'];
      return content is String ? content : null;
    } catch (_) {
      return null;
    }
  }
}
