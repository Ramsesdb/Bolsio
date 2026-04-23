import 'package:wallex/core/models/auto_import/capture_channel.dart';
import 'package:wallex/core/models/auto_import/raw_capture_event.dart';
import 'package:wallex/core/models/auto_import/transaction_proposal.dart';
import 'package:wallex/core/models/transaction/transaction_type.enum.dart';

import 'bank_profile.dart';

/// Bank profile for Banco de Venezuela (BDV) SMS messages.
///
/// Parses transaction SMS sent from shortcodes `2661` and `2662`.
/// Currently supports:
/// - Pagomovil recibido (income)
///
/// Messages that don't match any pattern (OTPs, verification codes, etc.)
/// are silently rejected (returns `null`).
class BdvSmsProfile implements BankProfile {
  @override
  String get profileId => 'bdv_sms';

  @override
  String get bankName => 'Banco de Venezuela';

  @override
  String get accountMatchName => 'Banco de Venezuela';

  @override
  CaptureChannel get channel => CaptureChannel.sms;

  @override
  List<String> get knownSenders => const ['2661', '2662'];

  @override
  int get profileVersion => 1;

  /// Regex for "Pagomovil recibido" SMS messages.
  ///
  /// Matches patterns like:
  ///   Recibiste un PagomovilBDV por Bs.12.000,00 del 0412-7635070 Ref: 108834202054 en fecha: 29-03-26 hora: 18:01.
  ///   Recibiste un PagomovilBDV por Bs. 210,00 del 0412-6638500 Ref: 000390572967 en fecha: 30-10-23 hora: 12:35
  ///   Recibiste un PagomovilBDV por Bs. 900,00 del 0412-7635070 Ref: 002103869591 en fecha: 25-01-25 hora: 21:26
  ///   Recibiste un PagomovilBDV por Bs.10.620,00 del 0412-7635070 Ref: 108639858076 en fecha 27-03-26 hora: 21:31.
  ///
  /// Note: The `:` after "fecha" and "hora" is optional (some messages omit it).
  ///
  /// Groups: 1=amount, 2=counterpartyPhone, 3=bankRef, 4=date, 5=time
  static final _pagomovilRecibidoRegex = RegExp(
    r'Recibiste un PagomovilBDV por Bs\.\s*([\d.]+,\d{2})\s*del\s*([\d-]+)\s*Ref:\s*(\d+)\s*en fecha:?\s*([\d-]+)\s*hora:?\s*([\d:]+)',
    caseSensitive: false,
  );

  // TODO: agregar "pagomovil enviado" cuando se capturen fixtures reales
  // TODO: agregar "consumo TDC/TDD" cuando se capturen fixtures reales

  @override
  TransactionProposal? tryParse(
    RawCaptureEvent event, {
    required String? accountId,
  }) {
    return tryParseWithDetails(event, accountId: accountId).transaction;
  }

  @override
  ParseResult tryParseWithDetails(
    RawCaptureEvent event, {
    required String? accountId,
  }) {
    // Try pagomovil recibido
    final match = _pagomovilRecibidoRegex.firstMatch(event.rawText);
    if (match != null) {
      final proposal = _parsePagomovilRecibido(match, event, accountId);
      if (proposal != null) {
        return ParseResult.parsed(proposal);
      }
      return ParseResult.failed(
        'Patrón de Pagomóvil detectado pero monto o fecha inválidos',
      );
    }

    // No pattern matched — likely OTP / código / promoción
    return ParseResult.failed(
      'SMS no coincide con ningún patrón conocido (OTP/código/promo)',
    );
  }

  TransactionProposal? _parsePagomovilRecibido(
    RegExpMatch match,
    RawCaptureEvent event,
    String? accountId,
  ) {
    final amountStr = match.group(1)!;
    final counterpartyPhone = match.group(2)!;
    final bankRef = match.group(3)!;
    final dateStr = match.group(4)!;
    final timeStr = match.group(5)!;

    final amount = parseVenezuelanNumber(amountStr);
    if (amount == null) return null;

    final date = parseDate(dateStr, timeStr);
    if (date == null) return null;

    return TransactionProposal.newProposal(
      accountId: accountId,
      amount: amount,
      currencyId: 'VES',
      date: date,
      type: TransactionType.income,
      counterpartyName: counterpartyPhone,
      bankRef: bankRef,
      rawText: event.rawText,
      channel: CaptureChannel.sms,
      sender: event.sender,
      confidence: 0.95,
      parsedBySender: 'bdv_sms_v1_pagomovil_recibido',
    );
  }

  /// Converts a Venezuelan-formatted number string to a double.
  ///
  /// Venezuelan format uses `.` as thousands separator and `,` as decimal separator.
  /// Examples:
  /// - `'12.000,00'` -> `12000.0`
  /// - `'210,00'` -> `210.0`
  /// - `'1.234.567,89'` -> `1234567.89`
  static double? parseVenezuelanNumber(String s) {
    try {
      // Remove thousands separator (dots), then replace decimal comma with dot
      final normalized = s.replaceAll('.', '').replaceAll(',', '.');
      return double.parse(normalized);
    } catch (_) {
      return null;
    }
  }

  /// Parses a date string in `DD-MM-YY` format and time in `HH:MM` format.
  ///
  /// Assumes 2-digit years are in the 2000s (e.g. `26` -> `2026`).
  /// Returns `null` if parsing fails.
  static DateTime? parseDate(String date, String time) {
    try {
      final dateParts = date.split('-');
      if (dateParts.length != 3) return null;

      final day = int.parse(dateParts[0]);
      final month = int.parse(dateParts[1]);
      var year = int.parse(dateParts[2]);

      // 2-digit year: assume 2000+
      if (year < 100) {
        year += 2000;
      }

      final timeParts = time.split(':');
      if (timeParts.length != 2) return null;

      final hour = int.parse(timeParts[0]);
      final minute = int.parse(timeParts[1]);

      return DateTime(year, month, day, hour, minute);
    } catch (_) {
      return null;
    }
  }
}
