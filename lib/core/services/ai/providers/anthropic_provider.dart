import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:bolsio/core/services/ai/ai_provider.dart';
import 'package:bolsio/core/services/ai/ai_provider_type.dart';

/// BYOK provider for Anthropic's `/v1/messages` endpoint.
///
/// Anthropic's API differs from OpenAI in two ways:
///   1. Authentication uses the `x-api-key` header (no Bearer prefix) plus
///      a mandatory `anthropic-version` header.
///   2. System prompts are NOT part of the messages list — they are passed
///      as a top-level `system` field. We extract every `role: 'system'`
///      entry from the input, concatenate their `content` with newlines,
///      and forward the rest as `messages`.
///
/// `max_tokens` is REQUIRED by the Anthropic API. When the caller does not
/// specify a value we fall back to `1024`.
class AnthropicProvider implements AiProvider {
  AnthropicProvider({
    required this.apiKey,
    required this.model,
    http.Client? client,
    Duration requestTimeout = const Duration(seconds: 20),
  })  : _client = client ?? http.Client(),
        _requestTimeout = requestTimeout;

  static const _endpoint = 'https://api.anthropic.com/v1/messages';
  static const _anthropicVersion = '2023-06-01';
  static const int _defaultMaxTokens = 1024;

  final String apiKey;
  final String model;
  final http.Client _client;
  final Duration _requestTimeout;

  @override
  AiProviderType get type => AiProviderType.anthropic;

  /// Splits an OpenAI-style message list into the Anthropic `system` text
  /// and the remaining `messages` array. The returned messages keep their
  /// original `role` (only `user` / `assistant` are valid for Anthropic;
  /// any other role is dropped after extracting the system content).
  static ({String? system, List<Map<String, String>> messages})
      _splitMessages(List<Map<String, String>> input) {
    final systemBuf = StringBuffer();
    final out = <Map<String, String>>[];
    for (final msg in input) {
      final role = msg['role'];
      final content = msg['content'] ?? '';
      if (role == 'system') {
        if (systemBuf.isNotEmpty) systemBuf.write('\n');
        systemBuf.write(content);
        continue;
      }
      if (role == 'user' || role == 'assistant') {
        out.add({'role': role!, 'content': content});
      }
    }
    final system = systemBuf.isEmpty ? null : systemBuf.toString();
    return (system: system, messages: out);
  }

  @override
  Future<String?> complete({
    required List<Map<String, String>> messages,
    double? temperature,
    int? maxTokens,
    String? model,
  }) async {
    if (apiKey.isEmpty) {
      debugPrint('AnthropicProvider.complete ABORT: no API key configured');
      return null;
    }

    final split = _splitMessages(messages);
    final resolvedModel = (model != null && model.isNotEmpty) ? model : this.model;

    final body = <String, dynamic>{
      'model': resolvedModel,
      'max_tokens': maxTokens ?? _defaultMaxTokens,
      'messages': split.messages,
    };
    if (split.system != null) body['system'] = split.system;
    if (temperature != null) body['temperature'] = temperature;

    final startedAt = DateTime.now();
    try {
      final response = await _client
          .post(
            Uri.parse(_endpoint),
            headers: {
              'Content-Type': 'application/json',
              'x-api-key': apiKey,
              'anthropic-version': _anthropicVersion,
            },
            body: jsonEncode(body),
          )
          .timeout(_requestTimeout);

      final latencyMs = DateTime.now().difference(startedAt).inMilliseconds;
      debugPrint(
        'AnthropicProvider.complete status=${response.statusCode} latencyMs=$latencyMs',
      );

      if (response.statusCode < 200 || response.statusCode >= 300) {
        return null;
      }

      final data = jsonDecode(response.body);
      if (data is! Map<String, dynamic>) return null;
      final content = data['content'];
      if (content is! List || content.isEmpty) return null;
      final firstBlock = content.first;
      if (firstBlock is! Map<String, dynamic>) return null;
      final text = firstBlock['text'];
      if (text is String && text.trim().isNotEmpty) {
        return text.trim();
      }
      return null;
    } catch (e) {
      debugPrint('AnthropicProvider.complete ERROR: $e');
      return null;
    }
  }

  @override
  Future<String?> testConnection() async {
    if (apiKey.isEmpty) return 'No hay API key configurada';
    try {
      final response = await _client
          .post(
            Uri.parse(_endpoint),
            headers: {
              'Content-Type': 'application/json',
              'x-api-key': apiKey,
              'anthropic-version': _anthropicVersion,
            },
            body: jsonEncode({
              'model': model,
              'max_tokens': 10,
              'messages': [
                {'role': 'user', 'content': 'ping'},
              ],
            }),
          )
          .timeout(_requestTimeout);

      if (response.statusCode == 401 || response.statusCode == 403) {
        return 'API key inválida (HTTP ${response.statusCode})';
      }
      if (response.statusCode == 429) {
        return 'Cuota agotada (HTTP 429)';
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return 'Error HTTP ${response.statusCode}';
      }
      return null;
    } on TimeoutException {
      return 'Timeout — el servidor tardó demasiado en responder';
    } catch (e) {
      return 'Error de red: $e';
    }
  }
}
