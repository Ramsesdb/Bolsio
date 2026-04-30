import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:kilatex/core/services/ai/ai_provider.dart';
import 'package:kilatex/core/services/ai/ai_provider_type.dart';

/// BYOK provider that talks to the Nexus AI gateway (OpenAI-compatible).
///
/// Nexus accepts free-text model identifiers and routes them to the right
/// upstream provider, so the dispatcher passes whatever the user typed in
/// settings without validating it against [AiProviderType.nexus.models].
class NexusProvider implements AiProvider {
  NexusProvider({
    required this.apiKey,
    String? baseUrl,
    String? model,
    http.Client? client,
    Duration requestTimeout = const Duration(seconds: 15),
  })  : _baseUrl = (baseUrl == null || baseUrl.trim().isEmpty)
            ? _defaultBaseUrl
            : baseUrl.trim().replaceAll(RegExp(r'/+$'), ''),
        _model = (model == null || model.trim().isEmpty) ? null : model.trim(),
        _client = client ?? http.Client(),
        _requestTimeout = requestTimeout;

  static const _defaultBaseUrl = 'https://api.ramsesdb.tech';
  static const _endpoint = '/v1/chat/completions';

  final String apiKey;
  final String _baseUrl;
  final String? _model;
  final http.Client _client;
  final Duration _requestTimeout;

  @override
  AiProviderType get type => AiProviderType.nexus;

  @override
  Future<String?> complete({
    required List<Map<String, String>> messages,
    double? temperature,
    int? maxTokens,
    String? model,
  }) async {
    if (apiKey.isEmpty) {
      debugPrint('NexusProvider.complete ABORT: no API key configured');
      return null;
    }

    final resolvedModel = model ?? _model;
    final body = <String, dynamic>{
      'stream': false,
      'messages': messages,
    };
    if (temperature != null) body['temperature'] = temperature;
    if (maxTokens != null) body['max_tokens'] = maxTokens;
    if (resolvedModel != null && resolvedModel.isNotEmpty) {
      body['model'] = resolvedModel;
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
            body: jsonEncode(body),
          )
          .timeout(_requestTimeout);

      final latencyMs = DateTime.now().difference(startedAt).inMilliseconds;
      debugPrint(
        'NexusProvider.complete status=${response.statusCode} latencyMs=$latencyMs',
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
      debugPrint('NexusProvider.complete ERROR: $e');
      return null;
    }
  }

  @override
  Future<String?> testConnection() async {
    if (apiKey.isEmpty) return 'No hay API key configurada';
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
              'max_tokens': 10,
              'messages': [
                {'role': 'user', 'content': 'ping'},
              ],
              if (_model != null && _model.isNotEmpty) 'model': _model,
            }),
          )
          .timeout(_requestTimeout);

      if (response.statusCode == 401 || response.statusCode == 403) {
        return 'API key inválida (HTTP ${response.statusCode})';
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
