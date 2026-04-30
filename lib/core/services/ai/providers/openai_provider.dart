import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:kilatex/core/services/ai/ai_provider.dart';
import 'package:kilatex/core/services/ai/ai_provider_type.dart';

/// BYOK provider for OpenAI's hosted chat-completions API.
///
/// Body shape is the canonical OpenAI one — every other "OpenAI-compatible"
/// gateway in the codebase mirrors this. Authentication is `Bearer <key>`.
class OpenAiProvider implements AiProvider {
  OpenAiProvider({
    required this.apiKey,
    required this.model,
    http.Client? client,
    Duration requestTimeout = const Duration(seconds: 20),
  })  : _client = client ?? http.Client(),
        _requestTimeout = requestTimeout;

  static const _endpoint = 'https://api.openai.com/v1/chat/completions';

  final String apiKey;
  final String model;
  final http.Client _client;
  final Duration _requestTimeout;

  @override
  AiProviderType get type => AiProviderType.openai;

  @override
  Future<String?> complete({
    required List<Map<String, String>> messages,
    double? temperature,
    int? maxTokens,
    String? model,
  }) async {
    if (apiKey.isEmpty) {
      debugPrint('OpenAiProvider.complete ABORT: no API key configured');
      return null;
    }

    final resolvedModel = (model != null && model.isNotEmpty) ? model : this.model;
    final body = <String, dynamic>{
      'model': resolvedModel,
      'messages': messages,
    };
    if (temperature != null) body['temperature'] = temperature;
    if (maxTokens != null) body['max_tokens'] = maxTokens;

    final startedAt = DateTime.now();
    try {
      final response = await _client
          .post(
            Uri.parse(_endpoint),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $apiKey',
            },
            body: jsonEncode(body),
          )
          .timeout(_requestTimeout);

      final latencyMs = DateTime.now().difference(startedAt).inMilliseconds;
      debugPrint(
        'OpenAiProvider.complete status=${response.statusCode} latencyMs=$latencyMs',
      );

      if (response.statusCode < 200 || response.statusCode >= 300) {
        return null;
      }

      final data = jsonDecode(response.body);
      if (data is! Map<String, dynamic>) return null;
      final choices = data['choices'];
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
    } catch (e) {
      debugPrint('OpenAiProvider.complete ERROR: $e');
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
              'Authorization': 'Bearer $apiKey',
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
