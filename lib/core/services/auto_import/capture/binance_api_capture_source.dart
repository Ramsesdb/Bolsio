import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:drift/drift.dart';
import 'package:bolsio/core/database/app_db.dart';
import 'package:bolsio/core/models/auto_import/capture_channel.dart';
import 'package:bolsio/core/models/auto_import/raw_capture_event.dart';
import 'package:bolsio/core/services/auto_import/binance/binance_api_client.dart';
import 'package:bolsio/core/services/auto_import/binance/binance_api_exception.dart';
import 'package:bolsio/core/services/auto_import/binance/binance_credentials_store.dart';
import 'package:bolsio/core/services/auto_import/capture/capture_source.dart';

/// Capture source that polls Binance REST API endpoints for transaction history.
///
/// Implements [CaptureSource] by periodically fetching C2C, fiat, Pay, deposit,
/// and withdrawal history and emitting [RawCaptureEvent]s for each new item.
///
/// Cursors (last-sync timestamps) are persisted in [SharedPreferences].
class BinanceApiCaptureSource implements CaptureSource {
  static const String _binanceAccountName = 'Binance';
  static const Set<String> _stablecoins = {'USD', 'USDT', 'USDC', 'BUSD', 'FDUSD'};

  final BinanceApiClient _client;
  final BinanceCredentialsStore _credentialsStore;
  final SharedPreferences? _prefsOverride;

  Timer? _timer;
  final StreamController<RawCaptureEvent> _controller =
      StreamController<RawCaptureEvent>.broadcast();

  /// Polling interval (default 5 minutes).
  final Duration pollInterval;

  BinanceApiCaptureSource({
    BinanceApiClient? client,
    BinanceCredentialsStore? credentialsStore,
    SharedPreferences? prefsOverride,
    this.pollInterval = const Duration(minutes: 5),
  })  : _client = client ?? BinanceApiClient(),
        _credentialsStore =
            credentialsStore ?? BinanceCredentialsStore.instance,
        _prefsOverride = prefsOverride;

  @override
  CaptureChannel get channel => CaptureChannel.api;

  @override
  Stream<RawCaptureEvent> get events => _controller.stream;

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<bool> hasPermission() => _credentialsStore.hasCredentials();

  @override
  Future<bool> requestPermission() => hasPermission();

  @override
  Future<void> start() async {
    final hasCreds = await _credentialsStore.hasCredentials();
    if (!hasCreds) {
      debugPrint(
        'BinanceApiCaptureSource: No Binance credentials — skipping API polling',
      );
      return;
    }

    try {
      await _client.syncServerTime();
    } catch (e) {
      debugPrint(
        'BinanceApiCaptureSource: Failed to sync Binance server time: $e',
      );
    }

    // Schedule periodic polling FIRST so the deferred-first-poll guard
    // (`_timer == null` means "stopped") works correctly.
    _timer = Timer.periodic(pollInterval, (_) => poll());

    // Defer the initial poll so the home dashboard can render first.
    // The 7 sequential Binance HTTP calls would otherwise contend with
    // main-isolate DB access during startup, causing ~2s of jank.
    // If [stop] is called within this 5s window, _timer is nulled and
    // the deferred poll becomes a no-op.
    Future.delayed(const Duration(seconds: 5), () {
      if (_timer == null) return; // stopped before first poll
      poll();
    });
  }

