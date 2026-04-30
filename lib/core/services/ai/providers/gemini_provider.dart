import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:kilatex/core/services/ai/ai_provider.dart';
import 'package:kilatex/core/services/ai/ai_provider_type.dart';

/// BYOK provider for Google's Gemini `generateContent` API.
///
/// Differences from OpenAI:
///   1. The API key travels in the query string (`?key=<apiKey>`) — there
///      is no header-based auth.
///   2. The endpoint embeds the model id in the path
///      (`/models/<model>:generateContent`).
///   3. System prompts go in `systemInstruction.parts[*].text` and are kept
///      out of the `contents[]` list. Roles for `contents[]` are `user` and
///      `model` (NOT `assistant`).
///   4. Sampling parameters live under `generationConfig`.
class GeminiProvider implements AiProvider {
  GeminiProvider({
    required this.apiKey,
    required this.model,
    http.Client? client,
    Duration requestTimeout = const Duration(seconds: 20),
  })  : _client = client ?? http.Client(),
        _requestTimeout = requestTimeout;

  static const _baseUrl = 'https://generativelanguage.googleapis.com/v1beta/models';

  final String apiKey;
  final String model;
  final http.Client _client;
  final Duration _requestTimeout;

  @override
  AiProviderType get type => AiProviderType.gemini;

  /// Translates an OpenAI-style message list into Gemini's `contents` +
  /// `systemInstruction` shape. System messages are concatenated into a
  /// single instruction; assistant messages map to `role: 'model'`.
  static ({String? systemText, List<Map<String, dynamic>> contents})
      _convert(List<Map<String, String>> input) {
    final systemBuf = StringBuffer();
    final contents = <Map<String, dynamic>>[];
    for (final msg in input) {
      final role = msg['role'];
      final content = msg['content'] ?? '';
      if (role == 'system') {
        if (systemBuf.isNotEmpty) systemBuf.write('\n');
        systemBuf.write(content);
        continue;
      }
      // 'assistant' → 'model'; everything else → 'user' (default).
      final geminiRole = role == 'assistant' ? 'model' : 'user';
      contents.add({
        'role': geminiRole,
        'parts': [
          {'text': content},
        ],
      });
    }
    final systemText = systemBuf.isEmpty ? null : systemBuf.toString();
    return (systemText: systemText, contents: contents);
  }

  Uri _buildUri(String resolvedModel) {
    return Uri.parse('$_baseUrl/$resolvedModel:generateContent?key=$apiKey');
  }

  @override
  Future<String?> complete({
    required List<Map<String, String>> messages,
    double? temperature,
    int? maxTokens,
    String? model,
  }) async {
    if (apiKey.isEmpty) {
      debugPrint('GeminiProvider.complete ABORT: no API key configured');
      return null;
    }

    final converted = _convert(messages);
    final resolvedModel = (model != null && model.isNotEmpty) ? model : this.model;

    final body = <String, dynamic>{
      'contents': converted.contents,
    };
    if (converted.systemText != null) {
      body['systemInstruction'] = {
        'parts': [
          {'text': converted.systemText},
        ],
      };
    }
    final genConfig = <String, dynamic>{};
    if (temperature != null) genConfig['temperature'] = temperature;
    if (maxTokens != null) genConfig['maxOutputTokens'] = maxTokens;
    if (genConfig.isNotEmpty) body['generationConfig'] = genConfig;

    final startedAt = DateTime.now();
    try {
      final response = await _client
          .post(
            _buildUri(resolvedModel),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(_requestTimeout);

      final latencyMs = DateTime.now().difference(startedAt).inMilliseconds;
      debugPrint(
        'GeminiProvider.complete status=${response.statusCode} latencyMs=$latencyMs',
      );

      if (response.statusCode < 200 || response.statusCode >= 300) {
        return null;
      }

      final data = jsonDecode(response.body);
      if (data is! Map<String, dynamic>) return null;
      final candidates = data['candidates'];
      if (candidates is! List || candidates.isEmpty) return null;
      final firstCandidate = candidates.first;
      if (firstCandidate is! Map<String, dynamic>) return null;
      final content = firstCandidate['content'];
      if (content is! Map<String, dynamic>) return null;
      final parts = content['parts'];
      if (parts is! List || parts.isEmpty) return null;
      final firstPart = parts.first;
      if (firstPart is! Map<String, dynamic>) return null;
      final text = firstPart['text'];
      if (text is String && text.trim().isNotEmpty) {
        return text.trim();
      }
      return null;
    } catch (e) {
      debugPrint('GeminiProvider.complete ERROR: $e');
      return null;
    }
  }

  @override
  Future<String?> testConnection() async {
    if (apiKey.isEmpty) return 'No hay API key configurada';
    try {
      final response = await _client
          .post(
            _buildUri(model),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({
              'contents': [
                {
                  'role': 'user',
                  'parts': [
                    {'text': 'ping'},
                  ],
                },
              ],
              'generationConfig': {'maxOutputTokens': 10},
            }),
          )
          .timeout(_requestTimeout);

      if (response.statusCode == 400 || response.statusCode == 403) {
        return 'API key inválida o solicitud rechazada (HTTP ${response.statusCode})';
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
