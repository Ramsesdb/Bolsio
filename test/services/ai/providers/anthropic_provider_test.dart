import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:wallex/core/services/ai/providers/anthropic_provider.dart';

class _FakeClient extends http.BaseClient {
  _FakeClient(this._statusCode, this._body);
  final int _statusCode;
  final String _body;
  http.BaseRequest? lastRequest;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    lastRequest = request;
    return http.StreamedResponse(
      Stream.value(utf8.encode(_body)),
      _statusCode,
      headers: const {'content-type': 'application/json'},
    );
  }
}

void main() {
  group('AnthropicProvider', () {
    test('extracts system messages into top-level system field', () async {
      final body = jsonEncode({
        'content': [
          {'text': 'pong'},
        ],
      });
      final client = _FakeClient(200, body);
      final provider = AnthropicProvider(
        apiKey: 'sk-ant-test',
        model: 'claude-haiku-4-5',
        client: client,
      );

      await provider.complete(messages: [
        {'role': 'system', 'content': 'You are a banker'},
        {'role': 'system', 'content': 'Use VES'},
        {'role': 'user', 'content': 'hi'},
        {'role': 'assistant', 'content': 'previous reply'},
      ]);

      final request = client.lastRequest as http.Request;
      expect(request.headers['x-api-key'], 'sk-ant-test');
      expect(request.headers['anthropic-version'], '2023-06-01');

      final payload = jsonDecode(request.body) as Map<String, dynamic>;
      expect(payload['system'], 'You are a banker\nUse VES');

      final messages = payload['messages'] as List;
      expect(messages.length, 2);
      expect(messages[0], {'role': 'user', 'content': 'hi'});
      expect(messages[1], {'role': 'assistant', 'content': 'previous reply'});
    });

    test('uses default max_tokens of 1024 when caller omits it', () async {
      final body = jsonEncode({
        'content': [
          {'text': 'pong'},
        ],
      });
      final client = _FakeClient(200, body);
      final provider = AnthropicProvider(
        apiKey: 'sk-ant-test',
        model: 'claude-haiku-4-5',
        client: client,
      );

      await provider.complete(messages: [
        {'role': 'user', 'content': 'hi'},
      ]);

      final payload = jsonDecode((client.lastRequest as http.Request).body)
          as Map<String, dynamic>;
      expect(payload['max_tokens'], 1024);
    });

    test('honours explicit max_tokens from caller', () async {
      final body = jsonEncode({
        'content': [
          {'text': 'pong'},
        ],
      });
      final client = _FakeClient(200, body);
      final provider = AnthropicProvider(
        apiKey: 'sk-ant-test',
        model: 'claude-haiku-4-5',
        client: client,
      );

      await provider.complete(
        messages: [
          {'role': 'user', 'content': 'hi'},
        ],
        maxTokens: 256,
      );

      final payload = jsonDecode((client.lastRequest as http.Request).body)
          as Map<String, dynamic>;
      expect(payload['max_tokens'], 256);
    });

    test('returns trimmed text from first content block', () async {
      final body = jsonEncode({
        'content': [
          {'text': '  trimmed reply  '},
        ],
      });
      final client = _FakeClient(200, body);
      final provider = AnthropicProvider(
        apiKey: 'sk-ant-test',
        model: 'claude-haiku-4-5',
        client: client,
      );
      final out = await provider.complete(messages: [
        {'role': 'user', 'content': 'hi'},
      ]);
      expect(out, 'trimmed reply');
    });

    test('returns null on 401', () async {
      final client = _FakeClient(401, '{"error":"unauthorized"}');
      final provider = AnthropicProvider(
        apiKey: 'sk-ant-bad',
        model: 'claude-haiku-4-5',
        client: client,
      );
      final out = await provider.complete(messages: [
        {'role': 'user', 'content': 'hi'},
      ]);
      expect(out, isNull);
    });
  });
}