  @override
  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
  }

  /// Run a single poll cycle across all Binance endpoints.
  ///
  /// Public so it can be tested directly.
  Future<void> poll() async {
    final prefs = _prefsOverride ?? await SharedPreferences.getInstance();

    await _pollEndpoint(
      prefs: prefs,
      cursorKey: 'binance_lastsync_c2c',
      sender: 'binance:c2c_p2p',
      fetch: (since) => _client.getC2cOrderHistory(since: since),
      getTimestamp: (item) => item['createTime'] as int?,
    );

    // Fiat orders: deposits
    await _pollEndpoint(
      prefs: prefs,
      cursorKey: 'binance_lastsync_fiat_orders_deposit',
      sender: 'binance:fiat_order_deposit',
      fetch: (since) =>
          _client.getFiatOrders(since: since, transactionType: '0'),
      getTimestamp: (item) => item['createTime'] as int?,
    );

    // Fiat orders: withdrawals
    await _pollEndpoint(
      prefs: prefs,
      cursorKey: 'binance_lastsync_fiat_orders_withdraw',
      sender: 'binance:fiat_order_withdraw',
      fetch: (since) =>
          _client.getFiatOrders(since: since, transactionType: '1'),
      getTimestamp: (item) => item['createTime'] as int?,
    );

    await _pollEndpoint(
      prefs: prefs,
      cursorKey: 'binance_lastsync_fiat_payments',
      sender: 'binance:fiat_payment',
      fetch: (since) => _client.getFiatPayments(since: since),
      getTimestamp: (item) => item['createTime'] as int?,
    );

    await _pollEndpoint(
      prefs: prefs,
      cursorKey: 'binance_lastsync_pay',
      sender: 'binance:pay',
      fetch: (since) => _client.getPayTransactions(since: since),
      getTimestamp: (item) => item['createTime'] as int?,
    );

    await _pollEndpoint(
      prefs: prefs,
      cursorKey: 'binance_lastsync_deposit',
      sender: 'binance:deposit',
      fetch: (since) => _client.getCapitalDeposits(since: since),
      getTimestamp: (item) => item['insertTime'] as int?,
    );

    await _pollEndpoint(
      prefs: prefs,
      cursorKey: 'binance_lastsync_withdraw',
      sender: 'binance:withdraw',
      fetch: (since) => _client.getCapitalWithdrawals(since: since),
      getTimestamp: (item) => item['insertTime'] as int? ?? item['applyTime'] as int?,
    );

    await _syncEstimatedBalanceToBinanceAccount();
  }

  Future<void> _syncEstimatedBalanceToBinanceAccount() async {
    try {
      final db = AppDB.instance;

      final accountRows = await db.customSelect(
        '''
        SELECT id, iniValue, currencyId
        FROM accounts
        WHERE LOWER(name) = LOWER(?)
        LIMIT 1
        ''',
        variables: [Variable.withString(_binanceAccountName)],
        readsFrom: {db.accounts},
      ).get();

      if (accountRows.isEmpty) {
        return;
      }

      final account = accountRows.first.data;
      final accountId = account['id'] as String;
      final currentIniValue = (account['iniValue'] as num?)?.toDouble() ?? 0.0;
      final currencyId = (account['currencyId'] as String?)?.toUpperCase() ?? '';

      // Keep this sync only for USD-like Binance account setups.
      if (currencyId != 'USD') {
        return;
      }

      final txCountRows = await db.customSelect(
        '''
        SELECT COUNT(1) AS txCount
        FROM transactions
        WHERE accountID = ? OR receivingAccountID = ?
        ''',
        variables: [
          Variable.withString(accountId),
          Variable.withString(accountId),
        ],
        readsFrom: {db.transactions},
      ).get();

      final txCount = (txCountRows.first.data['txCount'] as int?) ?? 0;

      // Avoid overriding balances for accounts already managed by local tx history.
      if (txCount > 0) {
        return;
      }

      final spot = await _client.getSpotAccount();

      List<Map<String, dynamic>> funding = const [];
      try {
        funding = await _client.getFundingAsset();
      } on BinanceApiException catch (e) {
        // Some API keys are valid for Spot but do not include Funding wallet scope.
        // Keep syncing using Spot balances instead of failing the whole sync.
        debugPrint(
          'BinanceApiCaptureSource: Funding wallet unavailable, using spot-only balance: $e',
        );
      }

      final spotBalances =
          List<Map<String, dynamic>>.from(spot['balances'] as List? ?? const []);

      final Map<String, double> amountByAsset = {};

      for (final item in spotBalances) {
        final asset = (item['asset'] as String? ?? '').toUpperCase();
        if (asset.isEmpty) continue;

        final free = double.tryParse('${item['free']}') ?? 0.0;
        final locked = double.tryParse('${item['locked']}') ?? 0.0;
        final total = free + locked;
        if (total <= 0) continue;

        amountByAsset.update(asset, (v) => v + total, ifAbsent: () => total);
      }

      for (final item in funding) {
        final asset = (item['asset'] as String? ?? '').toUpperCase();
        if (asset.isEmpty) continue;

        final free = double.tryParse('${item['free']}') ?? 0.0;
        final locked = double.tryParse('${item['locked']}') ?? 0.0;
        final freeze = double.tryParse('${item['freeze']}') ?? 0.0;
        final withdrawing = double.tryParse('${item['withdrawing']}') ?? 0.0;
        final total = free + locked + freeze + withdrawing;
        if (total <= 0) continue;

        amountByAsset.update(asset, (v) => v + total, ifAbsent: () => total);
      }

      final Map<String, double> priceCache = {};
      double estimatedUsdTotal = 0;

      for (final entry in amountByAsset.entries) {
        final asset = entry.key;
        final amount = entry.value;

        if (_stablecoins.contains(asset)) {
          estimatedUsdTotal += amount;
          continue;
        }

        final cached = priceCache[asset];
        final price = cached ?? await _client.getAssetPriceInUsdt(asset);
        if (price == null || price <= 0) {
          continue;
        }

        priceCache[asset] = price;
        estimatedUsdTotal += amount * price;
      }

      if ((estimatedUsdTotal - currentIniValue).abs() < 0.01) {
        return;
      }

      await db.customUpdate(
        'UPDATE accounts SET iniValue = ? WHERE id = ?',
        variables: [
          Variable.withReal(estimatedUsdTotal),
          Variable.withString(accountId),
        ],
        updates: {db.accounts},
      );

      db.markTablesUpdated([db.accounts]);

      debugPrint(
        'BinanceApiCaptureSource: Synced estimated Binance balance to account: '
        '${currentIniValue.toStringAsFixed(2)} -> ${estimatedUsdTotal.toStringAsFixed(2)} USD',
      );
    } on BinanceApiException catch (e) {
      debugPrint(
        'BinanceApiCaptureSource: Binance API error syncing estimated balance: $e',
      );
    } catch (e) {
      debugPrint(
        'BinanceApiCaptureSource: Unexpected error syncing estimated balance: $e',
      );
    }
  }

  Future<void> _pollEndpoint({
    required SharedPreferences prefs,
    required String cursorKey,
    required String sender,
    required Future<List<Map<String, dynamic>>> Function(DateTime? since) fetch,
    required int? Function(Map<String, dynamic> item) getTimestamp,
  }) async {
    try {
      final lastSyncMs = prefs.getInt(cursorKey);
      DateTime? since;
      if (lastSyncMs != null) {
        // Overlap by 5 minutes for safety
        since = DateTime.fromMillisecondsSinceEpoch(
          lastSyncMs - const Duration(minutes: 5).inMilliseconds,
        );
      } else {
        // First run: fetch last 30 days
        since = DateTime.now().subtract(const Duration(days: 30));
      }

      final items = await fetch(since);

      int maxTimestamp = lastSyncMs ?? 0;

      for (final item in items) {
        final ts = getTimestamp(item);
        final receivedAt = ts != null
            ? DateTime.fromMillisecondsSinceEpoch(ts)
            : DateTime.now();

        _controller.add(RawCaptureEvent(
          rawText: jsonEncode(item),
          sender: sender,
          receivedAt: receivedAt,
          channel: CaptureChannel.api,
        ));

        if (ts != null && ts > maxTimestamp) {
          maxTimestamp = ts;
        }
      }

      if (maxTimestamp > 0) {
        await prefs.setInt(cursorKey, maxTimestamp);
      }
    } on BinanceApiException catch (e) {
      debugPrint(
        'BinanceApiCaptureSource: Binance API error polling $sender: $e',
      );
    } catch (e) {
      debugPrint(
        'BinanceApiCaptureSource: Unexpected error polling $sender: $e',
      );
    }
  }
}
