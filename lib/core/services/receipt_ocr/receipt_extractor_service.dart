import 'dart:io';
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:wallex/core/database/services/user-setting/user_setting_service.dart';
import 'package:wallex/core/models/auto_import/capture_channel.dart';
import 'package:wallex/core/models/auto_import/raw_capture_event.dart';
import 'package:wallex/core/models/auto_import/transaction_proposal.dart';
import 'package:wallex/core/models/transaction/transaction_type.enum.dart';
import 'package:wallex/core/services/ai/nexus_ai_service.dart';
import 'package:wallex/core/services/auto_import/profiles/bdv_notif_profile.dart';
import 'package:wallex/core/services/auto_import/profiles/bank_profile.dart';
import 'package:wallex/core/services/receipt_ocr/ocr_service.dart';

typedef MultimodalCompleteFn = Future<String?> Function({
  required String systemPrompt,
  required String userPrompt,
  required String imageBase64,
  double temperature,
});

/// Extracts a JSON object from an AI response that may be wrapped in markdown
/// fences, surrounded by prose, or returned as bare JSON. Returns null if no
/// valid `Map<String, dynamic>` can be recovered.
Map<String, dynamic>? _extractJsonObject(String raw) {
  var cleaned = raw.trim();

  // 1. Strip triple-backtick fences: ```json ... ``` or ``` ... ```
  final fenced = RegExp(r'```(?:json)?\s*([\s\S]*?)\s*```', multiLine: true);
  final fenceMatch = fenced.firstMatch(cleaned);
  if (fenceMatch != null) {
    cleaned = fenceMatch.group(1)!.trim();
  }

  // 2. Try direct decode on the (possibly de-fenced) text.
  try {
    final decoded = jsonDecode(cleaned);
    if (decoded is Map<String, dynamic>) return decoded;
  } catch (_) {}

  // 3. Greedy match the outermost {...} block and retry. The greedy regex
  //    captures from the first `{` to the last `}`, which handles prose
  //    prefixes/suffixes and nested objects.
  final objMatch = RegExp(r'\{[\s\S]*\}').firstMatch(cleaned);
  if (objMatch != null) {
    try {
      final decoded = jsonDecode(objMatch.group(0)!);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {}
  }

  return null;
}

/// Returns the first non-null, non-empty value found under any of [keys] in
/// the given map. Useful for accepting aliased field names from the LLM
/// (`amount` vs `monto`, `currencyCode` vs `moneda`, etc.).
Object? _readField(Map<String, dynamic> m, List<String> keys) {
  for (final key in keys) {
    final value = m[key];
    if (value == null) continue;
    if (value is String && value.trim().isEmpty) continue;
    return value;
  }
  return null;
}

enum ExtractionOutcome {
  success,
  empty,
  noAmount,
  imageCorrupt,
}

/// Deterministic fallback category assigned to non-transfer proposals when
/// neither the AI nor the regex profile resolves one. Without this the
/// `transactions` XOR CHECK constraint (`categoryID` vs `receivingAccountID`)
/// fails on INSERT. Matches `personal_ve_seeders.dart` "Otros Gastos".
const String _kFallbackExpenseCategoryId = 'pve_e12';

class ExtractionResult {
  const ExtractionResult._({
    required this.outcome,
    this.proposal,
    required this.ocrText,
    this.errorKey,
    required this.currencyAmbiguous,
    this.extractedCurrencyCode,
  });

  final ExtractionOutcome outcome;
  final TransactionProposal? proposal;
  final String ocrText;
  final String? errorKey;
  final bool currencyAmbiguous;
  final String? extractedCurrencyCode;

  bool get isSuccess => outcome == ExtractionOutcome.success;

  factory ExtractionResult.success({
    required TransactionProposal proposal,
    required String ocrText,
    required bool currencyAmbiguous,
    required String? extractedCurrencyCode,
  }) {
    return ExtractionResult._(
      outcome: ExtractionOutcome.success,
      proposal: proposal,
      ocrText: ocrText,
      currencyAmbiguous: currencyAmbiguous,
      extractedCurrencyCode: extractedCurrencyCode,
    );
  }

  factory ExtractionResult.empty(String ocrText) {
    return ExtractionResult._(
      outcome: ExtractionOutcome.empty,
      ocrText: ocrText,
      errorKey: 'error.ocr_empty',
      currencyAmbiguous: false,
    );
  }

  factory ExtractionResult.noAmount(String ocrText) {
    return ExtractionResult._(
      outcome: ExtractionOutcome.noAmount,
      ocrText: ocrText,
      errorKey: 'error.no_amount',
      currencyAmbiguous: false,
    );
  }

  factory ExtractionResult.imageCorrupt() {
    return const ExtractionResult._(
      outcome: ExtractionOutcome.imageCorrupt,
      ocrText: '',
      errorKey: 'error.image_corrupt',
      currencyAmbiguous: false,
    );
  }
}

class ReceiptExtractorService {
  ReceiptExtractorService({
    OcrService? ocrService,
    BankProfile? profile,
    MultimodalCompleteFn? multimodalComplete,
  })  : _ocrService = ocrService ?? OcrService(),
        _profile = profile ?? BdvNotifProfile(),
        _multimodalComplete =
            multimodalComplete ?? NexusAiService.instance.completeMultimodal;

  final OcrService _ocrService;
  final BankProfile _profile;
  final MultimodalCompleteFn _multimodalComplete;

  Future<ExtractionResult> extractFromImage(
    File imageFile, {
    String sender = 'com.bancodevenezuela.bdvdigital',
    String? accountId,
    String? preferredCurrency,
  }) async {
    try {
      final imageBytes = await imageFile.readAsBytes();
      debugPrint(
        'ReceiptExtractor: extractFromImage start path=${imageFile.path} sizeBytes=${imageBytes.length}',
      );

      final ocrText = await _ocrService.recognize(imageFile);
      final ocrPreview = ocrText.length > 120
          ? '${ocrText.substring(0, 120)}…'
          : ocrText;
      debugPrint(
        'ReceiptExtractor: OCR text length=${ocrText.length} chars'
        '${ocrText.isNotEmpty ? ' preview="$ocrPreview"' : ''}',
      );

      final imageBase64 = base64Encode(imageBytes);

      return extractFromOcrTextWithAi(
        ocrText,
        imageBase64: imageBase64,
        sender: sender,
        accountId: accountId,
        preferredCurrency: preferredCurrency,
      );
    } on FormatException {
      debugPrint(
        'ReceiptExtractor: extractFromImage FormatException — outcome=imageCorrupt',
      );
      return ExtractionResult.imageCorrupt();
    }
  }

  Future<ExtractionResult> extractFromOcrTextWithAi(
    String ocrText, {
    required String imageBase64,
    String sender = 'com.bancodevenezuela.bdvdigital',
    String? accountId,
    String? preferredCurrency,
  }) async {
    final normalized = ocrText.trim();
    if (normalized.isEmpty) {
      debugPrint(
        'ReceiptExtractor: AI step skipped — reason: OCR text empty after trim',
      );
      final result = ExtractionResult.empty(ocrText);
      _logExit(result);
      return result;
    }

    final aiEnabled = _isReceiptAiEnabled();
    var fallbackFromTimeout = false;

    if (!aiEnabled) {
      final aiMaster = appStateSettings[SettingKey.nexusAiEnabled] == '1';
      final receiptAi = appStateSettings[SettingKey.receiptAiEnabled] != '0';
      debugPrint(
        'ReceiptExtractor: AI step skipped — reason: disabled '
        '(nexusAiEnabled=$aiMaster receiptAiEnabled=$receiptAi)',
      );
    } else {
      ExtractionResult? aiSuccess;
      for (var attempt = 1; attempt <= 2; attempt++) {
        debugPrint(
          'ReceiptExtractor: Calling Nexus multimodal (attempt $attempt/2)',
        );
        try {
          // Payload contract: openspec/changes/attachments-and-receipt-ocr/design.md#nexusaiservicecompletemultimodal--wire-contract
          final aiRaw = await _multimodalComplete(
            systemPrompt:
                'Responde SOLO con JSON valido. Sin markdown, sin texto adicional. '
                'Schema: {"amount":number,"currencyCode":string,"date":string,"type":string,'
                '"counterpartyName":string,"bankRef":string,"bankName":string,"confidence":number}.',
            userPrompt: 'OCR extracted text:\n$normalized',
            imageBase64: imageBase64,
            temperature: 0.1,
          );

          if (aiRaw == null) {
            debugPrint(
              'ReceiptExtractor: Nexus returned (null) on attempt $attempt/2',
            );
            if (attempt == 1) {
              await Future<void>.delayed(const Duration(milliseconds: 500));
            }
            continue;
          }

          final rawPreview = aiRaw.length > 200
              ? '${aiRaw.substring(0, 200)}…'
              : aiRaw;
          debugPrint(
            'ReceiptExtractor: Nexus returned length=${aiRaw.length} preview="$rawPreview" (attempt $attempt/2)',
          );

          final aiResult = _parseAiResult(
            aiRaw,
            normalizedOcrText: normalized,
            sender: sender,
            accountId: accountId,
            preferredCurrency: preferredCurrency,
          );
          if (aiResult != null) {
            aiSuccess = aiResult;
            break;
          }

          debugPrint(
            'ReceiptExtractor: AI response unusable (missing amount or not parseable) on attempt $attempt/2',
          );
          if (attempt == 1) {
            await Future<void>.delayed(const Duration(milliseconds: 500));
          }
        } on TimeoutException {
          fallbackFromTimeout = true;
          debugPrint(
            'ReceiptExtractor: Nexus multimodal TimeoutException on attempt $attempt/2 — aborting retry loop',
          );
          break;
        } catch (e) {
          // Any AI failure falls back to deterministic regex parsing.
          debugPrint(
            'ReceiptExtractor: Nexus multimodal threw on attempt $attempt/2: $e',
          );
          if (attempt == 1) {
            await Future<void>.delayed(const Duration(milliseconds: 500));
          }
        }
      }

      if (aiSuccess != null) {
        _logExit(aiSuccess);
        return aiSuccess;
      }
    }

    debugPrint(
      'ReceiptExtractor: Falling back to BdvNotifProfile regex '
      '(timeout=$fallbackFromTimeout aiEnabled=$aiEnabled)',
    );
    final fallback = await extractFromOcrText(
      normalized,
      sender: sender,
      accountId: accountId,
      preferredCurrency: preferredCurrency,
      forceFallbackConfidence: fallbackFromTimeout,
    );
    debugPrint(
      'ReceiptExtractor: Regex fallback proposal='
      '${fallback.proposal == null ? '(null)' : 'amount=${fallback.proposal!.amount} currency=${fallback.proposal!.currencyId} confidence=${fallback.proposal!.confidence}'}',
    );
    _logExit(fallback);
    return fallback;
  }

  void _logExit(ExtractionResult result) {
    final p = result.proposal;
    final summary = p == null
        ? 'amount=(null) currency=(null) confidence=(null)'
        : 'amount=${p.amount} currency=${p.currencyId} confidence=${p.confidence}';
    debugPrint(
      'ReceiptExtractor: exit outcome=${result.outcome.name} $summary',
    );
  }

  Future<ExtractionResult> extractFromOcrText(
    String ocrText, {
    String sender = 'com.bancodevenezuela.bdvdigital',
    String? accountId,
    String? preferredCurrency,
    bool forceFallbackConfidence = false,
  }) async {
    final normalized = ocrText.trim();
    if (normalized.isEmpty) {
      return ExtractionResult.empty(ocrText);
    }

    final event = RawCaptureEvent(
      rawText: 'Comprobante OCR\n$normalized',
      sender: sender,
      receivedAt: DateTime.now(),
      channel: CaptureChannel.receiptImage,
    );

    final parsed = await _profile.tryParse(event, accountId: accountId);
    if (parsed == null) {
      return ExtractionResult.noAmount(normalized);
    }

    final preferred = preferredCurrency ??
        appStateSettings[SettingKey.preferredCurrency] ??
        'USD';

    final currencyInfo = _detectCurrency(normalized);
    final effectiveCurrency = currencyInfo.ambiguous
        ? preferred.toUpperCase()
        : (currencyInfo.extractedCurrencyCode ?? parsed.currencyId);

    final proposal = parsed.copyWith(
      channel: CaptureChannel.receiptImage,
      sender: sender,
      rawText: normalized,
      currencyId: effectiveCurrency,
      confidence: forceFallbackConfidence ? 0.7 : parsed.confidence,
      proposedCategoryId: parsed.type.isIncomeOrExpense
          ? (parsed.proposedCategoryId ?? _kFallbackExpenseCategoryId)
          : parsed.proposedCategoryId,
    );

    return ExtractionResult.success(
      proposal: proposal,
      ocrText: normalized,
      currencyAmbiguous: currencyInfo.ambiguous,
      extractedCurrencyCode: currencyInfo.extractedCurrencyCode,
    );
  }

  _CurrencyDetectionResult _detectCurrency(String text) {
    final hasVes = RegExp(r'Bs\.', caseSensitive: false).hasMatch(text);
    final hasUsd = RegExp(r'(\$\.|\$\s*\d|\bUSD\b)', caseSensitive: false)
        .hasMatch(text);

    if (hasVes && !hasUsd) {
      return const _CurrencyDetectionResult(
        ambiguous: false,
        extractedCurrencyCode: 'VES',
      );
    }
    if (hasUsd && !hasVes) {
      return const _CurrencyDetectionResult(
        ambiguous: false,
        extractedCurrencyCode: 'USD',
      );
    }

    return const _CurrencyDetectionResult(
      ambiguous: true,
      extractedCurrencyCode: null,
    );
  }

  bool _isReceiptAiEnabled() {
    final aiMaster = appStateSettings[SettingKey.nexusAiEnabled] == '1';
    final receiptAi = appStateSettings[SettingKey.receiptAiEnabled] != '0';
    return aiMaster && receiptAi;
  }

  ExtractionResult? _parseAiResult(
    String? rawAiContent, {
    required String normalizedOcrText,
    required String sender,
    required String? accountId,
    required String? preferredCurrency,
  }) {
    if (rawAiContent == null || rawAiContent.isEmpty) {
      return null;
    }

    if (kDebugMode) {
      final preview = rawAiContent.length > 500
          ? '${rawAiContent.substring(0, 500)}…'
          : rawAiContent;
      debugPrint('ReceiptExtractor: AI raw response (first 500 chars): $preview');
    }

    final decoded = _extractJsonObject(rawAiContent);
    if (decoded == null) {
      debugPrint(
        'ReceiptExtractor: AI response not parseable as JSON, falling back to regex',
      );
      return null;
    }

    // amount is the ONLY truly required field. Without it we can't build a
    // transaction proposal, so we fall back to the regex profile.
    final amountRaw = _readField(decoded, const [
      'amount',
      'monto',
      'total',
      'value',
    ]);
    final amount = amountRaw is num
        ? amountRaw.toDouble()
        : double.tryParse(amountRaw?.toString() ?? '');
    if (amount == null || amount <= 0) {
      debugPrint(
        "ReceiptExtractor: AI JSON missing required 'amount' field, falling back to regex",
      );
      return null;
    }

    var appliedFallback = false;

    // type: unrecognized values default to expense (95% of receipts are
    // expenses; user can edit in review page).
    final rawTypeValue = _readField(decoded, const ['type', 'tipo']);
    final parsedType = _parseType(rawTypeValue);
    final type = parsedType ?? TransactionType.expense;
    if (parsedType == null) {
      appliedFallback = true;
      if (kDebugMode) {
        debugPrint(
          'ReceiptExtractor: type="$rawTypeValue" unrecognized, defaulting to expense',
        );
      }
    }

    // date: malformed or missing defaults to now().
    final now = DateTime.now();
    final dateRaw =
        _readField(decoded, const ['date', 'fecha', 'timestamp'])?.toString() ??
            '';
    final parsedDate = DateTime.tryParse(dateRaw);
    final date = parsedDate ?? now;
    if (parsedDate == null) {
      appliedFallback = true;
      if (kDebugMode && dateRaw.isNotEmpty) {
        debugPrint(
          'ReceiptExtractor: date="$dateRaw" unparseable, defaulting to now()',
        );
      }
    }

    // currency: missing → preferred setting, descriptive values → normalize.
    final preferred =
        (preferredCurrency ?? appStateSettings[SettingKey.preferredCurrency] ?? 'USD')
            .toUpperCase();
    final rawCurrency = _readField(decoded, const [
      'currencyCode',
      'currency',
      'moneda',
      'currency_code',
    ])?.toString();
    final normalizedCurrency = _normalizeCurrencyCode(rawCurrency);
    final extractedCurrency = normalizedCurrency;
    final aiCurrency = (normalizedCurrency == null || normalizedCurrency.isEmpty)
        ? preferred
        : normalizedCurrency;
    if (normalizedCurrency == null) {
      appliedFallback = true;
      if (kDebugMode && rawCurrency != null && rawCurrency.isNotEmpty) {
        debugPrint(
          'ReceiptExtractor: currency="$rawCurrency" unrecognized, defaulting to preferred=$preferred',
        );
      }
    }

    final confidenceRaw = _readField(decoded, const ['confidence', 'score']);
    final confidence = confidenceRaw is num
        ? confidenceRaw.toDouble().clamp(0.0, 1.0)
        : 0.8;

    final counterpartyName = _readField(decoded, const [
      'counterpartyName',
      'counterparty',
      'destinatario',
      'recipient',
      'payee',
    ])?.toString();
    final bankRef = _readField(decoded, const [
      'bankRef',
      'reference',
      'referencia',
      'operationId',
      'operation',
    ])?.toString();

    final parseTag = appliedFallback ? 'AI parsed OK (with fallbacks)' : 'AI parsed OK';
    debugPrint(
      'ReceiptExtractor: $parseTag — amount=$amount currency=$aiCurrency type=${type.name} confidence=$confidence',
    );

    final proposal = TransactionProposal.newProposal(
      accountId: accountId,
      amount: amount,
      currencyId: aiCurrency,
      date: date,
      type: type,
      counterpartyName: counterpartyName,
      bankRef: bankRef,
      rawText: normalizedOcrText,
      channel: CaptureChannel.receiptImage,
      sender: sender,
      confidence: confidence,
      parsedBySender: 'nexus_multimodal',
      proposedCategoryId:
          type.isIncomeOrExpense ? _kFallbackExpenseCategoryId : null,
    );

    return ExtractionResult.success(
      proposal: proposal,
      ocrText: normalizedOcrText,
      currencyAmbiguous: false,
      extractedCurrencyCode: extractedCurrency,
    );
  }

  /// Maps the AI's free-form `type` value to a [TransactionType].
  ///
  /// Returns `null` when the value is unrecognized (e.g. "PagomóvilBDV
  /// Personas"). Callers are expected to treat null as "default to expense"
  /// — expense is the safe fallback because ~95% of captured receipts are
  /// expenses and the user can edit in the review page.
  TransactionType? _parseType(Object? rawType) {
    final value = rawType?.toString().trim().toUpperCase();
    if (value == null || value.isEmpty) return null;
    switch (value) {
      case 'E':
      case 'EXPENSE':
      case 'GASTO':
        return TransactionType.expense;
      case 'I':
      case 'INCOME':
      case 'INGRESO':
        return TransactionType.income;
      case 'T':
      case 'TRANSFER':
      case 'TRANSFERENCIA':
        return TransactionType.transfer;
      default:
        return null;
    }
  }

  /// Normalizes the AI's free-form currency label to an ISO-like code.
  ///
  /// Examples:
  ///   "Bs", "Bs.", "BsS", "Bs.S", "Bolívares", "VES", "VEF" → "VES"
  ///   "$", "USD", "US$", "dólares"                          → "USD"
  ///   "€", "EUR", "euros"                                   → "EUR"
  ///
  /// Returns null when the input is null/empty/unrecognized, so callers can
  /// decide whether to fall back to the user's preferred currency.
  String? _normalizeCurrencyCode(String? raw) {
    if (raw == null) return null;
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;

    final upper = trimmed.toUpperCase();

    // Strip trailing punctuation (handles "Bs.", "$.", "BS,") to match
    // descriptive symbols that the LLM often echoes from the receipt.
    final cleaned = upper.replaceAll(RegExp(r'[.,;:\s]+$'), '');

    // Venezuelan bolívares (any of the historical codes / variants).
    const vesAliases = {
      'BS',
      'BSS',
      'BS.S',
      'BSF',
      'VES',
      'VEF',
      'VED',
      'BOLIVARES',
      'BOLÍVARES',
      'BOLIVAR',
      'BOLÍVAR',
    };
    if (vesAliases.contains(cleaned) || upper.startsWith('BOLÍV') ||
        upper.startsWith('BOLIV')) {
      return 'VES';
    }

    // US dollars.
    const usdAliases = {
      '\$',
      'USD',
      'US\$',
      'US',
      'DOLAR',
      'DÓLAR',
      'DOLARES',
      'DÓLARES',
    };
    if (usdAliases.contains(cleaned) || cleaned.startsWith('US\$') ||
        cleaned.startsWith('DOLAR') || cleaned.startsWith('DÓLAR')) {
      return 'USD';
    }

    // Euros.
    const eurAliases = {'€', 'EUR', 'EURO', 'EUROS'};
    if (eurAliases.contains(cleaned)) {
      return 'EUR';
    }

    // Fallback: if the input is already a 3-letter ISO code, pass it through.
    if (RegExp(r'^[A-Z]{3}$').hasMatch(cleaned)) {
      return cleaned;
    }

    return null;
  }
}

class _CurrencyDetectionResult {
  const _CurrencyDetectionResult({
    required this.ambiguous,
    required this.extractedCurrencyCode,
  });

  final bool ambiguous;
  final String? extractedCurrencyCode;
}
