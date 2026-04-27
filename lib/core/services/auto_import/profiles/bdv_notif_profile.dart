import 'package:flutter/foundation.dart';
import 'package:wallex/core/models/auto_import/capture_channel.dart';
import 'package:wallex/core/models/auto_import/raw_capture_event.dart';
import 'package:wallex/core/models/auto_import/transaction_proposal.dart';
import 'package:wallex/core/models/transaction/transaction_type.enum.dart';

import 'bank_profile.dart';
import 'bdv_sms_profile.dart';

/// Package name candidates for the BDV mobile app on Android.
const List<String> _bdvPackageCandidates = [
  'com.bancodevenezuela.bdvdigital',
];

/// Bank profile for Banco de Venezuela (BDV) push notifications.
///
/// Uses a dynamic extraction approach instead of exact title matching.
/// Any notification from the BDV app is attempted — the parser extracts
/// whatever structured data it can find (amount, type, reference,
/// counterparty, date) and returns a [TransactionProposal] with a
/// confidence score reflecting how much was extracted.
///
/// If no monetary amount can be found, the notification is rejected
/// (returns `null`) — it's likely promotional or informational.
class BdvNotifProfile implements BankProfile {
  @override
  String get profileId => 'bdv_notif';

  @override
  String get bankName => 'Banco de Venezuela';

  @override
  String get accountMatchName => 'Banco de Venezuela';

  @override
  CaptureChannel get channel => CaptureChannel.notification;

  @override
  List<String> get knownSenders => _bdvPackageCandidates;

  @override
  int get profileVersion => 2;

  // ── Amount extraction regexes ──────────────────────────────────────────────

  /// Matches VES amounts: `Bs.\s*<amount>` where amount uses dots as
  /// thousands separator and comma as decimal (e.g. `Bs. 5.910,00`).
  static final _amountVesRegex = RegExp(
    r'Bs\.\s*([\d.]+,\d{2})',
    caseSensitive: false,
  );

  /// Matches USD amounts: `$.\s*<amount>` (tarjeta internacional format).
  static final _amountUsdRegex = RegExp(
    r'\$\.\s*([\d.]+,\d{2})',
    caseSensitive: false,
  );

  // ── Transaction type keywords ──────────────────────────────────────────────

  static final _incomeKeywords = RegExp(
    r'recibido|recibida|recibiste',
    caseSensitive: false,
  );

  static final _expenseKeywords = RegExp(
    r'realizado|realizada|realizaste|pago sin contacto|punto de venta|consumo|pago en linea',
    caseSensitive: false,
  );

  // ── Reference extraction regexes (tried in order) ──────────────────────────

  static final _refPatterns = [
    RegExp(r'Ref:\s*(\d+)', caseSensitive: false),
    RegExp(r'n.mero de operaci.n\s+(\d+)', caseSensitive: false),
    RegExp(r'numero de operacion\s+(\d+)', caseSensitive: false),
    RegExp(r'#(\d+)', caseSensitive: false),
  ];

  // ── Counterparty extraction regexes (tried in order) ───────────────────────

  /// Name in CAPS followed by "por" — e.g. "de JOINER ALEXANDER ... por"
  static final _counterpartyNameRegex = RegExp(
    r'de\s+([A-ZÁÉÍÓÚÑ][A-ZÁÉÍÓÚÑ\s]+?)\s+por',
    caseSensitive: true,
  );

  /// Phone number after "del" — e.g. "del 0412-7171711"
  static final _counterpartyPhoneFromRegex = RegExp(
    r'del\s+(\d{4}-\d{7})',
    caseSensitive: false,
  );

  /// Phone number after "al" — e.g. "al 0412-7171711"
  static final _counterpartyPhoneToRegex = RegExp(
    r'al\s+(\d{4}-\d{7})',
    caseSensitive: false,
  );

  // ── Date extraction regexes (tried in order) ───────────────────────────────

  /// SMS-style: "en fecha[:] DD-MM-YY hora[:] HH:MM"
  static final _dateSmsStyleRegex = RegExp(
    r'en fecha:?\s*(\d{2}-\d{2}-\d{2})\s*hora:?\s*(\d{2}:\d{2})',
    caseSensitive: false,
  );

  /// Push-style: "el DD-MM-YY a las HH:MM"
  static final _datePushStyleRegex = RegExp(
    r'el\s+(\d{2}-\d{2}-\d{2})\s+a las\s+(\d{2}:\d{2})',
    caseSensitive: false,
  );

  @override
  Future<TransactionProposal?> tryParse(
    RawCaptureEvent event, {
    required String? accountId,
  }) async {
    final result = await tryParseWithDetails(event, accountId: accountId);
    return result.transaction;
  }

