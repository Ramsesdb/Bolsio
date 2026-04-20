import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:wallex/core/services/ai/nexus_ai_service.dart';
import 'package:wallex/core/services/statement_import/models/extracted_row.dart';
import 'package:wallex/core/utils/uuid.dart';

typedef StatementMultimodalCompleteFn = Future<String?> Function({
  required String systemPrompt,
  required String userPrompt,
  required String imageBase64,
  double temperature,
  int maxTokens,
});

const String _systemPrompt =
    'Eres un extractor de movimientos bancarios venezolanos (BDV principalmente).\n'
    'Tu ÚNICA salida es un JSON válido. Sin markdown, sin texto alrededor.\n'
    'Schema:\n'
    '{\n'
    '  "transactions": [\n'
    '    {\n'
    '      "amount": number,\n'
    '      "kind": "income" | "expense" | "fee",\n'
    '      "date_hint": "HOY" | "AYER" | "YYYY-MM-DD",\n'
    '      "time_hint": "HH:MM AM" | "HH:MM PM" | null,\n'
    '      "description": string,\n'
    '      "confidence": number\n'
    '    }\n'
    '  ]\n'
    '}\n'
    'Reglas:\n'
    '- kind="fee" si descripción contiene "comisión", "cobro comisión", "cargo".\n'
    '- kind="income" si icono es ► (derecha) y/o color verde.\n'
    '- kind="expense" en otros casos con signo negativo.\n'
    '- Devuelve un array vacío si no detectas movimientos.';

const String _userPromptInitial =
    'Extrae los movimientos de este estado de cuenta.';

const String _userPromptStrict =
    'Tu respuesta anterior no fue JSON válido. Devuelve SOLO el JSON con el schema indicado. Sin texto, sin markdown, sin explicaciones.';

class StatementExtractorException implements Exception {
  const StatementExtractorException(this.message);
  final String message;
  @override
  String toString() => 'StatementExtractorException: $message';
}

class StatementExtractorService {
  StatementExtractorService({StatementMultimodalCompleteFn? multimodalComplete})
      : _multimodalComplete =
            multimodalComplete ?? NexusAiService.instance.completeMultimodal;

  final StatementMultimodalCompleteFn _multimodalComplete;

  Future<List<ExtractedRow>> extractFromImage({
    required String imageBase64,
    required DateTime pivotDate,
  }) async {
    final firstRaw = await _multimodalComplete(
      systemPrompt: _systemPrompt,
      userPrompt: _userPromptInitial,
      imageBase64: imageBase64,
      temperature: 0.1,
      maxTokens: 2048,
    );

    final firstParsed = _tryParse(firstRaw);
    if (firstParsed != null) {
      return _mapRows(firstParsed, pivotDate);
    }

    debugPrint(
      'StatementExtractor: first attempt failed to parse — retrying with strict prompt',
    );

    final secondRaw = await _multimodalComplete(
      systemPrompt: _systemPrompt,
      userPrompt: _userPromptStrict,
      imageBase64: imageBase64,
      temperature: 0.1,
      maxTokens: 2048,
    );

    final secondParsed = _tryParse(secondRaw);
    if (secondParsed != null) {
      return _mapRows(secondParsed, pivotDate);
    }

    throw const StatementExtractorException(
      'No se pudo interpretar la respuesta del modelo tras 2 intentos.',
    );
  }

  List<dynamic>? _tryParse(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final obj = _extractJsonObject(raw);
    if (obj == null) return null;
    final txs = obj['transactions'];
    if (txs is List) return txs;
    return null;
  }

  List<ExtractedRow> _mapRows(List<dynamic> rawRows, DateTime pivotDate) {
    final result = <ExtractedRow>[];
    for (final raw in rawRows) {
      if (raw is! Map) continue;
      final map = raw.cast<String, dynamic>();

      final amountRaw = map['amount'];
      final amountNum = amountRaw is num
          ? amountRaw.toDouble()
          : double.tryParse(amountRaw?.toString() ?? '');
      if (amountNum == null) continue;
      final amount = amountNum.abs();

      final rawKind = map['kind']?.toString().toLowerCase();
      final kind = (rawKind == 'income' || rawKind == 'expense' || rawKind == 'fee')
          ? rawKind!
          : 'expense';

      final dateHint = map['date_hint']?.toString();
      final timeHint = map['time_hint']?.toString();
      final date = _resolveDate(dateHint, timeHint, pivotDate);

      final description = map['description']?.toString() ?? '';

      final confidenceRaw = map['confidence'];
      final confidence = confidenceRaw is num
          ? confidenceRaw.toDouble().clamp(0.0, 1.0).toDouble()
          : null;

      result.add(ExtractedRow(
        id: generateUUID(),
        amount: amount,
        kind: kind,
        date: date,
        description: description,
        confidence: confidence,
      ));
    }
    return result;
  }

  DateTime _resolveDate(String? dateHint, String? timeHint, DateTime pivotDate) {
    final pivotDay = DateTime(pivotDate.year, pivotDate.month, pivotDate.day);
    DateTime baseDate;
    if (dateHint == null || dateHint.isEmpty) {
      baseDate = pivotDay;
    } else {
      final upper = dateHint.toUpperCase();
      if (upper == 'HOY') {
        baseDate = pivotDay;
      } else if (upper == 'AYER') {
        baseDate = pivotDay.subtract(const Duration(days: 1));
      } else {
        final parsed = DateTime.tryParse(dateHint);
        baseDate = parsed != null
            ? DateTime(parsed.year, parsed.month, parsed.day)
            : pivotDay;
      }
    }

    if (timeHint == null || timeHint.trim().isEmpty) return baseDate;

    final match = RegExp(
      r'^\s*(\d{1,2}):(\d{2})\s*(AM|PM)?\s*$',
      caseSensitive: false,
    ).firstMatch(timeHint);
    if (match == null) return baseDate;

    var hour = int.tryParse(match.group(1) ?? '') ?? 0;
    final minute = int.tryParse(match.group(2) ?? '') ?? 0;
    final suffix = match.group(3)?.toUpperCase();
    if (suffix == 'PM' && hour < 12) hour += 12;
    if (suffix == 'AM' && hour == 12) hour = 0;
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return baseDate;

    return DateTime(
      baseDate.year,
      baseDate.month,
      baseDate.day,
      hour,
      minute,
    );
  }
}

Map<String, dynamic>? _extractJsonObject(String raw) {
  var cleaned = raw.trim();

  final fenced = RegExp(r'```(?:json)?\s*([\s\S]*?)\s*```', multiLine: true);
  final fenceMatch = fenced.firstMatch(cleaned);
  if (fenceMatch != null) {
    cleaned = fenceMatch.group(1)!.trim();
  }

  try {
    final decoded = jsonDecode(cleaned);
    if (decoded is Map<String, dynamic>) return decoded;
  } catch (_) {}

  final objMatch = RegExp(r'\{[\s\S]*\}').firstMatch(cleaned);
  if (objMatch != null) {
    try {
      final decoded = jsonDecode(objMatch.group(0)!);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {}
  }

  return null;
}
