import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:bolsio/core/services/ai/providers/openai_provider.dart';

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
  group('OpenAiProvider', () {
    test('happy path returns trimmed assistant content', () async {
      final body = jsonEncode({
        'choices': [
          {
            'message': {'content': '  hello world  '},
          },
        ],
      });
      final client = _FakeClient(200, body);
      final provider = OpenAiProvider(
        apiKey: 'sk-test',
        model: 'gpt-4o-mini',
        client: client,
      );

      final result = await provider.complete(messages: [
        {'role': 'user', 'content': 'hi'},
      ]);

      expect(result, 'hello world');

      final sentRequest = client.lastRequest as http.Request;
      final headers = sentRequest.headers;
      expect(headers['Authorization'], 'Bearer sk-test');

      final payload = jsonDecode(sentRequest.body) as Map<String, dynamic>;
      expect(payload['model'], 'gpt-4o-mini');
      expect(payload['messages'], [
        {'role': 'user', 'content': 'hi'},
      ]);
    });

    test('forwards explicit model + temperature + max_tokens', () async {
      final body = jsonEncode({
        'choices': [
          {
            'message': {'content': 'ok'},
          },
        ],
      });
      final client = _FakeClient(200, body);
      final provider = OpenAiProvider(
        apiKey: 'sk-test',
        model: 'gpt-4o-mini',
        client: client,
      );

      await provider.complete(
        messages: [
          {'role': 'user', 'content': 'hi'},
        ],
        model: 'gpt-4.1',
        temperature: 0.42,
        maxTokens: 256,
      );

      final payload = jsonDecode((client.lastRequest as http.Request).body)
          as Map<String, dynamic>;
      expect(payload['model'], 'gpt-4.1');
      expect(payload['temperature'], 0.42);
      expect(payload['max_tokens'], 256);
    });

    test('returns null on 401', () async {
      final client = _FakeClient(401, '{"error":"unauthorized"}');
      final provider = OpenAiProvider(
        apiKey: 'sk-bad',
        model: 'gpt-4o-mini',
        client: client,
      );
      final result = await provider.complete(messages: [
        {'role': 'user', 'content': 'hi'},
      ]);
      expect(result, isNull);
    });

    test('testConnection maps 401/403 to API key error', () async {
      final client = _FakeClient(401, '{"error":"unauthorized"}');
      final provider = OpenAiProvider(
        apiKey: 'sk-bad',
        model: 'gpt-4o-mini',
        client: client,
      );
      final result = await provider.testConnection();
      expect(result, contains('inválida'));
    });

    test('testConnection returns null on success', () async {
      final body = jsonEncode({
        'choices': [
          {
            'message': {'content': 'pong'},
          },
        ],
      });
      final client = _FakeClient(200, body);
      final provider = OpenAiProvider(
        apiKey: 'sk-test',
        model: 'gpt-4o-mini',
        client: client,
      );
      expect(await provider.testConnection(), isNull);
    });
  });
}
