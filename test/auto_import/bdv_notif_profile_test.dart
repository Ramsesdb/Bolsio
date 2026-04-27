import 'package:flutter_test/flutter_test.dart';
import 'package:wallex/core/models/auto_import/capture_channel.dart';
import 'package:wallex/core/models/auto_import/raw_capture_event.dart';
import 'package:wallex/core/models/transaction/transaction_type.enum.dart';
import 'package:wallex/core/services/auto_import/profiles/bdv_notif_profile.dart';

void main() {
  late BdvNotifProfile profile;

  setUp(() {
    profile = BdvNotifProfile();
  });

  RawCaptureEvent makeEvent(String rawText,
      {String sender = 'com.bancodevenezuela.bdvdigital'}) {
    return RawCaptureEvent(
      rawText: rawText,
      sender: sender,
      receivedAt: DateTime(2026, 4, 15, 14, 30),
      channel: CaptureChannel.notification,
    );
  }

  group('BdvNotifProfile metadata', () {
    test('bankName is Banco de Venezuela', () {
      expect(profile.bankName, 'Banco de Venezuela');
    });

    test('accountMatchName is Banco de Venezuela', () {
      expect(profile.accountMatchName, 'Banco de Venezuela');
    });

    test('channel is notification', () {
      expect(profile.channel, CaptureChannel.notification);
    });

    test('knownSenders contains at least one package placeholder', () {
      expect(profile.knownSenders, isNotEmpty);
      expect(profile.knownSenders, contains('com.bancodevenezuela.bdvdigital'));
    });

    test('profileVersion is 2', () {
      expect(profile.profileVersion, 2);
    });
  });

  group('BdvNotifProfile — Transferencia BDV recibida (income VES)', () {
    test('Fixture: Transferencia recibida por Bs.277.000,00', () async {
      const title = 'Transferencia BDV recibida';
      const body =
          '"Recibiste una transferencia BDV de JOINER ALEXANDER ROVARIO SAAVEDRA por Bs.277.000,00 bajo el número de operación 059135723999"';
      final event = makeEvent('$title\n$body');

      final proposal = await profile.tryParse(event, accountId: 'acc-bdv');

      expect(proposal, isNotNull);
      expect(proposal!.amount, 277000.00);
      expect(proposal.currencyId, 'VES');
      expect(proposal.type, TransactionType.income);
      expect(proposal.bankRef, '059135723999');
      expect(proposal.counterpartyName,
          'JOINER ALEXANDER ROVARIO SAAVEDRA');
      expect(proposal.confidence, 0.95);
      expect(proposal.channel, CaptureChannel.notification);
      expect(proposal.accountId, 'acc-bdv');
      expect(proposal.parsedBySender, 'bdv_notif_v2_dynamic');
    });
  });

  group('BdvNotifProfile — PagomóvilBDV recibido Format A (income VES)', () {
    test('Fixture: Pagomovil recibido with accent on title', () async {
      const title = 'PagomóvilBDV recibido'; // WITH accent
      const body =
          'Recibiste un PagomovilBDV de ROBERTO CARLO PALMAR MOLERO por Bs.50,00 bajo el numero de operacion 005703907569';
      final event = makeEvent('$title\n$body');

      final proposal = await profile.tryParse(event, accountId: 'acc-bdv');

      expect(proposal, isNotNull);
      expect(proposal!.amount, 50.00);
      expect(proposal.currencyId, 'VES');
      expect(proposal.type, TransactionType.income);
      expect(proposal.bankRef, '005703907569');
      expect(proposal.counterpartyName, 'ROBERTO CARLO PALMAR MOLERO');
      expect(proposal.confidence, 0.95);
      expect(proposal.channel, CaptureChannel.notification);
      expect(proposal.accountId, 'acc-bdv');
      expect(proposal.parsedBySender, 'bdv_notif_v2_dynamic');
    });

    test('Fixture: Pagomovil recibido WITHOUT accent on title (Format A body)',
        () async {
      const title = 'PagomovilBDV recibido'; // WITHOUT accent
      const body =
          'Recibiste un PagomovilBDV de ROBERTO CARLO PALMAR MOLERO por Bs.50,00 bajo el numero de operacion 005703907569';
      final event = makeEvent('$title\n$body');

      final proposal = await profile.tryParse(event, accountId: 'acc-bdv');

      expect(proposal, isNotNull);
      expect(proposal!.amount, 50.00);
      expect(proposal.counterpartyName, 'ROBERTO CARLO PALMAR MOLERO');
      expect(proposal.bankRef, '005703907569');
      expect(proposal.parsedBySender, 'bdv_notif_v2_dynamic');
    });
  });

  group('BdvNotifProfile — PagomovilBDV recibido Format B (income VES)', () {
    test('Fixture: Pagomovil recibido SMS-style with phone number', () async {
      const title = 'PagomovilBDV recibido'; // WITHOUT accent
      const body =
          'Recibiste un PagomovilBDV por Bs.100,00 del 0412-7171711 Ref: 184891460184 en fecha 16-04-26 hora: 10:17.';
      final event = makeEvent('$title\n$body');

      final proposal = await profile.tryParse(event, accountId: 'acc-bdv');

      expect(proposal, isNotNull);
      expect(proposal!.amount, 100.00);
      expect(proposal.currencyId, 'VES');
      expect(proposal.type, TransactionType.income);
      expect(proposal.bankRef, '184891460184');
      expect(proposal.counterpartyName, '0412-7171711');
      expect(proposal.confidence, 0.95);
      expect(proposal.channel, CaptureChannel.notification);
      expect(proposal.date, DateTime(2026, 4, 16, 10, 17));
      expect(proposal.accountId, 'acc-bdv');
      expect(proposal.parsedBySender, 'bdv_notif_v2_dynamic');
    });

    test('Fixture: Format B with accented title', () async {
      const title = 'PagomóvilBDV recibido'; // WITH accent
      const body =
          'Recibiste un PagomovilBDV por Bs.10.620,00 del 0412-7635070 Ref: 108639858076 en fecha 27-03-26 hora: 21:31.';
      final event = makeEvent('$title\n$body');

      final proposal = await profile.tryParse(event, accountId: 'acc-bdv');

      expect(proposal, isNotNull);
      expect(proposal!.amount, 10620.00);
      expect(proposal.counterpartyName, '0412-7635070');
      expect(proposal.bankRef, '108639858076');
      expect(proposal.date, DateTime(2026, 3, 27, 21, 31));
      expect(proposal.parsedBySender, 'bdv_notif_v2_dynamic');
    });
  });

  group('BdvNotifProfile — BiopagoBDV sin contacto (expense VES)', () {
    test('Fixture: Pago sin contacto por Bs. 5.910,00', () async {
      const title = 'Operaciones por Punto de venta / BiopagoBDV';
      const body =
          'Pago sin contacto realizado en punto de venta por Bs. 5.910,00, bajo el #2977, disp. 366.258,19 el 15-04-26 a las 17:46.';
      final event = makeEvent('$title\n$body');

      final proposal = await profile.tryParse(event, accountId: 'acc-bdv');

      expect(proposal, isNotNull);
      expect(proposal!.amount, 5910.00);
      expect(proposal.currencyId, 'VES');
      expect(proposal.type, TransactionType.expense);
      expect(proposal.bankRef, '#2977');
      expect(proposal.counterpartyName, isNull);
      // Dynamic parser: bankRef + type detected → 0.95
      expect(proposal.confidence, 0.95);
      expect(proposal.channel, CaptureChannel.notification);
      expect(proposal.date, DateTime(2026, 4, 15, 17, 46));
      expect(proposal.parsedBySender, 'bdv_notif_v2_dynamic');
    });
  });

  group('BdvNotifProfile — Tarjeta Internacional USD (expense USD)', () {
    test('Fixture: Pago con tarjeta internacional por \$.300,00', () async {
      const title = 'Pago en linea con tu Tarjeta Internacional';
      const body =
          'Operacion en linea con tu Tarjeta Internacional #4325 por \$.300,00 el 15-04-26 a las 14:04. Inf. 0500-6425283';
      final event = makeEvent('$title\n$body');

      final proposal = await profile.tryParse(event, accountId: 'acc-bdv');

      expect(proposal, isNotNull);
      expect(proposal!.amount, 300.00);
      expect(proposal.currencyId, 'USD');
      expect(proposal.type, TransactionType.expense);
      // Dynamic parser picks up #4325 (card fragment) as a ref
      expect(proposal.bankRef, '#4325');
      expect(proposal.counterpartyName, isNull);
      // bankRef + type detected → 0.95
      expect(proposal.confidence, 0.95);
      expect(proposal.channel, CaptureChannel.notification);
      expect(proposal.date, DateTime(2026, 4, 15, 14, 4));
      expect(proposal.parsedBySender, 'bdv_notif_v2_dynamic');
    });
  });

  group('BdvNotifProfile — Negative tests (should return null)', () {
    test('Unknown title with no amount returns null', () async {
      final event = makeEvent(
        'Promoción BDV\nTenemos una oferta para ti...',
      );
      expect(await profile.tryParse(event, accountId: 'acc-bdv'), isNull);
    });

    test('Known title but body has no amount returns null', () async {
      final event = makeEvent(
        'Transferencia BDV recibida\nMensaje corrupto',
      );
      expect(await profile.tryParse(event, accountId: 'acc-bdv'), isNull);
    });

    test('Empty string returns null', () async {
      final event = makeEvent('');
      expect(await profile.tryParse(event, accountId: 'acc-bdv'), isNull);
    });

    test('Only title, no newline returns null', () async {
      final event = makeEvent('Transferencia BDV recibida');
      expect(await profile.tryParse(event, accountId: 'acc-bdv'), isNull);
    });

    test('Title with empty body returns null', () async {
      final event = makeEvent('Transferencia BDV recibida\n');
      expect(await profile.tryParse(event, accountId: 'acc-bdv'), isNull);
    });
  });

  group('BdvNotifProfile — Dynamic parser: unknown titles with amounts', () {
    test('New notification format with amount is still parsed', () async {
      // A hypothetical new BDV notification format we haven't seen before
      final event = makeEvent(
        'Nuevo tipo de operación\n'
        'Se realizó un débito por Bs. 1.500,00 en tu cuenta.',
      );

      final proposal = await profile.tryParse(event, accountId: 'acc-bdv');

      // Should NOT be null — amount was found
      expect(proposal, isNotNull);
      expect(proposal!.amount, 1500.00);
      expect(proposal.currencyId, 'VES');
      // "realizó" matches expense keyword "realiz" prefix — but actually
      // the regex is "realizado|realizada|realizaste", not "realizó"
      // No keywords match → default to expense
      expect(proposal.type, TransactionType.expense);
      // No ref, no counterparty
      expect(proposal.bankRef, isNull);
      expect(proposal.counterpartyName, isNull);
      // Only amount → 0.70
      expect(proposal.confidence, 0.70);
    });

    test('Unknown title with income keyword and amount is parsed as income',
        () async {
      final event = makeEvent(
        'Alerta BDV\n'
        'Has recibido un abono por Bs. 200,00.',
      );

      final proposal = await profile.tryParse(event, accountId: 'acc-bdv');

      expect(proposal, isNotNull);
      expect(proposal!.amount, 200.00);
      expect(proposal.currencyId, 'VES');
      // "recibido" matches income keyword
      expect(proposal.type, TransactionType.income);
      // No ref → confidence 0.85
      expect(proposal.confidence, 0.85);
    });
  });

  group('BdvNotifProfile — accountId passthrough', () {
    test('null accountId is preserved in proposal', () async {
      const title = 'Transferencia BDV recibida';
      const body =
          '"Recibiste una transferencia BDV de JOINER ALEXANDER ROVARIO SAAVEDRA por Bs.277.000,00 bajo el número de operación 059135723999"';
      final event = makeEvent('$title\n$body');

      final proposal = await profile.tryParse(event, accountId: null);
      expect(proposal, isNotNull);
      expect(proposal!.accountId, isNull);
    });
  });
}
