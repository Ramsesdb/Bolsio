import 'dart:async';
import 'dart:io' show Platform;

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:wallex/core/database/app_db.dart';
import 'package:wallex/core/models/account/account.dart';
import 'package:wallex/core/database/services/pending_import/pending_import_service.dart';
import 'package:wallex/core/database/services/user-setting/user_setting_service.dart';
import 'package:wallex/core/models/auto_import/capture_channel.dart';
import 'package:wallex/core/models/auto_import/raw_capture_event.dart';
import 'package:wallex/core/models/auto_import/transaction_proposal_status.dart';
import 'package:wallex/core/utils/uuid.dart';
import 'package:wallex/core/services/auto_import/binance/binance_credentials_store.dart';
import 'package:wallex/core/services/auto_import/capture/binance_api_capture_source.dart';
import 'package:wallex/core/services/auto_import/capture/capture_source.dart';
import 'package:wallex/core/services/auto_import/capture/notification_capture_source.dart';
import 'package:wallex/core/services/auto_import/capture/sms_capture_source.dart';
import 'package:wallex/core/services/auto_import/dedupe/dedupe_checker.dart';
import 'package:wallex/core/services/auto_import/profiles/bank_profile.dart';
import 'package:wallex/core/services/auto_import/profiles/bank_profiles_registry.dart';

/// Central orchestrator that manages capture sources and dispatches events
/// through bank profiles to produce transaction proposals.
///
/// Singleton that:
/// 1. Registers and manages [CaptureSource]s.
/// 2. Merges their event streams.
/// 3. Matches events to [BankProfile]s from the registry.
/// 4. Resolves account IDs by profile's [accountMatchName].
/// 5. Runs deduplication checks.
/// 6. Persists proposals as pending imports.
class CaptureOrchestrator {
  static final CaptureOrchestrator instance = CaptureOrchestrator._();

  CaptureOrchestrator._();

  /// For testing: create an instance with custom dependencies.
  CaptureOrchestrator.forTesting({
    required AppDB db,
    required PendingImportService pendingImportService,
    required DedupeChecker dedupeChecker,
  })  : _db = db,
        _pendingImportService = pendingImportService,
        _dedupeChecker = dedupeChecker;

  final List<CaptureSource> _sources = [];
  StreamSubscription<RawCaptureEvent>? _subscription;

  /// Callback invoked after each successful INSERT of a pending import with
  /// status 'pending' (not duplicate). The int argument is the current count
  /// of pending imports.
  ///
  /// Used by the background service to trigger local notifications.
  Future<void> Function(int pendingCount)? onNewPendingImport;

  // Dependencies — lazily initialized for the singleton, injected for tests.
  AppDB? _db;
  PendingImportService? _pendingImportService;
  DedupeChecker? _dedupeChecker;

  AppDB get db => _db ?? AppDB.instance;
  PendingImportService get pendingImportService =>
      _pendingImportService ?? PendingImportService.instance;
  DedupeChecker get dedupeChecker =>
      _dedupeChecker ?? DedupeChecker.instance;

  /// Register a capture source to be managed by this orchestrator.
  Future<void> registerSource(CaptureSource source) async {
    _sources.add(source);
  }

  /// Start all registered sources and begin processing events.
  Future<void> start() async {
    // Start all sources
    for (final source in _sources) {
      try {
        await source.start();
      } catch (e) {
        debugPrint(
          'CaptureOrchestrator: Failed to start capture source ${source.channel.dbValue}: $e',
        );
      }
    }

    // Merge all event streams
    if (_sources.isNotEmpty) {
      final mergedStream = _sources.length == 1
          ? _sources.first.events
          : _mergeStreams(_sources.map((s) => s.events).toList());

      _subscription = mergedStream.listen(
        _handleEvent,
        onError: (error) {
          debugPrint(
            'CaptureOrchestrator: Error in merged capture stream: $error',
          );
        },
      );
    }
  }

  /// Stop all sources and cancel the merged subscription.
  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;

