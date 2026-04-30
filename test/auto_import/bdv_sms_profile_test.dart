import 'package:flutter_test/flutter_test.dart';
import 'package:bolsio/core/models/auto_import/capture_channel.dart';
import 'package:bolsio/core/models/auto_import/raw_capture_event.dart';
import 'package:bolsio/core/models/transaction/transaction_type.enum.dart';
import 'package:bolsio/core/services/auto_import/profiles/bdv_sms_profile.dart';

void main() {
  late BdvSmsProfile profile;

  setUp(() {
    profile = BdvSmsProfile();
  });

  RawCaptureEvent makeEvent(String rawText, {String sender = '2661'}) {
    return RawCaptureEvent(
      rawText: rawText,
      sender: sender,
      receivedAt: DateTime.now(),
      channel: CaptureChannel.sms,
    );
  }

  group('BdvSmsProfile metadata', () {
    test('bankName is Banco de Venezuela', () {
      expect(profile.bankName, 'Banco de Venezuela');
    });

    test('accountMatchName is Banco de Venezuela', () {
      expect(profile.accountMatchName, 'Banco de Venezuela');
    });

    test('channel is sms', () {
      expect(profile.channel, CaptureChannel.sms);
    });

    test('knownSenders contains 2661 and 2662', () {
      expect(profile.knownSenders, contains('2661'));
      expect(profile.knownSenders, contains('2662'));
    });

    test('profileVersion is 1', () {
      expect(profile.profileVersion, 1);
    });
  });

  group('BdvSmsProfile — Pagomovil recibido (positive tests)', () {
    test('Fixture 1: Bs.12.000,00 sin espacio tras Bs.', () async {
      final event = makeEvent(
        'Recibiste un PagomovilBDV por Bs.12.000,00 del 0412-7635070 Ref: 108834202054 en fecha: 29-03-26 hora: 18:01.',
      );

      final proposal = await profile.tryParse(event, accountId: 'acc-bdv');

      expect(proposal, isNotNull);
      expect(proposal!.amount, 12000.0);
      expect(proposal.currencyId, 'VES');
      expect(proposal.type, TransactionType.income);
      expect(proposal.counterpartyName, '0412-7635070');
      expect(proposal.bankRef, '108834202054');
      expect(proposal.date, DateTime(2026, 3, 29, 18, 1));
      expect(proposal.confidence, greaterThanOrEqualTo(0.9));
      expect(proposal.channel, CaptureChannel.sms);
      expect(proposal.accountId, 'acc-bdv');
      expect(
        proposal.parsedBySender,
        'bdv_sms_v1_pagomovil_recibido',
      );
    });

    test('Fixture 2: Bs. 210,00 con espacio tras Bs., fecha 2023', () async {
      final event = makeEvent(
        'Recibiste un PagomovilBDV por Bs. 210,00 del 0412-6638500 Ref: 000390572967 en fecha: 30-10-23 hora: 12:35',
      );

      final proposal = await profile.tryParse(event, accountId: 'acc-bdv');

      expect(proposal, isNotNull);
      expect(proposal!.amount, 210.0);
      expect(proposal.currencyId, 'VES');
      expect(proposal.type, TransactionType.income);
      expect(proposal.counterpartyName, '0412-6638500');
      expect(proposal.bankRef, '000390572967');
      expect(proposal.date, DateTime(2023, 10, 30, 12, 35));
      expect(proposal.confidence, greaterThanOrEqualTo(0.9));
    });

    test('Fixture 3: Bs. 900,00 con espacio, fecha 2025', () async {
      final event = makeEvent(
        'Recibiste un PagomovilBDV por Bs. 900,00 del 0412-7635070 Ref: 002103869591 en fecha: 25-01-25 hora: 21:26',
      );

      final proposal = await profile.tryParse(event, accountId: 'acc-bdv');

      expect(proposal, isNotNull);
      expect(proposal!.amount, 900.0);
      expect(proposal.currencyId, 'VES');
      expect(proposal.type, TransactionType.income);
      expect(proposal.counterpartyName, '0412-7635070');
      expect(proposal.bankRef, '002103869591');
      expect(proposal.date, DateTime(2025, 1, 25, 21, 26));
      expect(proposal.confidence, greaterThanOrEqualTo(0.9));
    });
  });

  group('BdvSmsProfile — 2662 positivos (Pagomovil recibido)', () {
    test('Fixture 2662-1: Bs. 30,00 con espacio, fecha con ":"', () async {
      final event = makeEvent(
        'Recibiste un PagomovilBDV por Bs. 30,00 del 0412-6638500 Ref: 000379526101 en fecha: 22-10-23 hora: 19:16',
        sender: '2662',
      );

      final proposal = await profile.tryParse(event, accountId: 'acc-bdv');

      expect(proposal, isNotNull);
      expect(proposal!.amount, 30.0);
      expect(proposal.currencyId, 'VES');
      expect(proposal.type, TransactionType.income);
      expect(proposal.counterpartyName, '0412-6638500');
      expect(proposal.bankRef, '000379526101');
      expect(proposal.date, DateTime(2023, 10, 22, 19, 16));
      expect(proposal.confidence, greaterThanOrEqualTo(0.9));
      expect(proposal.channel, CaptureChannel.sms);
    });

    test('Fixture 2662-2: Bs.10.620,00 sin espacio, fecha SIN ":"', () async {
      final event = makeEvent(
        'Recibiste un PagomovilBDV por Bs.10.620,00 del 0412-7635070 Ref: 108639858076 en fecha 27-03-26 hora: 21:31.',
        sender: '2662',
      );

      final proposal = await profile.tryParse(event, accountId: 'acc-bdv');

      expect(proposal, isNotNull);
      expect(proposal!.amount, 10620.0);
      expect(proposal.currencyId, 'VES');
      expect(proposal.type, TransactionType.income);
      expect(proposal.counterpartyName, '0412-7635070');
      expect(proposal.bankRef, '108639858076');
      expect(proposal.date, DateTime(2026, 3, 27, 21, 31));
      expect(proposal.confidence, greaterThanOrEqualTo(0.9));
      expect(proposal.channel, CaptureChannel.sms);
    });

    test('Fixture 2662-3: Bs.29.428,10 sin espacio, fecha SIN ":"', () async {
      final event = makeEvent(
        'Recibiste un PagomovilBDV por Bs.29.428,10 del 0424-6218586 Ref: 108639894484 en fecha 27-03-26 hora: 21:47.',
        sender: '2662',
      );

      final proposal = await profile.tryParse(event, accountId: 'acc-bdv');

      expect(proposal, isNotNull);
      expect(proposal!.amount, 29428.10);
      expect(proposal.currencyId, 'VES');
      expect(proposal.type, TransactionType.income);
      expect(proposal.counterpartyName, '0424-6218586');
      expect(proposal.bankRef, '108639894484');
      expect(proposal.date, DateTime(2026, 3, 27, 21, 47));
      expect(proposal.confidence, greaterThanOrEqualTo(0.9));
      expect(proposal.channel, CaptureChannel.sms);
    });

    test('Fixture 2662-4: Bs.5.953,10 sin espacio, fecha SIN ":"', () async {
      final event = makeEvent(
        'Recibiste un PagomovilBDV por Bs.5.953,10 del 0424-6125380 Ref: 000717467994 en fecha 27-03-26 hora: 22:25.',
        sender: '2662',
      );

      final proposal = await profile.tryParse(event, accountId: 'acc-bdv');

      expect(proposal, isNotNull);
      expect(proposal!.amount, 5953.10);
      expect(proposal.currencyId, 'VES');
      expect(proposal.type, TransactionType.income);
      expect(proposal.counterpartyName, '0424-6125380');
      expect(proposal.bankRef, '000717467994');
      expect(proposal.date, DateTime(2026, 3, 27, 22, 25));
      expect(proposal.confidence, greaterThanOrEqualTo(0.9));
      expect(proposal.channel, CaptureChannel.sms);
    });
  });

  group('BdvSmsProfile — Negative tests (should return null)', () {
    test('OTP clave de pago (1)', () async {
      final event = makeEvent(
        'BDV: La clave de pago para procesar tu operacion es 67928761',
      );

      expect(await profile.tryParse(event, accountId: 'acc-bdv'), isNull);
    });

    test('OTP clave de pago (2)', () async {
      final event = makeEvent(
        'BDV: La clave de pago para procesar tu operacion es 68010677',
      );

      expect(await profile.tryParse(event, accountId: 'acc-bdv'), isNull);
    });

    test('Codigo de vinculacion', () async {
      final event = makeEvent(
        'Tu codigo para proceder con la vinculacion de Ami Ven es 2256800 emr2y27v6wc',
      );

      expect(await profile.tryParse(event, accountId: 'acc-bdv'), isNull);
    });

    test('Random unrelated message', () async {
      final event = makeEvent('Mensaje random cualquiera');

      expect(await profile.tryParse(event, accountId: 'acc-bdv'), isNull);
    });
  });

  group('BdvSmsProfile — parseVenezuelanNumber', () {
    test('12.000,00 -> 12000.0', () {
      expect(BdvSmsProfile.parseVenezuelanNumber('12.000,00'), 12000.0);
    });

    test('210,00 -> 210.0', () {
      expect(BdvSmsProfile.parseVenezuelanNumber('210,00'), 210.0);
    });

    test('1.234.567,89 -> 1234567.89', () {
      expect(BdvSmsProfile.parseVenezuelanNumber('1.234.567,89'), 1234567.89);
    });
  });

  group('BdvSmsProfile — parseDate', () {
    test('29-03-26 18:01 -> DateTime(2026, 3, 29, 18, 1)', () {
      expect(BdvSmsProfile.parseDate('29-03-26', '18:01'),
          DateTime(2026, 3, 29, 18, 1));
    });

    test('30-10-23 12:35 -> DateTime(2023, 10, 30, 12, 35)', () {
      expect(BdvSmsProfile.parseDate('30-10-23', '12:35'),
          DateTime(2023, 10, 30, 12, 35));
    });
  });

  group('BdvSmsProfile — accountId passthrough', () {
    test('null accountId is preserved in proposal', () async {
      final event = makeEvent(
        'Recibiste un PagomovilBDV por Bs. 900,00 del 0412-7635070 Ref: 002103869591 en fecha: 25-01-25 hora: 21:26',
      );

      final proposal = await profile.tryParse(event, accountId: null);
      expect(proposal, isNotNull);
      expect(proposal!.accountId, isNull);
    });
  });
}
