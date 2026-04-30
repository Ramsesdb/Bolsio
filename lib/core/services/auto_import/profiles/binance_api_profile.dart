import 'dart:convert';
import 'dart:developer' as developer;

import 'package:kilatex/core/models/auto_import/capture_channel.dart';
import 'package:kilatex/core/models/auto_import/raw_capture_event.dart';
import 'package:kilatex/core/models/auto_import/transaction_proposal.dart';
import 'package:kilatex/core/models/transaction/transaction_type.enum.dart';
import 'package:kilatex/core/services/auto_import/profiles/bank_profile.dart';

/// Bank profile for Binance API-sourced transactions.
///
/// Parses JSON payloads from the various Binance endpoints (C2C P2P, fiat
/// orders, fiat payments, Pay, capital deposits, capital withdrawals) into
/// [TransactionProposal]s.
class BinanceApiProfile implements BankProfile {
  @override
  String get profileId => 'binance_api';

  @override
  String get bankName => 'Binance';

  @override
  String get accountMatchName => 'Binance';

  @override
  CaptureChannel get channel => CaptureChannel.api;

  @override
  List<String> get knownSenders => const [
        'binance:c2c_p2p',
        'binance:fiat_order_deposit',
        'binance:fiat_order_withdraw',
        'binance:fiat_payment',
        'binance:pay',
        'binance:deposit',
        'binance:withdraw',
      ];

  @override
  int get profileVersion => 1;

  @override
  Future<ParseResult> tryParseWithDetails(
    RawCaptureEvent event, {
    required String? accountId,
  }) async {
    final proposal = await tryParse(event, accountId: accountId);
    if (proposal != null) return ParseResult.parsed(proposal);
    return ParseResult.failed(
      'Payload de Binance no reconocido o estado no completado',
    );
  }

  @override
  Future<TransactionProposal?> tryParse(
    RawCaptureEvent event, {
    required String? accountId,
  }) async {
    try {
      final item = jsonDecode(event.rawText) as Map<String, dynamic>;

      switch (event.sender) {
        case 'binance:c2c_p2p':
          return _parseC2cP2p(item, event, accountId);
        case 'binance:fiat_order_deposit':
          return _parseFiatOrder(item, event, accountId, isDeposit: true);
        case 'binance:fiat_order_withdraw':
          return _parseFiatOrder(item, event, accountId, isDeposit: false);
        case 'binance:fiat_payment':
          return _parseFiatPayment(item, event, accountId);
        case 'binance:pay':
          return _parsePay(item, event, accountId);
        case 'binance:deposit':
          return _parseDeposit(item, event, accountId);
        case 'binance:withdraw':
          return _parseWithdraw(item, event, accountId);
        default:
          developer.log(
            'Unknown Binance sender: ${event.sender}',
            name: 'BinanceApiProfile',
          );
          return null;
      }
    } catch (e) {
      developer.log(
        'Failed to parse Binance event (${event.sender}): $e',
        name: 'BinanceApiProfile',
      );
      return null;
    }
  }

  // ─── C2C P2P ─────────────────────────────────────────────────

  TransactionProposal? _parseC2cP2p(
    Map<String, dynamic> item,
    RawCaptureEvent event,
    String? accountId,
  ) {
    final status = item['orderStatus'] as String?;
    if (status != 'COMPLETED') return null;

    final tradeType = item['tradeType'] as String?;
    if (tradeType == null) return null;

    // BUY = crypto enters Binance account = income
    // SELL = crypto leaves Binance account = expense
    final type = tradeType == 'BUY'
        ? TransactionType.income
        : TransactionType.expense;

    final amount = double.tryParse('${item['amount']}') ?? 0.0;
    final createTime = item['createTime'] as int?;
    final date = createTime != null
        ? DateTime.fromMillisecondsSinceEpoch(createTime)
        : event.receivedAt;

    return TransactionProposal.newProposal(
      accountId: accountId,
      amount: amount,
      currencyId: _resolveCurrencyId(item['asset'] as String? ?? 'USDT'),
      date: date,
      type: type,
      counterpartyName: item['counterPartNickName'] as String?,
      bankRef: item['orderNumber'] as String?,
      rawText: event.rawText,
      channel: CaptureChannel.api,
      sender: event.sender,
      confidence: 0.95,
      parsedBySender: 'binance_api_v1_c2c_p2p',
    );
  }

