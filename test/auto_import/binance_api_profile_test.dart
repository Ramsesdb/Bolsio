import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:wallex/core/models/auto_import/capture_channel.dart';
import 'package:wallex/core/models/auto_import/raw_capture_event.dart';
import 'package:wallex/core/models/transaction/transaction_type.enum.dart';
import 'package:wallex/core/services/auto_import/profiles/binance_api_profile.dart';

void main() {
  late BinanceApiProfile profile;

  setUp(() {
    profile = BinanceApiProfile();
  });

  RawCaptureEvent makeEvent(Map<String, dynamic> json, String sender) {
    return RawCaptureEvent(
      rawText: jsonEncode(json),
      sender: sender,
      receivedAt: DateTime(2025, 4, 1),
      channel: CaptureChannel.api,
    );
  }

  group('BinanceApiProfile metadata', () {
    test('bankName is Binance', () {
      expect(profile.bankName, 'Binance');
    });

    test('accountMatchName is Binance', () {
      expect(profile.accountMatchName, 'Binance');
    });

    test('channel is api', () {
      expect(profile.channel, CaptureChannel.api);
    });

    test('knownSenders contains all expected senders', () {
      expect(profile.knownSenders, contains('binance:c2c_p2p'));
      expect(profile.knownSenders, contains('binance:fiat_order_deposit'));
      expect(profile.knownSenders, contains('binance:fiat_order_withdraw'));
      expect(profile.knownSenders, contains('binance:fiat_payment'));
      expect(profile.knownSenders, contains('binance:pay'));
      expect(profile.knownSenders, contains('binance:deposit'));
      expect(profile.knownSenders, contains('binance:withdraw'));
    });

    test('profileVersion is 1', () {
      expect(profile.profileVersion, 1);
    });
  });

  group('C2C P2P', () {
    test('COMPLETED SELL → expense', () async {
      final json = {
        'orderNumber': '20250401001234567890',
        'tradeType': 'SELL',
        'asset': 'USDT',
        'fiat': 'VES',
        'amount': '150.00',
        'totalPrice': '5625000.00',
        'unitPrice': '37500.00',
        'counterPartNickName': 'Carlos_P2P',
        'createTime': 1711929600000,
        'orderStatus': 'COMPLETED',
      };

      final event = makeEvent(json, 'binance:c2c_p2p');
      final proposal = await profile.tryParse(event, accountId: 'acc-binance');

      expect(proposal, isNotNull);
      expect(proposal!.amount, 150.0);
      expect(proposal.currencyId, 'USD');
      expect(proposal.type, TransactionType.expense);
      expect(proposal.counterpartyName, 'Carlos_P2P');
      expect(proposal.bankRef, '20250401001234567890');
      expect(proposal.confidence, 0.95);
      expect(proposal.channel, CaptureChannel.api);
      expect(proposal.accountId, 'acc-binance');
    });

    test('COMPLETED BUY → income', () async {
      final json = {
        'orderNumber': '20250401009876543210',
        'tradeType': 'BUY',
        'asset': 'USDT',
        'fiat': 'VES',
        'amount': '200.00',
        'totalPrice': '7500000.00',
        'unitPrice': '37500.00',
        'counterPartNickName': 'Maria_VES',
        'createTime': 1711933200000,
        'orderStatus': 'COMPLETED',
      };

      final event = makeEvent(json, 'binance:c2c_p2p');
      final proposal = await profile.tryParse(event, accountId: 'acc-binance');

      expect(proposal, isNotNull);
      expect(proposal!.amount, 200.0);
      expect(proposal.currencyId, 'USD');
      expect(proposal.type, TransactionType.income);
      expect(proposal.counterpartyName, 'Maria_VES');
      expect(proposal.bankRef, '20250401009876543210');
      expect(proposal.confidence, 0.95);
    });

    test('PENDING status → null (ignored)', () async {
      final json = {
        'orderNumber': '20250401005555555555',
        'tradeType': 'BUY',
        'asset': 'USDT',
        'fiat': 'VES',
        'amount': '50.00',
        'totalPrice': '1875000.00',
        'unitPrice': '37500.00',
        'counterPartNickName': 'Pending_User',
        'createTime': 1711936800000,
        'orderStatus': 'PENDING',
      };

      final event = makeEvent(json, 'binance:c2c_p2p');
      final proposal = await profile.tryParse(event, accountId: 'acc-binance');

      expect(proposal, isNull);
    });

    test('CANCELLED status → null (ignored)', () async {
      final json = {
        'orderNumber': '20250401006666666666',
        'tradeType': 'SELL',
        'asset': 'USDT',
        'fiat': 'VES',
        'amount': '100.00',
        'totalPrice': '3750000.00',
        'unitPrice': '37500.00',
        'counterPartNickName': 'Cancel_User',
        'createTime': 1711940400000,
        'orderStatus': 'CANCELLED',
      };

      final event = makeEvent(json, 'binance:c2c_p2p');
      final proposal = await profile.tryParse(event, accountId: 'acc-binance');

      expect(proposal, isNull);
    });
  });

  group('Fiat Order', () {
    test('Successful deposit → income', () async {
      final json = {
        'orderNo': 'FO20250402001122334455',
        'fiatCurrency': 'USD',
        'indicatedAmount': '500.00',
        'amount': '500.00',
        'totalFee': '0.00',
        'method': 'BPay VISA Card',
        'status': 'Successful',
        'createTime': 1712001600000,
        'updateTime': 1712005200000,
      };

      final event = makeEvent(json, 'binance:fiat_order_deposit');
      final proposal = await profile.tryParse(event, accountId: 'acc-binance');

      expect(proposal, isNotNull);
      expect(proposal!.amount, 500.0);
      expect(proposal.currencyId, 'USD');
      expect(proposal.type, TransactionType.income);
      expect(proposal.counterpartyName, 'BPay VISA Card');
      expect(proposal.bankRef, 'FO20250402001122334455');
      expect(proposal.confidence, 0.95);
    });

    test('Successful withdrawal → expense', () async {
      final json = {
        'orderNo': 'FO20250402002233445566',
        'fiatCurrency': 'USD',
        'indicatedAmount': '200.00',
        'amount': '200.00',
        'totalFee': '1.00',
        'method': 'Bank Transfer',
        'status': 'Successful',
        'createTime': 1712001600000,
        'updateTime': 1712005200000,
      };

      final event = makeEvent(json, 'binance:fiat_order_withdraw');
      final proposal = await profile.tryParse(event, accountId: 'acc-binance');

      expect(proposal, isNotNull);
      expect(proposal!.type, TransactionType.expense);
    });

    test('Failed status → null (ignored)', () async {
      final json = {
        'orderNo': 'FO20250402009999999999',
        'fiatCurrency': 'USD',
        'indicatedAmount': '100.00',
        'amount': '100.00',
        'totalFee': '0.00',
        'method': 'Bank Transfer',
        'status': 'Failed',
        'createTime': 1712008800000,
        'updateTime': 1712012400000,
      };

      final event = makeEvent(json, 'binance:fiat_order_deposit');
      final proposal = await profile.tryParse(event, accountId: 'acc-binance');

      expect(proposal, isNull);
    });
  });

  group('Fiat Payment', () {
    test('Completed card purchase → income (crypto enters wallet)', () async {
      final json = {
        'orderNo': 'FP20250403001234',
        'sourceAmount': '100.00',
        'fiatCurrency': 'USD',
        'obtainAmount': '99.50',
        'cryptoCurrency': 'USDT',
        'totalFee': '0.50',
        'status': 'Completed',
        'createTime': 1712088000000,
      };

      final event = makeEvent(json, 'binance:fiat_payment');
      final proposal = await profile.tryParse(event, accountId: 'acc-binance');

      expect(proposal, isNotNull);
      expect(proposal!.amount, 99.5);
      expect(proposal.currencyId, 'USD');
      expect(proposal.type, TransactionType.income);
      expect(proposal.counterpartyName, 'Binance Card Purchase');
      expect(proposal.bankRef, 'FP20250403001234');
      expect(proposal.confidence, 0.90);
    });

    test('Non-stablecoin crypto purchase uses coin as currencyId', () async {
      final json = {
        'orderNo': 'FP20250403005678',
        'sourceAmount': '100.00',
        'fiatCurrency': 'USD',
        'obtainAmount': '0.0025',
        'cryptoCurrency': 'BTC',
        'totalFee': '0.50',
        'status': 'Completed',
        'createTime': 1712088000000,
      };

      final event = makeEvent(json, 'binance:fiat_payment');
      final proposal = await profile.tryParse(event, accountId: 'acc-binance');

      expect(proposal, isNotNull);
      expect(proposal!.currencyId, 'BTC');
    });
  });

  group('Pay Transaction', () {
    test('SUCCESS PAY → expense', () async {
      final json = {
        'orderType': 'PAY',
        'transactionId': 'PAY20250404001122',
        'amount': '25.00',
        'currency': 'USDT',
        'transactionType': 'PAY',
        'status': 'SUCCESS',
        'counterparty': {
          'name': 'Coffee Shop VE',
          'accountId': '123456',
          'binanceId': 'BID789',
        },
        'createTime': 1712174400000,
      };

      final event = makeEvent(json, 'binance:pay');
      final proposal = await profile.tryParse(event, accountId: 'acc-binance');

      expect(proposal, isNotNull);
      expect(proposal!.amount, 25.0);
      expect(proposal.currencyId, 'USD');
      expect(proposal.type, TransactionType.expense);
      expect(proposal.counterpartyName, 'Coffee Shop VE');
      expect(proposal.bankRef, 'PAY20250404001122');
      expect(proposal.confidence, 0.90);
    });

    test('SUCCESS RECEIVE → income', () async {
      final json = {
        'orderType': 'C2C',
        'transactionId': 'PAY20250404003344',
        'amount': '10.00',
        'currency': 'USDT',
        'transactionType': 'RECEIVE',
        'status': 'SUCCESS',
        'counterparty': {
          'name': 'Friend_Send',
          'accountId': '654321',
          'binanceId': 'BID456',
        },
        'createTime': 1712178000000,
      };

      final event = makeEvent(json, 'binance:pay');
      final proposal = await profile.tryParse(event, accountId: 'acc-binance');

      expect(proposal, isNotNull);
      expect(proposal!.type, TransactionType.income);
      expect(proposal.counterpartyName, 'Friend_Send');
    });

    test('PENDING status → null (ignored)', () async {
      final json = {
        'orderType': 'PAY',
        'transactionId': 'PAY20250404009999',
        'amount': '5.00',
        'currency': 'USDT',
        'transactionType': 'PAY',
        'status': 'PENDING',
        'counterparty': {'name': 'Someone'},
        'createTime': 1712181600000,
      };

      final event = makeEvent(json, 'binance:pay');
      final proposal = await profile.tryParse(event, accountId: 'acc-binance');

      expect(proposal, isNull);
    });
  });

  group('Capital Deposit', () {
    test('status=1, USDT → income, currencyId=USD, confidence=0.90', () async {
      final json = {
        'id': 'dep_001',
        'amount': '300.00',
        'coin': 'USDT',
        'network': 'TRX',
        'status': 1,
        'address': 'TXyz1234567890abcdef1234567890abcd',
        'txId': '0xabc123def456789',
        'insertTime': 1712260800000,
      };

      final event = makeEvent(json, 'binance:deposit');
      final proposal = await profile.tryParse(event, accountId: 'acc-binance');

      expect(proposal, isNotNull);
      expect(proposal!.amount, 300.0);
      expect(proposal.currencyId, 'USD');
      expect(proposal.type, TransactionType.income);
      expect(proposal.counterpartyName,
          'TXyz1234567890abcdef1234567890abcd');
      expect(proposal.bankRef, '0xabc123def456789');
      expect(proposal.confidence, 0.90);
    });

    test('status=1, BTC → income, currencyId=BTC, confidence=0.60', () async {
      final json = {
        'id': 'dep_002',
        'amount': '0.01500000',
        'coin': 'BTC',
        'network': 'BTC',
        'status': 1,
        'address': 'bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh',
        'txId': '0xbtc_hash_example',
        'insertTime': 1712264400000,
      };

      final event = makeEvent(json, 'binance:deposit');
      final proposal = await profile.tryParse(event, accountId: 'acc-binance');

      expect(proposal, isNotNull);
      expect(proposal!.amount, 0.015);
      expect(proposal.currencyId, 'BTC');
      expect(proposal.type, TransactionType.income);
      expect(proposal.confidence, 0.60);
    });

    test('status=0 (pending) → null (ignored)', () async {
      final json = {
        'id': 'dep_003',
        'amount': '100.00',
        'coin': 'USDT',
        'network': 'TRX',
        'status': 0,
        'address': 'TPending1234567890',
        'txId': '0xpending_hash',
        'insertTime': 1712268000000,
      };

      final event = makeEvent(json, 'binance:deposit');
      final proposal = await profile.tryParse(event, accountId: 'acc-binance');

      expect(proposal, isNull);
    });
  });

  group('Capital Withdrawal', () {
    test('status=6, USDT → expense, currencyId=USD, confidence=0.90', () async {
      final json = {
        'id': 'wdr_001',
        'amount': '50.00',
        'coin': 'USDT',
        'network': 'TRX',
        'status': 6,
        'address': 'TDestination1234567890abcdef12345',
        'txId': '0xwithdraw_hash_123',
        'applyTime': '2025-04-05 12:00:00',
      };

      final event = makeEvent(json, 'binance:withdraw');
      final proposal = await profile.tryParse(event, accountId: 'acc-binance');

      expect(proposal, isNotNull);
      expect(proposal!.amount, 50.0);
      expect(proposal.currencyId, 'USD');
      expect(proposal.type, TransactionType.expense);
      expect(proposal.counterpartyName,
          'TDestination1234567890abcdef12345');
      expect(proposal.bankRef, 'wdr_001');
      expect(proposal.confidence, 0.90);
    });

    test('status=2 (processing) → null (ignored)', () async {
      final json = {
        'id': 'wdr_002',
        'amount': '25.00',
        'coin': 'USDT',
        'network': 'TRX',
        'status': 2,
        'address': 'TProcessing123',
        'txId': '0xprocessing_hash',
        'applyTime': '2025-04-05 13:00:00',
      };

      final event = makeEvent(json, 'binance:withdraw');
      final proposal = await profile.tryParse(event, accountId: 'acc-binance');

      expect(proposal, isNull);
    });
  });

  group('Edge cases', () {
    test('unknown sender → null', () async {
      final json = {'some': 'data'};
      final event = makeEvent(json, 'binance:unknown_endpoint');
      final proposal = await profile.tryParse(event, accountId: 'acc-binance');

      expect(proposal, isNull);
    });

    test('malformed JSON rawText → null (does not throw)', () async {
      final event = RawCaptureEvent(
        rawText: 'not valid json {{{',
        sender: 'binance:c2c_p2p',
        receivedAt: DateTime(2025, 4, 1),
        channel: CaptureChannel.api,
      );

      final proposal = await profile.tryParse(event, accountId: 'acc-binance');
      expect(proposal, isNull);
    });

    test('FDUSD stablecoin → currencyId=USD', () async {
      final json = {
        'id': 'dep_fdusd',
        'amount': '100.00',
        'coin': 'FDUSD',
        'network': 'BSC',
        'status': 1,
        'address': 'TFDUSD_address',
        'txId': '0xfdusd_hash',
        'insertTime': 1712260800000,
      };

      final event = makeEvent(json, 'binance:deposit');
      final proposal = await profile.tryParse(event, accountId: 'acc-binance');

      expect(proposal, isNotNull);
      expect(proposal!.currencyId, 'USD');
    });

    test('USDC stablecoin → currencyId=USD', () async {
      final json = {
        'id': 'dep_usdc',
        'amount': '250.00',
        'coin': 'USDC',
        'network': 'ETH',
        'status': 1,
        'address': 'TUSDC_address',
        'txId': '0xusdc_hash',
        'insertTime': 1712260800000,
      };

      final event = makeEvent(json, 'binance:deposit');
      final proposal = await profile.tryParse(event, accountId: 'acc-binance');

      expect(proposal, isNotNull);
      expect(proposal!.currencyId, 'USD');
    });
  });
}
