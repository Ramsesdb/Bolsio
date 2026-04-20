import 'dart:io';
import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:wallex/core/database/services/user-setting/user_setting_service.dart';
import 'package:wallex/core/models/auto_import/capture_channel.dart';
import 'package:wallex/core/models/auto_import/raw_capture_event.dart';
import 'package:wallex/core/models/auto_import/transaction_proposal.dart';
import 'package:wallex/core/models/transaction/transaction_type.enum.dart';
import 'package:wallex/core/services/ai/nexus_ai_service.dart';
import 'package:wallex/core/services/auto_import/profiles/bank_profile.dart';
import 'package:wallex/core/services/receipt_ocr/ocr_service.dart';
import 'package:wallex/core/services/receipt_ocr/receipt_extractor_service.dart';
import 'package:wallex/core/services/receipt_ocr/receipt_image_service.dart';

class _FakeOcrService extends OcrService {
  _FakeOcrService(this._text) : super();

  final String _text;

  @override
  Future<String> recognize(File imageFile) async => _text;
}

/// HTTP client whose `send` never completes. Lets tests exercise the real
/// timeout path of `NexusAiService.completeMultimodal` (the `.timeout(...)`
/// wrapped around `_client.post`) instead of synthesizing a `TimeoutException`.
class _BlockingHttpClient extends http.BaseClient {
  final Completer<http.StreamedResponse> _never =
      Completer<http.StreamedResponse>();

  int sendCalls = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    sendCalls++;
    // Intentionally never completes so that `_client.post(...).timeout(...)`
    // in NexusAiService triggers the timeout branch naturally.
    return _never.future;
  }
}

class _CountingProfile extends BankProfile {
  _CountingProfile({required this.result});

  int calls = 0;
  TransactionProposal? result;

  @override
  String get bankName => 'Fake';

  @override
  String get accountMatchName => 'Fake';

  @override
  CaptureChannel get channel => CaptureChannel.receiptImage;

  @override
  List<String> get knownSenders => const ['fake'];

  @override
  int get profileVersion => 1;