  // ─── Fiat Order (deposit/withdraw) ────────────────────────────

  TransactionProposal? _parseFiatOrder(
    Map<String, dynamic> item,
    RawCaptureEvent event,
    String? accountId, {
    required bool isDeposit,
  }) {
    final status = (item['status'] as String? ?? '').toLowerCase();
    final isCompleted = status == 'successful' ||
        status == 'completed' ||
        status == 'success';
    if (!isCompleted) return null;

    final fiatCurrency = item['fiatCurrency'] as String? ?? 'USD';
    final amount = double.tryParse('${item['amount']}') ??
        double.tryParse('${item['indicatedAmount']}') ??
        double.tryParse('${item['totalPrice']}') ??
        0.0;
    if (amount <= 0) return null;
    final createTime = item['createTime'] as int?;
    final date = createTime != null
        ? DateTime.fromMillisecondsSinceEpoch(createTime)
        : event.receivedAt;

    return TransactionProposal.newProposal(
      accountId: accountId,
      amount: amount,
      currencyId: fiatCurrency == 'USD' ? 'USD' : fiatCurrency,
      date: date,
      type: isDeposit ? TransactionType.income : TransactionType.expense,
      counterpartyName: (item['method'] as String?) ?? (item['sourceType'] as String?),
      bankRef: item['orderNo'] as String?,
      rawText: event.rawText,
      channel: CaptureChannel.api,
      sender: event.sender,
      confidence: 0.95,
      parsedBySender: 'binance_api_v1_fiat_order',
    );
  }

  // ─── Fiat Payment (card → crypto) ────────────────────────────

  TransactionProposal? _parseFiatPayment(
    Map<String, dynamic> item,
    RawCaptureEvent event,
    String? accountId,
  ) {
    final status = item['status'] as String?;
    if (status != 'Completed') return null;

    final cryptoCurrency = item['cryptoCurrency'] as String? ?? 'USDT';
    final obtainAmount = double.tryParse('${item['obtainAmount']}') ?? 0.0;
    final createTime = item['createTime'] as int?;
    final date = createTime != null
        ? DateTime.fromMillisecondsSinceEpoch(createTime)
        : event.receivedAt;

    return TransactionProposal.newProposal(
      accountId: accountId,
      amount: obtainAmount,
      currencyId: _resolveCurrencyId(cryptoCurrency),
      date: date,
      type: TransactionType.income,
      counterpartyName: 'Binance Card Purchase',
      bankRef: item['orderNo'] as String?,
      rawText: event.rawText,
      channel: CaptureChannel.api,
      sender: event.sender,
      confidence: 0.90,
      parsedBySender: 'binance_api_v1_fiat_payment',
    );
  }

  // ─── Binance Pay ──────────────────────────────────────────────

