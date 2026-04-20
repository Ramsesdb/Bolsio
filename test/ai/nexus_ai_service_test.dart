import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:wallex/core/services/ai/nexus_ai_service.dart';

class _CaptureClient extends http.BaseClient {
  http.BaseRequest? lastRequest;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    lastRequest = request;

    final responseBody = jsonEncode({
      'choices': [
        {
          'message': {
            'content': jsonEncode({
              'amount': 10,
              'currencyCode': 'USD',
              'date': '2026-04-17T10:24:00Z',
              'type': 'E',
              'counterpartyName': 'Test',
              'bankRef': '123',
              'bankName': 'BDV',
              'confidence': 0.9,
            }),
          },
        },
      ],
    });

    return http.StreamedResponse(
      Stream.value(utf8.encode(responseBody)),
      200,
      headers: const {'content-type': 'application/json'},
    );
  }
}

void main() {
  test('3.12 completeMultimodal sends text and image_url parts', () async {
    final client = _CaptureClient();
    final service = NexusAiService.forTesting(
      client: client,
      loadApiKey: () async => 'test-key',
      loadModel: () async => 'openai/gpt-4.1-mini',
    );

    await service.completeMultimodal(
      systemPrompt: 'system',
      userPrompt: 'user prompt',
      imageBase64: 'abc123',
      temperature: 0.1,
    );

    final sent = client.lastRequest;
    expect(sent, isNotNull);

    final body = jsonDecode((sent as http.Request).body) as Map<String, dynamic>;
    final messages = body['messages'] as List<dynamic>;
    final user = messages[1] as Map<String, dynamic>;
    final content = user['content'] as List<dynamic>;

    expect(content[0]['type'], 'text');
    expect(content[1]['type'], 'image_url');

    final imageUrl = (content[1]['image_url'] as Map<String, dynamic>)['url'] as String;
    expect(imageUrl.startsWith('data:image/jpeg;base64,'), isTrue);
  });
}
