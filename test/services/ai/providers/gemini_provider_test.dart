import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:nitido/core/services/ai/providers/gemini_provider.dart';

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
  group('GeminiProvider', () {
    test('converts assistant role to model + extracts systemInstruction',
        () async {
      final body = jsonEncode({
        'candidates': [
          {
            'content': {
              'parts': [
                {'text': 'pong'},
              ],
            },
          },
        ],
      });
      final client = _FakeClient(200, body);
      final provider = GeminiProvider(
        apiKey: 'AIza-test',
        model: 'gemini-2.5-flash',
        client: client,
      );

      await provider.complete(messages: [
        {'role': 'system', 'content': 'You are a banker'},
        {'role': 'user', 'content': 'hi'},
        {'role': 'assistant', 'content': 'previous reply'},
        {'role': 'user', 'content': 'follow up'},
      ]);

      final request = client.lastRequest as http.Request;
      expect(
        request.url.toString(),
        contains(
            'generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent'),
      );
      expect(request.url.queryParameters['key'], 'AIza-test');

      final payload = jsonDecode(request.body) as Map<String, dynamic>;
      expect(payload['systemInstruction'], isA<Map<String, dynamic>>());
      final sysParts =
          (payload['systemInstruction'] as Map)['parts'] as List;
      expect((sysParts.first as Map)['text'], 'You are a banker');

      final contents = payload['contents'] as List;
      expect(contents.length, 3);
      expect((contents[0] as Map)['role'], 'user');
      expect((contents[1] as Map)['role'], 'model'); // was 'assistant'
      expect((contents[2] as Map)['role'], 'user');
    });

    test('omits systemInstruction when no system message present', () async {
      final body = jsonEncode({
        'candidates': [
          {
            'content': {
              'parts': [
                {'text': 'pong'},
              ],
            },
          },
        ],
      });
      final client = _FakeClient(200, body);
      final provider = GeminiProvider(
        apiKey: 'AIza-test',
        model: 'gemini-2.5-flash',
        client: client,
      );

      await provider.complete(messages: [
        {'role': 'user', 'content': 'hi'},
      ]);

      final payload = jsonDecode((client.lastRequest as http.Request).body)
          as Map<String, dynamic>;
      expect(payload.containsKey('systemInstruction'), isFalse);
    });

    test('returns trimmed text from first candidate part', () async {
      final body = jsonEncode({
        'candidates': [
          {
            'content': {
              'parts': [
                {'text': '  hello  '},
              ],
            },
          },
        ],
      });
      final client = _FakeClient(200, body);
      final provider = GeminiProvider(
        apiKey: 'AIza-test',
        model: 'gemini-2.5-flash',
        client: client,
      );
      final out = await provider.complete(messages: [
        {'role': 'user', 'content': 'hi'},
      ]);
      expect(out, 'hello');
    });

    test('returns null on 403', () async {
      final client = _FakeClient(403, '{"error":"bad key"}');
      final provider = GeminiProvider(
        apiKey: 'bad',
        model: 'gemini-2.5-flash',
        client: client,
      );
      expect(
        await provider.complete(messages: [
          {'role': 'user', 'content': 'hi'},
        ]),
        isNull,
      );
    });

    test('routes generationConfig parameters', () async {
      final body = jsonEncode({
        'candidates': [
          {
            'content': {
              'parts': [
                {'text': 'pong'},
              ],
            },
          },
        ],
      });
      final client = _FakeClient(200, body);
      final provider = GeminiProvider(
        apiKey: 'AIza-test',
        model: 'gemini-2.5-flash',
        client: client,
      );

      await provider.complete(
        messages: [
          {'role': 'user', 'content': 'hi'},
        ],
        temperature: 0.42,
        maxTokens: 256,
      );

      final payload = jsonDecode((client.lastRequest as http.Request).body)
          as Map<String, dynamic>;
      final genConfig = payload['generationConfig'] as Map<String, dynamic>;
      expect(genConfig['temperature'], 0.42);
      expect(genConfig['maxOutputTokens'], 256);
    });
  });
}
