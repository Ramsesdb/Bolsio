import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:wallex/core/services/ai/nexus_credentials_store.dart';

class NexusAiService {
  static final instance = NexusAiService._();
  NexusAiService._();

  static const _baseUrl = 'https://api.ramsesdb.tech';
  static const _endpoint = '/v1/chat/completions';

  Future<String?> complete({
    required List<Map<String, String>> messages,
    double temperature = 0.2,
  }) async {
    final apiKey = await NexusCredentialsStore.instance.loadApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      debugPrint('NexusAiService.complete ABORT: no API key configured');
      return null;
    }

    final startedAt = DateTime.now();

    try {
      final response = await http
          .post(
            Uri.parse('$_baseUrl$_endpoint'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $apiKey',
            },
            body: jsonEncode({
              'stream': false,
              'temperature': temperature,
              'messages': messages,
            }),
          )
          .timeout(const Duration(seconds: 15));

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

  Stream<String> streamComplete({
    required List<Map<String, String>> messages,
    double temperature = 0.7,
  }) async* {
    final apiKey = await NexusCredentialsStore.instance.loadApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      debugPrint('NexusAiService.streamComplete ABORT: no API key configured');
      return;
    }

    final client = http.Client();
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
        'messages': messages,
      });

      final response = await client
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
    } finally {
      client.close();
    }
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