    for (final source in _sources) {
      try {
        await source.stop();
      } catch (e) {
        debugPrint(
          'CaptureOrchestrator: Failed to stop capture source ${source.channel.dbValue}: $e',
        );
      }
    }
  }

  /// Remove all registered sources (after stopping them).
  Future<void> clearSources() async {
    await stop();
    _sources.clear();
  }

  /// The currently registered sources (read-only view, useful for tests).
  List<CaptureSource> get sources => List.unmodifiable(_sources);

  /// Immediately poll all polling-based sources (e.g. Binance API).
  ///
  /// Event-driven sources (SMS, notification) return 0 — they emit via streams.
  /// Returns the total number of polling sources that were triggered.
  Future<int> pollNow() async {
    int polled = 0;
    for (final source in _sources) {
      if (source is BinanceApiCaptureSource) {
        try {
          await source.poll();
          polled++;
        } catch (e) {
          debugPrint(
            'CaptureOrchestrator: pollNow error on ${source.channel.dbValue}: $e',
          );
        }
      }
    }
    return polled;
  }

  /// Read user settings and (re-)configure capture sources accordingly.
  ///
  /// Call this:
  /// - At app startup (if autoImportEnabled == true).
  /// - After any toggle change in AutoImportSettingsPage.
  /// - After saving Binance API credentials.
  ///
  /// The [sourceFactory] parameter exists for testing — in production it is null
  /// and real sources are instantiated.
  Future<void> applySettings({
    Future<CaptureSource> Function(CaptureChannel)? sourceFactory,
  }) async {
    final autoEnabled =
        appStateSettings[SettingKey.autoImportEnabled] == '1';

    if (!autoEnabled) {
      await clearSources();
      debugPrint(
        'CaptureOrchestrator: Auto-import disabled — all sources stopped',
      );
      return;
    }

    // Stop current sources before reconfiguring
    await clearSources();

    // SMS source (Android only, or any platform when using sourceFactory for tests)
    final smsEnabled =
        appStateSettings[SettingKey.smsImportEnabled] == '1';
    if (smsEnabled && (sourceFactory != null || Platform.isAndroid)) {
      try {
        final CaptureSource smsSource;
        if (sourceFactory != null) {
          smsSource = await sourceFactory(CaptureChannel.sms);
        } else {
          final smsSenders = bankProfilesRegistry
              .where((p) => p.channel == CaptureChannel.sms)
              .expand((p) => p.knownSenders)
              .toSet()
              .toList();
          smsSource = SmsCaptureSource(allowlistSenders: smsSenders);
        }
        if (await smsSource.hasPermission()) {
          await registerSource(smsSource);
        } else {
          debugPrint(
            'CaptureOrchestrator: SMS source enabled but no permission — skipping',
          );
        }
      } catch (e) {
        debugPrint(
          'CaptureOrchestrator: Error creating SMS source: $e',
        );
      }
    }

    // Notification source (Android only, or any platform when using sourceFactory for tests)
    final notifEnabled =
        appStateSettings[SettingKey.notifListenerEnabled] == '1';
    if (notifEnabled && (sourceFactory != null || Platform.isAndroid)) {
      try {
        final CaptureSource notifSource;
        if (sourceFactory != null) {
          notifSource = await sourceFactory(CaptureChannel.notification);
        } else {
          final notifPackages = bankProfilesRegistry
              .where((p) => p.channel == CaptureChannel.notification)
              .expand((p) => p.knownSenders)
              .toSet()
              .toList();
          notifSource =
              NotificationCaptureSource(allowlistPackages: notifPackages);
        }
        if (await notifSource.hasPermission()) {
          await registerSource(notifSource);
        } else {
          debugPrint(
            'CaptureOrchestrator: Notification source enabled but no permission — skipping',
          );
        }
      } catch (e) {
        debugPrint(
          'CaptureOrchestrator: Error creating notification source: $e',
        );
      }
    }

    // Binance API source (all platforms)
    final binanceEnabled =
        appStateSettings[SettingKey.binanceApiEnabled] == '1';
    if (binanceEnabled) {
      try {
        if (sourceFactory != null) {
          // In test mode, delegate permission check to the source itself
          final binanceSource = await sourceFactory(CaptureChannel.api);
          if (await binanceSource.hasPermission()) {
            await registerSource(binanceSource);
          }
        } else {
          final hasCreds =
              await BinanceCredentialsStore.instance.hasCredentials();
          if (hasCreds) {
            final binanceSource = BinanceApiCaptureSource();
            await registerSource(binanceSource);
          } else {
            debugPrint(
              'CaptureOrchestrator: Binance API enabled but no credentials — skipping',
            );
          }
        }
      } catch (e) {
        debugPrint(
          'CaptureOrchestrator: Error creating Binance API source: $e',
        );
      }
    }

    // Start all registered sources
    if (_sources.isNotEmpty) {
      await start();
      debugPrint(
        'CaptureOrchestrator: Auto-import started with ${_sources.length} source(s): '
        '${_sources.map((s) => s.channel.dbValue).join(', ')}',
      );
    } else {
      debugPrint(
        'CaptureOrchestrator: Auto-import enabled but no sources could be registered',
      );
    }
  }

  /// Process a single raw capture event through the bank profile pipeline.
  ///
  /// Resilient: exceptions in individual profiles are caught and logged,
  /// never crashing the stream.
  Future<void> _handleEvent(RawCaptureEvent event) async {
    // Find matching profiles by channel + sender
    final matchingProfiles = bankProfilesRegistry.where((profile) =>
        profile.channel == event.channel &&
        profile.knownSenders.contains(event.sender));

    for (final profile in matchingProfiles) {
      try {
        // Parse first so we can resolve account by bank name + proposal currency.
        final parsedProposal = profile.tryParse(event, accountId: null);

        if (parsedProposal == null) {
          debugPrint(
            'CaptureOrchestrator: Profile ${profile.bankName} (${profile.channel.dbValue}) '
            'could not parse event from ${event.sender}: '
            '"${event.rawText.length > 60 ? '${event.rawText.substring(0, 60)}...' : event.rawText}"',
          );
          continue;
        }

        final resolvedAccountId = await _resolveAccountId(
          profile.accountMatchName,
          currencyCode: parsedProposal.currencyId,
        );

        final proposal = parsedProposal.copyWith(accountId: resolvedAccountId);

        // Run deduplication check
        final isDuplicate = await dedupeChecker.check(proposal);

        if (isDuplicate) {
          debugPrint(
            'CaptureOrchestrator: Skipping duplicate proposal: '
            '${proposal.bankRef ?? 'no-ref'} (${proposal.amount} ${proposal.currencyId})',
          );
          continue;
        }

        if (await _shouldSkipBinanceProposalToAvoidDoubleCount(proposal)) {
          debugPrint(
            'CaptureOrchestrator: Skipping Binance proposal to avoid double count: '
            '${proposal.bankRef ?? 'no-ref'} (${proposal.amount} ${proposal.currencyId})',
          );
          continue;
        }

        // Persist the proposal
        final status = TransactionProposalStatus.pending;

        await pendingImportService
            .insertPendingImport(proposal.toCompanion(status: status));

        debugPrint(
          'CaptureOrchestrator: Persisted proposal: ${proposal.bankRef ?? 'no-ref'} '
          'as $status (${proposal.amount} ${proposal.currencyId})',
        );

        // Notify background service about new pending imports
        if (status == TransactionProposalStatus.pending &&
            onNewPendingImport != null) {
          try {
            // Get the current count of pending imports for the notification
            final countStream = pendingImportService.watchPendingCount();
            final currentCount =
                await countStream.first.timeout(const Duration(seconds: 2));
            await onNewPendingImport!(currentCount);
          } catch (e) {
            debugPrint(
              'CaptureOrchestrator: Error invoking onNewPendingImport callback: $e',
            );
          }
        }
      } catch (e, stackTrace) {
        // A throw in a profile must NOT crash the stream
        debugPrint(
          'CaptureOrchestrator: Error processing event with profile ${profile.bankName}: $e\n$stackTrace',
        );
      }
    }
  }

  /// Look up an account ID by name.
  ///
  /// Returns `null` if no matching account is found.
  Future<String?> _resolveAccountId(
    String accountMatchName, {
    String? currencyCode,
  }) async {
    final normalizedCurrency = currencyCode?.toUpperCase();

    if (normalizedCurrency != null && normalizedCurrency.isNotEmpty) {
      final byCurrency = await (db.select(db.accounts)
            ..where(
              (a) =>
                  a.name.equals(accountMatchName) &
                  a.currencyId.equals(normalizedCurrency),
            )
            ..limit(1))
          .getSingleOrNull();

      if (byCurrency != null) return byCurrency.id;
    }

    if (normalizedCurrency != null && normalizedCurrency.isNotEmpty) {
      if (accountMatchName == 'Banco de Venezuela' &&
          (normalizedCurrency == 'USD' || normalizedCurrency == 'VES')) {
        return _createBdvAccountIfMissing(normalizedCurrency);
      }

      final similarByCurrency = await db.customSelect(
        '''
        SELECT id
        FROM accounts
        WHERE LOWER(name) LIKE LOWER(?)
          AND currencyId = ?
        ORDER BY displayOrder ASC
        LIMIT 1
        ''',
        variables: [
          Variable.withString('$accountMatchName%'),
          Variable.withString(normalizedCurrency),
        ],
        readsFrom: {db.accounts},
      ).getSingleOrNull();

      if (similarByCurrency != null) {
        return similarByCurrency.data['id'] as String?;
      }

      // Do not fallback to a different-currency account.
      return null;
    }

    final fallback = await (db.select(db.accounts)
          ..where((a) => a.name.equals(accountMatchName))
          ..limit(1))
        .getSingleOrNull();

    if (fallback != null) return fallback.id;

    if (accountMatchName == 'Banco de Venezuela' &&
        normalizedCurrency != null &&
        (normalizedCurrency == 'USD' || normalizedCurrency == 'VES')) {
      return _createBdvAccountIfMissing(normalizedCurrency);
    }

    return null;
  }

  Future<bool> _shouldSkipBinanceProposalToAvoidDoubleCount(
    dynamic proposal,
  ) async {
    final sender = (proposal.sender as String?)?.toLowerCase() ?? '';
    if (!sender.startsWith('binance:')) return false;

    final accountId = proposal.accountId as String?;
    if (accountId == null) return false;

    final accountRow = await db.customSelect(
      '''
      SELECT name, currencyId
      FROM accounts
      WHERE id = ?
      LIMIT 1
      ''',
      variables: [Variable.withString(accountId)],
      readsFrom: {db.accounts},
    ).getSingleOrNull();

    if (accountRow == null) return false;

    final name = (accountRow.data['name'] as String? ?? '').toLowerCase();
    final currency = (accountRow.data['currencyId'] as String? ?? '').toUpperCase();

    // Check if a recent transfer already credited this account.
    // When a BDV→Binance transfer is saved as type 'T', the Binance side
    // is already recorded via receivingAccountID + valueInDestiny.
    // If the API later reports the same deposit, skip it.
    final proposalAmount = (proposal.amount as double?) ?? 0.0;
    final proposalDate = proposal.date as DateTime?;

    if (proposalAmount > 0 && proposalDate != null) {
      final recentTransferRow = await db.customSelect(
        '''
        SELECT id FROM transactions
        WHERE type = 'T'
          AND receivingAccountID = ?
          AND date BETWEEN ? AND ?
          AND (
            ABS(COALESCE(valueInDestiny, ABS(value)) - ?) < 1.0
          )
        LIMIT 1
        ''',
        variables: [
          Variable.withString(accountId),
          Variable.withDateTime(
            proposalDate.subtract(const Duration(hours: 24)),
          ),
          Variable.withDateTime(
            proposalDate.add(const Duration(hours: 24)),
          ),
          Variable.withReal(proposalAmount),
        ],
        readsFrom: {db.transactions},
      ).getSingleOrNull();

      if (recentTransferRow != null) {
        debugPrint(
          'CaptureOrchestrator: Binance deposit matches recent transfer '
          '${recentTransferRow.data['id']} — skipping to avoid double count',
        );
        return true;
      }
    }

    // Balance-sync mode: Binance USD account with no local tx history.
    if (!name.contains('binance') || currency != 'USD') return false;

    final txCountRow = await db.customSelect(
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
    ).getSingle();

    final txCount = (txCountRow.data['txCount'] as int?) ?? 0;
    return txCount == 0;
  }

  Future<String?> _createBdvAccountIfMissing(String currencyCode) async {
    final name = currencyCode == 'VES'
        ? 'Banco de Venezuela'
        : 'Banco de Venezuela $currencyCode';

    final existing = await (db.select(db.accounts)
          ..where(
            (a) => a.name.equals(name) & a.currencyId.equals(currencyCode),
          )
          ..limit(1))
        .getSingleOrNull();

    if (existing != null) return existing.id;

    final maxOrderRow = await db.customSelect(
      'SELECT COALESCE(MAX(displayOrder), 0) AS maxOrder FROM accounts',
      readsFrom: {db.accounts},
    ).getSingle();
    final maxOrder = (maxOrderRow.data['maxOrder'] as int?) ?? 0;

    final newAccount = AccountInDB(
      id: generateUUID(),
      name: name,
      displayOrder: maxOrder + 1,
      type: AccountType.normal,
      currencyId: currencyCode,
      iniValue: 0,
      date: DateTime.now(),
      iconId: 'account_balance',
      color: '1A237E',
    );

    await db.into(db.accounts).insert(newAccount);
    db.markTablesUpdated([db.accounts]);

    debugPrint(
      'CaptureOrchestrator: Auto-created account $name ($currencyCode) for BDV imports',
    );

    return newAccount.id;
  }

  /// Merge multiple streams into one. Uses StreamGroup-like behavior.
  Stream<T> _mergeStreams<T>(List<Stream<T>> streams) {
    final controller = StreamController<T>.broadcast();
    final subscriptions = <StreamSubscription<T>>[];

    for (final stream in streams) {
      subscriptions.add(stream.listen(
        controller.add,
        onError: controller.addError,
      ));
    }

    controller.onCancel = () async {
      for (final sub in subscriptions) {
        await sub.cancel();
      }
    };

    return controller.stream;
  }
}