  @override
  TransactionProposal? tryParse(
    RawCaptureEvent event, {
    required String? accountId,
  }) {
    calls++;
    return result;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');

  late ReceiptExtractorService extractor;
  late ReceiptImageService imageService;
  late Directory tempRoot;

  setUp(() async {
    extractor = ReceiptExtractorService();
    imageService = ReceiptImageService();
    tempRoot = await Directory.systemTemp.createTemp('wallex_receipt_ocr_test_');
    appStateSettings[SettingKey.nexusAiEnabled] = '1';
    appStateSettings[SettingKey.receiptAiEnabled] = '1';

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, (MethodCall call) async {
      if (call.method == 'getTemporaryDirectory') {
        return tempRoot.path;
      }
      return tempRoot.path;
    });
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, null);
    if (await tempRoot.exists()) {
      await tempRoot.delete(recursive: true);
    }
  });

  test('2.6 extractor parses BDV OCR text with amount, bankRef, date and type', () {
    const ocrText =
        'PagomovilBDV recibido\n'
        'Recibiste un PagomovilBDV por Bs.100,00 del 0412-7171711 Ref: 184891460184 en fecha 16-04-26 hora: 10:17.';

    final result = extractor.extractFromOcrText(
      ocrText,
      accountId: 'acc-bdv-001',
      preferredCurrency: 'USD',
    );

    expect(result.isSuccess, isTrue);
    expect(result.proposal, isNotNull);

    final proposal = result.proposal!;
    expect(proposal.amount, 100.00);
    expect(proposal.bankRef, '184891460184');
    expect(proposal.date, DateTime(2026, 4, 16, 10, 17));
    expect(proposal.type, TransactionType.income);
    expect(proposal.counterpartyName, '0412-7171711');
    expect(proposal.channel, CaptureChannel.receiptImage);
  });

  test('2.7 extractor returns empty when OCR text is empty', () {
    final result = extractor.extractFromOcrText('   ');

    expect(result.outcome, ExtractionOutcome.empty);
    expect(result.errorKey, 'error.ocr_empty');
    expect(result.proposal, isNull);
  });

  test('2.8 extractor returns noAmount when amount cannot be extracted', () {
    const ocrText =
        'Comprobante\n'
        'Transferencia recibida\n'
        'Operacion completada sin monto visible';

    final result = extractor.extractFromOcrText(ocrText);

    expect(result.outcome, ExtractionOutcome.noAmount);
    expect(result.errorKey, 'error.no_amount');
    expect(result.proposal, isNull);
  });

  test('2.9 receipt_image_service compresses 4k image to <=1600px and jpg', () async {
    final big = img.Image(width: 4096, height: 3072);
    for (var y = 0; y < big.height; y++) {
      for (var x = 0; x < big.width; x++) {
        big.setPixelRgba(x, y, x % 255, y % 255, (x + y) % 255, 255);
      }
    }

    final source = File('${tempRoot.path}/source_4k.png')
      ..writeAsBytesSync(img.encodePng(big, level: 0));

    final compressed = await imageService.compressToTemp(source);

    expect(await compressed.exists(), isTrue);
    expect(compressed.path.endsWith('.jpg'), isTrue);

    final decoded = img.decodeJpg(await compressed.readAsBytes());
    expect(decoded, isNotNull);

    final maxSide = decoded!.width > decoded.height ? decoded.width : decoded.height;
    expect(maxSide, lessThanOrEqualTo(1600));
    expect(await compressed.length(), lessThan(await source.length()));
  });

  test('3.8 AI valid JSON returns proposal and skips regex fallback', () async {
    final profile = _CountingProfile(result: null);
    var aiCalls = 0;
    final extractorWithAi = ReceiptExtractorService(
      ocrService: _FakeOcrService('Texto OCR cualquiera'),
      profile: profile,
      multimodalComplete: ({
        required systemPrompt,
        required userPrompt,
        required imageBase64,
        temperature = 0.1,
      }) async {
        aiCalls++;
        return jsonEncode({
          'amount': 24.5,
          'currencyCode': 'USD',
          'date': '2026-04-17T10:24:00Z',
          'type': 'E',
          'counterpartyName': 'Farmatodo',
          'bankRef': '005717108313',
          'bankName': 'BDV',
          'confidence': 0.88,
        });
      },
    );

    final image = File('${tempRoot.path}/ai_success.jpg')
      ..writeAsBytesSync(List.filled(128, 1));

    final result = await extractorWithAi.extractFromImage(image);

    expect(result.isSuccess, isTrue);
    expect(aiCalls, 1);
    expect(profile.calls, 0);
    expect(result.proposal!.amount, 24.5);
    expect(result.proposal!.confidence, 0.88);
  });

  test('3.9 malformed AI response falls back to regex parser', () async {
    const ocrText =
        'PagomovilBDV recibido\n'
        'Recibiste un PagomovilBDV por Bs.100,00 del 0412-7171711 Ref: 184891460184 en fecha 16-04-26 hora: 10:17.';

    var aiCalls = 0;
    final extractorWithAi = ReceiptExtractorService(
      ocrService: _FakeOcrService(ocrText),
      multimodalComplete: ({
        required systemPrompt,
        required userPrompt,
        required imageBase64,
        temperature = 0.1,
      }) async {
        aiCalls++;
        return 'texto sin json valido';
      },
    );

    final image = File('${tempRoot.path}/ai_bad.jpg')
      ..writeAsBytesSync(List.filled(128, 2));
    final result = await extractorWithAi.extractFromImage(image);

    expect(result.isSuccess, isTrue);
    // Retry logic: malformed JSON triggers a second attempt before falling
    // back to the deterministic regex parser.
    expect(aiCalls, 2);
    expect(result.proposal!.bankRef, '184891460184');
  });

  test(
    '3.10 Nexus multimodal HTTP timeout falls back to regex with confidence 0.7',
    () async {
      const ocrText =
          'PagomovilBDV recibido\n'
          'Recibiste un PagomovilBDV por Bs.100,00 del 0412-7171711 Ref: 184891460184 en fecha 16-04-26 hora: 10:17.';

      // Wire the real Nexus service with a client that never returns, so the
      // `.timeout(requestTimeout)` inside `completeMultimodal` fires naturally
      // and we exercise the actual HTTP-layer timeout path (not a synthetic
      // TimeoutException at the extractor boundary).
      final blockingClient = _BlockingHttpClient();
      final nexus = NexusAiService.forTesting(
        client: blockingClient,
        loadApiKey: () async => 'test-key',
        loadModel: () async => 'openai/gpt-4.1-mini',
        // Short deadline so the suite runs fast. The production default is
        // 15s (per spec), but the codepath under test is identical.
        requestTimeout: const Duration(milliseconds: 150),
      );

      final extractorWithAi = ReceiptExtractorService(
        ocrService: _FakeOcrService(ocrText),
        multimodalComplete: nexus.completeMultimodal,
      );

      final image = File('${tempRoot.path}/ai_timeout.jpg')
        ..writeAsBytesSync(List.filled(128, 3));
      final result = await extractorWithAi.extractFromImage(image);

      expect(blockingClient.sendCalls, 1,
          reason: 'Nexus service must actually hit the HTTP layer.');
      expect(result.isSuccess, isTrue);
      expect(result.proposal!.confidence, 0.7);
      expect(result.proposal!.bankRef, '184891460184');
    },
  );

  test('3.11 receiptAiEnabled false skips multimodal call', () async {
    appStateSettings[SettingKey.receiptAiEnabled] = '0';

    var aiCalls = 0;
    final extractorWithAi = ReceiptExtractorService(
      ocrService: _FakeOcrService('Comprobante sin monto'),
      multimodalComplete: ({
        required systemPrompt,
        required userPrompt,
        required imageBase64,
        temperature = 0.1,
      }) async {
        aiCalls++;
        return '{}';
      },
    );

    final image = File('${tempRoot.path}/ai_disabled.jpg')
      ..writeAsBytesSync(List.filled(128, 4));
    await extractorWithAi.extractFromImage(image);

    expect(aiCalls, 0);
  });

  test('3.12 AI response wrapped in ```json fences is parsed', () async {
    final profile = _CountingProfile(result: null);
    final extractorWithAi = ReceiptExtractorService(
      ocrService: _FakeOcrService('Texto OCR cualquiera'),
      profile: profile,
      multimodalComplete: ({
        required systemPrompt,
        required userPrompt,
        required imageBase64,
        temperature = 0.1,
      }) async {
        return '```json\n'
            '{"amount": 12.34, "currencyCode": "USD", "date": "2026-04-17T10:00:00Z", '
            '"type": "E", "counterpartyName": "Farmatodo", "bankRef": "999", '
            '"confidence": 0.91}\n'
            '```';
      },
    );

    final image = File('${tempRoot.path}/ai_fenced.jpg')
      ..writeAsBytesSync(List.filled(128, 10));

    final result = await extractorWithAi.extractFromImage(image);

    expect(result.isSuccess, isTrue);
    expect(profile.calls, 0);
    expect(result.proposal!.amount, 12.34);
    expect(result.proposal!.bankRef, '999');
    expect(result.proposal!.confidence, 0.91);
  });

  test('3.13 AI prose + JSON at the end is parsed', () async {
    final profile = _CountingProfile(result: null);
    final extractorWithAi = ReceiptExtractorService(
      ocrService: _FakeOcrService('Texto OCR cualquiera'),
      profile: profile,
      multimodalComplete: ({
        required systemPrompt,
        required userPrompt,
        required imageBase64,
        temperature = 0.1,
      }) async {
        return 'Aquí tienes el JSON solicitado:\n'
            '{"amount": 5.50, "currencyCode": "USD", '
            '"date": "2026-04-17T09:30:00Z", "type": "E", '
            '"counterpartyName": "Panadería", "bankRef": "ABC123", '
            '"confidence": 0.75}';
      },
    );

    final image = File('${tempRoot.path}/ai_prose.jpg')
      ..writeAsBytesSync(List.filled(128, 11));

    final result = await extractorWithAi.extractFromImage(image);

    expect(result.isSuccess, isTrue);
    expect(profile.calls, 0);
    expect(result.proposal!.amount, 5.50);
    expect(result.proposal!.bankRef, 'ABC123');
  });

  test('3.14 Spanish field aliases (monto, moneda, fecha, tipo) are parsed',
      () async {
    final profile = _CountingProfile(result: null);
    final extractorWithAi = ReceiptExtractorService(
      ocrService: _FakeOcrService('Texto OCR cualquiera'),
      profile: profile,
      multimodalComplete: ({
        required systemPrompt,
        required userPrompt,
        required imageBase64,
        temperature = 0.1,
      }) async {
        return jsonEncode({
          'monto': 77.0,
          'moneda': 'VES',
          'fecha': '2026-04-17T11:00:00Z',
          'tipo': 'gasto',
          'destinatario': 'Supermercado X',
          'referencia': 'REF-42',
          'score': 0.66,
        });
      },
    );

    final image = File('${tempRoot.path}/ai_spanish.jpg')
      ..writeAsBytesSync(List.filled(128, 12));

    final result = await extractorWithAi.extractFromImage(image);

    expect(result.isSuccess, isTrue);
    expect(profile.calls, 0);
    expect(result.proposal!.amount, 77.0);
    expect(result.proposal!.currencyId, 'VES');
    expect(result.proposal!.type, TransactionType.expense);
    expect(result.proposal!.counterpartyName, 'Supermercado X');
    expect(result.proposal!.bankRef, 'REF-42');
    expect(result.proposal!.confidence, closeTo(0.66, 1e-9));
  });

  test('3.15 Garbage AI response falls through to regex fallback', () async {
    const ocrText =
        'PagomovilBDV recibido\n'
        'Recibiste un PagomovilBDV por Bs.100,00 del 0412-7171711 Ref: 184891460184 en fecha 16-04-26 hora: 10:17.';

    final extractorWithAi = ReceiptExtractorService(
      ocrService: _FakeOcrService(ocrText),
      multimodalComplete: ({
        required systemPrompt,
        required userPrompt,
        required imageBase64,
        temperature = 0.1,
      }) async {
        return 'totalmente invalido { no json :: aqui';
      },
    );

    final image = File('${tempRoot.path}/ai_garbage.jpg')
      ..writeAsBytesSync(List.filled(128, 13));

    final result = await extractorWithAi.extractFromImage(image);

    // Falls through to the BDV regex profile and succeeds on the SMS-ish OCR.
    expect(result.isSuccess, isTrue);
    expect(result.proposal!.bankRef, '184891460184');
  });

  test(
    '3.16 Unrecognized type ("PagomóvilBDV Personas") defaults to expense',
    () async {
      final profile = _CountingProfile(result: null);
      final extractorWithAi = ReceiptExtractorService(
        ocrService: _FakeOcrService('Texto OCR cualquiera'),
        profile: profile,
        multimodalComplete: ({
          required systemPrompt,
          required userPrompt,
          required imageBase64,
          temperature = 0.1,
        }) async {
          return jsonEncode({
            'amount': 2400.00,
            'currencyCode': 'Bs',
            'date': '2026-04-17',
            'type': 'PagomóvilBDV Personas',
            'counterpartyName': '04126638500',
            'bankRef': '005717108313O',
            'bankName': 'BANCO DE VENEZUELA',
            'confidence': 0.9,
          });
        },
      );

      final image = File('${tempRoot.path}/ai_unknown_type.jpg')
        ..writeAsBytesSync(List.filled(128, 14));

      final result = await extractorWithAi.extractFromImage(image);

      expect(result.isSuccess, isTrue);
      expect(profile.calls, 0,
          reason: 'Unknown type should default to expense, not fall back.');
      expect(result.proposal!.type, TransactionType.expense);
      expect(result.proposal!.amount, 2400.00);
    },
  );

  test('3.17 Descriptive currency "Bs" is normalized to VES', () async {
    final profile = _CountingProfile(result: null);
    final extractorWithAi = ReceiptExtractorService(
      ocrService: _FakeOcrService('Texto OCR cualquiera'),
      profile: profile,
      multimodalComplete: ({
        required systemPrompt,
        required userPrompt,
        required imageBase64,
        temperature = 0.1,
      }) async {
        return jsonEncode({
          'amount': 100.0,
          'currencyCode': 'Bs',
          'date': '2026-04-17T10:00:00Z',
          'type': 'E',
          'confidence': 0.8,
        });
      },
    );

    final image = File('${tempRoot.path}/ai_bs_currency.jpg')
      ..writeAsBytesSync(List.filled(128, 15));

    final result = await extractorWithAi.extractFromImage(image);

    expect(result.isSuccess, isTrue);
    expect(profile.calls, 0);
    expect(result.proposal!.currencyId, 'VES');
  });

  test(
    '3.18 Full real-log Nexus payload extracts amount/currency/ref/counterparty',
    () async {
      final profile = _CountingProfile(result: null);
      final extractorWithAi = ReceiptExtractorService(
        ocrService: _FakeOcrService('Texto OCR cualquiera'),
        profile: profile,
        multimodalComplete: ({
          required systemPrompt,
          required userPrompt,
          required imageBase64,
          temperature = 0.1,
        }) async {
          // Exact captured string from the production log (2026-04-17).
          return '{"amount":2400.00,"currencyCode":"Bs","date":"2026-04-17",'
              '"type":"PagomóvilBDV Personas","counterpartyName":"04126638500",'
              '"bankRef":"005717108313O","bankName":"BANCO DE VENEZUELA",'
              '"confidence":0.9}';
        },
      );

      final image = File('${tempRoot.path}/ai_real_log.jpg')
        ..writeAsBytesSync(List.filled(128, 16));

      final result = await extractorWithAi.extractFromImage(image);

      expect(result.isSuccess, isTrue);
      expect(profile.calls, 0,
          reason: 'Real-log payload must parse without regex fallback.');
      expect(result.proposal!.amount, 2400.00);
      expect(result.proposal!.currencyId, 'VES');
      expect(result.proposal!.bankRef, '005717108313O');
      expect(result.proposal!.counterpartyName, '04126638500');
      expect(result.proposal!.type, TransactionType.expense);
      expect(result.proposal!.confidence, closeTo(0.9, 1e-9));
    },
  );
}