  @override
  Future<ParseResult> tryParseWithDetails(
    RawCaptureEvent event, {
    required String? accountId,
  }) async {
    final rawText = event.rawText;
    final newlineIdx = rawText.indexOf('\n');
    if (newlineIdx < 0) {
      return ParseResult.failed(
        'Notificación sin cuerpo (solo título)',
      );
    }

    final title = rawText.substring(0, newlineIdx).trim();
    final body = rawText.substring(newlineIdx + 1).trim();

    if (body.isEmpty) {
      return ParseResult.failed('Cuerpo de la notificación vacío');
    }

    // Combine title + body for flexible extraction
    final fullText = '$title\n$body';

    debugPrint('BdvNotifProfile: attempting parse — title="$title"');

    // ── 1. Amount extraction (required) ──────────────────────────────────────

    double? amount;
    String currencyId;

    final vesMatch = _amountVesRegex.firstMatch(fullText);
    final usdMatch = _amountUsdRegex.firstMatch(fullText);

    if (usdMatch != null) {
      // Prefer USD match (more specific — `$.` prefix)
      amount = BdvSmsProfile.parseVenezuelanNumber(usdMatch.group(1)!);
      currencyId = 'USD';
    } else if (vesMatch != null) {
      amount = BdvSmsProfile.parseVenezuelanNumber(vesMatch.group(1)!);
      currencyId = 'VES';
    } else {
      debugPrint('BdvNotifProfile: no amount found — skipping notification');
      return ParseResult.failed(
        'No se encontró monto (Bs. o \$.) en la notificación',
      );
    }

    if (amount == null) {
      debugPrint('BdvNotifProfile: amount parsing failed — skipping');
      return ParseResult.failed(
        'Monto encontrado pero no se pudo interpretar como número',
      );
    }

    debugPrint('BdvNotifProfile: amount=$amount $currencyId');

    // ── 2. Transaction type detection ────────────────────────────────────────

    TransactionType type;
    final hasIncome = _incomeKeywords.hasMatch(fullText);
    final hasExpense = _expenseKeywords.hasMatch(fullText);

    if (hasIncome && !hasExpense) {
      type = TransactionType.income;
    } else if (hasExpense && !hasIncome) {
      type = TransactionType.expense;
    } else if (hasExpense && hasIncome) {
      // Both keywords present — expense is safer default
      type = TransactionType.expense;
    } else {
      // No keywords — default to expense (user can correct in review)
      type = TransactionType.expense;
    }

    debugPrint('BdvNotifProfile: type=$type');

    // ── 3. Reference extraction ──────────────────────────────────────────────

    String? bankRef;
    for (final pattern in _refPatterns) {
      final match = pattern.firstMatch(fullText);
      if (match != null) {
        final refValue = match.group(1)!;
        // Preserve the '#' prefix for POS references
        if (pattern.pattern.contains('#')) {
          bankRef = '#$refValue';
        } else {
          bankRef = refValue;
        }
        debugPrint('BdvNotifProfile: bankRef=$bankRef');
        break;
      }
    }

    if (bankRef == null) {
      debugPrint('BdvNotifProfile: no bankRef found');
    }

    // ── 4. Counterparty extraction ───────────────────────────────────────────

    String? counterpartyName;

    final nameMatch = _counterpartyNameRegex.firstMatch(fullText);
    if (nameMatch != null) {
      counterpartyName = nameMatch.group(1)!.trim();
      debugPrint('BdvNotifProfile: counterparty (name)=$counterpartyName');
    } else {
      final phoneFromMatch = _counterpartyPhoneFromRegex.firstMatch(fullText);
      if (phoneFromMatch != null) {
        counterpartyName = phoneFromMatch.group(1)!;
        debugPrint('BdvNotifProfile: counterparty (phone from)=$counterpartyName');
      } else {
        final phoneToMatch = _counterpartyPhoneToRegex.firstMatch(fullText);
        if (phoneToMatch != null) {
          counterpartyName = phoneToMatch.group(1)!;
          debugPrint('BdvNotifProfile: counterparty (phone to)=$counterpartyName');
        } else {
          debugPrint('BdvNotifProfile: no counterparty found');
        }
      }
    }

    // ── 5. Date extraction ───────────────────────────────────────────────────

    DateTime? date;

    final smsDateMatch = _dateSmsStyleRegex.firstMatch(fullText);
    if (smsDateMatch != null) {
      date = BdvSmsProfile.parseDate(
        smsDateMatch.group(1)!,
        smsDateMatch.group(2)!,
      );
      debugPrint('BdvNotifProfile: date (sms-style)=$date');
    } else {
      final pushDateMatch = _datePushStyleRegex.firstMatch(fullText);
      if (pushDateMatch != null) {
        date = BdvSmsProfile.parseDate(
          pushDateMatch.group(1)!,
          pushDateMatch.group(2)!,
        );
        debugPrint('BdvNotifProfile: date (push-style)=$date');
      } else {
        debugPrint('BdvNotifProfile: no date found — using receivedAt');
      }
    }

    date ??= event.receivedAt;

    // ── 6. Confidence scoring ────────────────────────────────────────────────

    double confidence;
    if (bankRef != null && type == TransactionType.income ||
        bankRef != null && type == TransactionType.expense) {
      // amount + bankRef + type detected
      confidence = 0.95;
    } else if (bankRef == null &&
        (hasIncome || hasExpense)) {
      // amount + type detected but no bankRef
      confidence = 0.85;
    } else {
      // only amount
      confidence = 0.70;
    }

    debugPrint(
      'BdvNotifProfile: confidence=$confidence '
      '(bankRef=${bankRef != null}, typeDetected=${hasIncome || hasExpense})',
    );

    // ── 7. Build proposal ────────────────────────────────────────────────────

    return ParseResult.parsed(TransactionProposal.newProposal(
      accountId: accountId,
      amount: amount,
      currencyId: currencyId,
      date: date,
      type: type,
      counterpartyName: counterpartyName,
      bankRef: bankRef,
      rawText: event.rawText,
      channel: CaptureChannel.notification,
      sender: event.sender,
      confidence: confidence,
      parsedBySender: 'bdv_notif_v2_dynamic',
    ));
  }
}