  TransactionProposal? _parsePay(
    Map<String, dynamic> item,
    RawCaptureEvent event,
    String? accountId,
  ) {
    // Binance Pay uses 'status' or 'orderStatus' depending on endpoint version.
    final status =
        (item['status'] as String? ?? item['orderStatus'] as String? ?? '')
            .toUpperCase();
    if (status != 'SUCCESS' && status != 'COMPLETED') return null;

    final currency = item['currency'] as String? ?? 'USDT';
    final amount = double.tryParse('${item['amount']}') ?? 0.0;
    final createTime = item['createTime'] as int?;
    final date = createTime != null
        ? DateTime.fromMillisecondsSinceEpoch(createTime)
        : event.receivedAt;

    // Determine direction: PAY/PAYOUT → expense, RECEIVE/C2C → income
    final transactionType =
        (item['transactionType'] as String? ?? '').toUpperCase();
    final type = (transactionType == 'PAY' || transactionType == 'PAYOUT')
        ? TransactionType.expense
        : TransactionType.income;

    // Counterparty info
    String? counterpartyName;
    final counterparty = item['counterparty'];
    if (counterparty is Map<String, dynamic>) {
      counterpartyName = counterparty['name'] as String?;
    }

    return TransactionProposal.newProposal(
      accountId: accountId,
      amount: amount,
      currencyId: _resolveCurrencyId(currency),
      date: date,
      type: type,
      counterpartyName: counterpartyName,
      bankRef: item['transactionId'] as String?,
      rawText: event.rawText,
      channel: CaptureChannel.api,
      sender: event.sender,
      confidence: 0.90,
      parsedBySender: 'binance_api_v1_pay',
    );
  }

  // ─── Capital Deposit ──────────────────────────────────────────

  TransactionProposal? _parseDeposit(
    Map<String, dynamic> item,
    RawCaptureEvent event,
    String? accountId,
  ) {
    final status = item['status'] as int?;
    if (status != 1) return null; // 1 = confirmed

    final coin = item['coin'] as String? ?? '';
    final amount = double.tryParse('${item['amount']}') ?? 0.0;
    final insertTime = item['insertTime'] as int?;
    final date = insertTime != null
        ? DateTime.fromMillisecondsSinceEpoch(insertTime)
        : event.receivedAt;

    final isStablecoin = _isStablecoin(coin);

    return TransactionProposal.newProposal(
      accountId: accountId,
      amount: amount,
      currencyId: _resolveCurrencyId(coin),
      date: date,
      type: TransactionType.income,
      counterpartyName: item['address'] as String?,
      bankRef: (item['txId'] as String?) ?? item['id'] as String?,
      rawText: event.rawText,
      channel: CaptureChannel.api,
      sender: event.sender,
      confidence: isStablecoin ? 0.90 : 0.60,
      parsedBySender: 'binance_api_v1_deposit',
    );
  }

  // ─── Capital Withdrawal ───────────────────────────────────────

  TransactionProposal? _parseWithdraw(
    Map<String, dynamic> item,
    RawCaptureEvent event,
    String? accountId,
  ) {
    // Withdrawal status: 6 = completed (Binance uses int statuses for withdrawals)
    final status = item['status'] as int?;
    if (status != 6) return null;

    final coin = item['coin'] as String? ?? '';
    final amount = double.tryParse('${item['amount']}') ?? 0.0;
    final applyTime = item['applyTime'] as String?;
    DateTime date;
    if (applyTime != null) {
      date = DateTime.tryParse(applyTime) ?? event.receivedAt;
    } else {
      date = event.receivedAt;
    }

    final isStablecoin = _isStablecoin(coin);

    return TransactionProposal.newProposal(
      accountId: accountId,
      amount: amount,
      currencyId: _resolveCurrencyId(coin),
      date: date,
      type: TransactionType.expense,
      counterpartyName: item['address'] as String?,
      bankRef: (item['id'] as String?) ?? item['txId'] as String?,
      rawText: event.rawText,
      channel: CaptureChannel.api,
      sender: event.sender,
      confidence: isStablecoin ? 0.90 : 0.60,
      parsedBySender: 'binance_api_v1_withdraw',
    );
  }

  // ─── Helpers ──────────────────────────────────────────────────

  static const _stablecoins = {'USDT', 'USDC', 'BUSD', 'FDUSD'};

  bool _isStablecoin(String coin) =>
      _stablecoins.contains(coin.toUpperCase());

  /// Map stablecoins to 'USD'; leave other currencies as-is.
  String _resolveCurrencyId(String coin) {
    if (_isStablecoin(coin)) return 'USD';
    if (coin.toUpperCase() == 'VES') return 'VES';
    return coin.toUpperCase();
  }
}
