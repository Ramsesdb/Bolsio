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
import 'package:wallex/core/services/auto_import/capture/capture_event_log.dart';
import 'package:wallex/core/services/auto_import/capture/capture_health_monitor.dart';
import 'package:wallex/core/services/auto_import/capture/models/capture_event.dart';
import 'package:wallex/core/services/auto_import/dedupe/dedupe_checker.dart';
import 'package:wallex/core/services/auto_import/dedupe/fingerprint_registry.dart';
import 'package:wallex/core/services/auto_import/dedupe/notif_fingerprint.dart';
import 'package:wallex/core/services/auto_import/profiles/bank_profile.dart';
import 'package:wallex/core/services/auto_import/profiles/bank_profiles_registry.dart';
import 'package:wallex/core/services/auto_import/profiles/generic_llm_profile.dart';
import 'package:wallex/core/services/bank_detection/bank_detection_service.dart';
import 'package:wallex/core/services/ai/auto_categorization_service.dart';

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

  /// LLM fallback parser — called when no regex profile matched a notification
  /// from a known bank sender.
  final _genericLlmFallback = const GenericLlmProfile();

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

    // Stop the health monitor too — there is nothing left to watch over.
    try {
      await CaptureHealthMonitor.instance.stop();
    } catch (_) {}
  }

  /// Remove all registered sources (after stopping them).
  Future<void> clearSources() async {
    await stop();
    _sources.clear();
    CaptureHealthMonitor.instance.unbindNotificationSource();
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
    /// If non-null, only configure sources for the specified channels.
    /// Pass `{CaptureChannel.notification}` in the main isolate and
    /// `{CaptureChannel.sms, CaptureChannel.api}` in the background isolate
    /// so that the notification EventChannel (which only works in the main
    /// FlutterEngine) is never subscribed from the background service.
    Set<CaptureChannel>? channels,
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
    final includeSms = channels == null || channels.contains(CaptureChannel.sms);
    if (includeSms && smsEnabled && (sourceFactory != null || Platform.isAndroid)) {
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
    final includeNotif = channels == null || channels.contains(CaptureChannel.notification);
    if (includeNotif && notifEnabled && (sourceFactory != null || Platform.isAndroid)) {
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
          if (notifSource is NotificationCaptureSource) {
            CaptureHealthMonitor.instance
                .bindNotificationSource(notifSource);
            // Idempotent — if already running this is a no-op.
            await CaptureHealthMonitor.instance.start();
          }
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
    final includeBinance = channels == null || channels.contains(CaptureChannel.api);
    if (includeBinance && binanceEnabled) {
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
    // Diagnostic: log the incoming raw event so the diagnostics screen sees
    // every message the orchestrator got, regardless of what happens next.
    final diagnosticBase = _buildDiagnosticBase(event);
    _logDiagnostic(diagnosticBase);

    // -----------------------------------------------------------------
    // Tanda 4 — fingerprint-based pre-dedupe.
    //
    // Goal: kill reposts (Android redispatches the same notif when the bank
    // updates the line, user taps it, etc.) and distinguish "user removed"
    // events (hasRemoved) from new captures — BEFORE we even try to parse.
    // -----------------------------------------------------------------
    // Only notifications carry the native metadata; SMS events bypass this
    // block entirely (they already have their own robust dedupe via bankRef).
    if (event.channel == CaptureChannel.notification) {
      final fingerprint = NotifFingerprint.from(event);

      // A "notification removed" event is NOT a new capture. Register the
      // fact and exit early so the orchestrator doesn't try to parse a
      // phantom transaction from the OS-generated removal hook.
      if (event.hasRemoved) {
        try {
          await FingerprintRegistry.instance.markRemoved(fingerprint);
        } catch (e) {
          debugPrint(
            'CaptureOrchestrator: markRemoved error: $e',
          );
        }
        _logDiagnostic(diagnosticBase.copyWith(
          id: generateUUID(),
          status: CaptureEventStatus.systemEvent,
          reason:
              'Usuario borró notif id=${event.nativeNotifId ?? '?'} (hasRemoved)',
        ));
        return;
      }

      // Known fingerprint? Skip the whole pipeline.
      try {
        final seen = await FingerprintRegistry.instance.lookup(fingerprint);
        if (seen != null) {
          final isStableMatch = seen.stable == fingerprint.stable;
          final linked = seen.linkedTransactionId ?? '-';
          final hoursSince =
              DateTime.now().difference(seen.lastSeen).inHours;
          final fpShort = fingerprint.contentHash;
          final firstSeenRel = _relativeAgo(seen.firstSeen);
          final headline = isStableMatch
              ? 'Repost exacto de notif previa (tx=$linked, ocurrencias=${seen.occurrences + 1})'
              : 'Contenido idéntico visto hace ${hoursSince}h, tx=$linked';
          final reason =
              '$headline · Fingerprint: $fpShort · Primera vez: $firstSeenRel';
          _logDiagnostic(diagnosticBase.copyWith(
            id: generateUUID(),
            status: CaptureEventStatus.duplicate,
            reason: reason,
          ));
          // Still bump the `lastSeen` / occurrences counter so the diagnostic
          // tile reflects the real event rate.
          try {
            await FingerprintRegistry.instance.markSeen(fingerprint);
          } catch (_) {}
          return;
        }
      } catch (e) {
        debugPrint('CaptureOrchestrator: fingerprint lookup error: $e');
        // Graceful degrade: keep processing even if the registry is broken.
      }
    }

    // Find matching profiles by channel + sender
    final candidateProfiles = bankProfilesRegistry
        .where((profile) =>
            profile.channel == event.channel &&
            profile.knownSenders.contains(event.sender))
        .toList();

    if (candidateProfiles.isEmpty) {
      final reason = event.channel == CaptureChannel.notification
          ? 'Package "${event.sender}" no tiene perfil en el registro'
          : 'Remitente "${event.sender}" no tiene perfil en el registro';
      _logDiagnostic(diagnosticBase.copyWith(
        id: generateUUID(),
        status: CaptureEventStatus.filteredOut,
        reason: reason,
      ));
      return;
    }

    // Respect per-profile toggles from the auto-import settings UI. A profile
    // whose toggle is OFF must not parse anything — we log a diagnostic so
    // the user can see *why* a known sender was ignored.
    final matchingProfiles = <BankProfile>[];
    for (final profile in candidateProfiles) {
      if (UserSettingService.instance.isProfileEnabled(profile.profileId)) {
        matchingProfiles.add(profile);
      } else {
        _logDiagnostic(diagnosticBase.copyWith(
          id: generateUUID(),
          status: CaptureEventStatus.filteredOut,
          reason:
              'Perfil "${profile.bankName}" está desactivado en ajustes',
          matchedProfile: profile.bankName,
        ));
      }
    }

    if (matchingProfiles.isEmpty) {
      // Every candidate was disabled — nothing else to do.
      return;
    }

    // From here on, a notification event has a matching profile and is going
    // into the parser. Register its fingerprint (without a tx id yet) so that
    // any repost — even a parse failure — is caught by the early exit above.
    NotifFingerprint? fingerprintForMarking;
    if (event.channel == CaptureChannel.notification) {
      fingerprintForMarking = NotifFingerprint.from(event);
    }
    // Track the tx id of the first successfully-persisted proposal so we can
    // link it to the fingerprint after the loop. Null means either parse
    // failed everywhere or every profile was a duplicate; we still mark the
    // fingerprint as "seen" to avoid re-parsing the same raw text on repost.
    String? createdTransactionId;

    for (final profile in matchingProfiles) {
      try {
        // Parse first so we can resolve account by bank name + proposal currency.
        final parseResult =
            await profile.tryParseWithDetails(event, accountId: null);

        if (!parseResult.success || parseResult.transaction == null) {
          debugPrint(
            'CaptureOrchestrator: Profile ${profile.bankName} (${profile.channel.dbValue}) '
            'could not parse event from ${event.sender}: '
            '"${event.rawText.length > 60 ? '${event.rawText.substring(0, 60)}...' : event.rawText}" '
            '— reason: ${parseResult.failureReason ?? 'unspecified'}',
          );
          _logDiagnostic(diagnosticBase.copyWith(
            id: generateUUID(),
            status: CaptureEventStatus.parsedFailed,
            reason: parseResult.failureReason ??
                'El perfil no pudo extraer una transacción',
            matchedProfile: profile.bankName,
          ));
          continue;
        }

        final parsedProposal = parseResult.transaction!;

        final resolvedAccountId = await _resolveAccountId(
          profile.accountMatchName,
          currencyCode: parsedProposal.currencyId,
        );

        final proposal = parsedProposal.copyWith(accountId: resolvedAccountId);

        // [DEDUPE-DBG] Capture point: proposal ready, about to dedupe.
        debugPrint(
          '[DEDUPE-DBG] orchestrator: NEW PROPOSAL '
          'profile=${profile.bankName} channel=${event.channel.dbValue} '
          'sender=${event.sender} bankRef=${proposal.bankRef} '
          'accountId=${proposal.accountId} amount=${proposal.amount} '
          'currency=${proposal.currencyId} date=${proposal.date.toIso8601String()}',
        );

        // Run deduplication check FIRST — before any AI call. This avoids
        // burning AI quota on events that are already known duplicates
        // (e.g. Binance polling re-reporting the same transactions every
        // few minutes).
        final isDuplicate = await dedupeChecker.check(proposal);
        debugPrint(
          '[DEDUPE-DBG] orchestrator: dedupe.check returned $isDuplicate '
          'for bankRef=${proposal.bankRef}',
        );

        if (isDuplicate) {
          debugPrint(
            'CaptureOrchestrator: Skipping duplicate proposal: '
            '${proposal.bankRef ?? 'no-ref'} (${proposal.amount} ${proposal.currencyId})',
          );
          _logDiagnostic(diagnosticBase.copyWith(
            id: generateUUID(),
            status: CaptureEventStatus.duplicate,
            reason: proposal.bankRef != null && proposal.bankRef!.isNotEmpty
                ? 'Duplicado por bankRef=${proposal.bankRef}'
                : 'Duplicado (coincidencia con transacción existente)',
            matchedProfile: profile.bankName,
            parsedAmount: proposal.amount,
            parsedCurrency: proposal.currencyId,
          ));
          continue;
        }

        // Run the Binance double-count protection BEFORE the AI call. If the
        // proposal would be skipped anyway, we don't want to spend AI quota
        // on it. Each Binance poll (every ~5 min) re-reports the same
        // transactions, so calling the IA classifier on every poll for a
        // proposal that ends up being silently skipped is pure waste.
        final shouldAutoSkip =
            await _shouldSkipBinanceProposalToAvoidDoubleCount(proposal);

        // AI auto-categorization (Feature 1) — only after we know this is
        // not a duplicate AND not going to be auto-skipped, so we never spend
        // AI quota on redundant events.
        var enhancedProposal = proposal;
        if (!shouldAutoSkip && proposal.proposedCategoryId == null) {
          debugPrint(
            '[DEDUPE-DBG] CALLING AI classifier for bankRef=${proposal.bankRef}',
          );
          final aiResult = await AutoCategorizationService.instance
              .suggest(proposal: proposal)
              .timeout(const Duration(seconds: 2), onTimeout: () => null)
              .catchError((_) => null);

          if (aiResult != null) {
            enhancedProposal = proposal.copyWith(
              proposedCategoryId: aiResult.categoryId,
            );
          }
        }

        // Persist the proposal. When the double-count protection fires, we
        // store the row with status=duplicate so the dedupe check on the
        // next poll finds it via findByBankRef and short-circuits BEFORE
        // hitting the IA classifier again.
        final status = shouldAutoSkip
            ? TransactionProposalStatus.duplicate
            : TransactionProposalStatus.pending;

        if (shouldAutoSkip) {
          debugPrint(
            '[DEDUPE-DBG] orchestrator: SKIP via double-count protection '
            'bankRef=${proposal.bankRef} amount=${proposal.amount} '
            '— persisting as auto-dismissed',
          );
          debugPrint(
            'CaptureOrchestrator: Skipping Binance proposal to avoid double count: '
            '${enhancedProposal.bankRef ?? 'no-ref'} (${enhancedProposal.amount} ${enhancedProposal.currencyId})',
          );
          _logDiagnostic(diagnosticBase.copyWith(
            id: generateUUID(),
            status: CaptureEventStatus.duplicate,
            reason:
                'Saltado para evitar doble conteo con transferencia Binance reciente',
            matchedProfile: profile.bankName,
            parsedAmount: enhancedProposal.amount,
            parsedCurrency: enhancedProposal.currencyId,
          ));
        }

        debugPrint(
          '[DEDUPE-DBG] orchestrator: INSERT_PATH — about to insertPendingImport '
          'id=${enhancedProposal.id} bankRef=${enhancedProposal.bankRef} '
          'accountId=${enhancedProposal.accountId} amount=${enhancedProposal.amount} '
          'currency=${enhancedProposal.currencyId} status=$status',
        );

        try {
          final insertedRowId = await pendingImportService
              .insertPendingImport(enhancedProposal.toCompanion(status: status));
          debugPrint(
            '[DEDUPE-DBG] orchestrator: insertPendingImport SUCCESS '
            'rowId=$insertedRowId id=${enhancedProposal.id} bankRef=${enhancedProposal.bankRef}',
          );
          if (shouldAutoSkip) {
            debugPrint(
              '[DEDUPE-DBG] orchestrator: auto-dismissed pending_import inserted '
              'bankRef=${enhancedProposal.bankRef}',
            );
          }
        } catch (e, st) {
          debugPrint(
            '[DEDUPE-DBG] orchestrator: insertPendingImport THREW '
            'id=${enhancedProposal.id} bankRef=${enhancedProposal.bankRef} '
            'error=$e\n$st',
          );
          rethrow;
        }

        // For auto-skipped rows we already emitted a `duplicate` diagnostic
        // above; skip the success path bookkeeping (createdTransactionId,
        // parsedSuccess diagnostic, health signal, pending-count notification).
        if (shouldAutoSkip) {
          continue;
        }

        // Remember the first successfully-persisted tx id so we can link it
        // to the notification fingerprint once the loop is done.
        createdTransactionId ??= enhancedProposal.id;

        debugPrint(
          'CaptureOrchestrator: Persisted proposal: ${enhancedProposal.bankRef ?? 'no-ref'} '
          'as $status (${enhancedProposal.amount} ${enhancedProposal.currencyId})',
        );

        _logDiagnostic(diagnosticBase.copyWith(
          id: generateUUID(),
          status: CaptureEventStatus.parsedSuccess,
          reason: resolvedAccountId == null
              ? 'Parseada OK — sin cuenta asociada'
              : 'Parseada OK — propuesta creada',
          matchedProfile: profile.bankName,
          parsedAmount: enhancedProposal.amount,
          parsedCurrency: enhancedProposal.currencyId,
        ));

        // Health signal: the pipeline produced a parseable proposal — this is
        // the strongest "things are working end-to-end" indicator we have.
        try {
          CaptureHealthMonitor.instance.markSuccess();
        } catch (_) {}

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
        _logDiagnostic(diagnosticBase.copyWith(
          id: generateUUID(),
          status: CaptureEventStatus.parsedFailed,
          reason: 'Excepción al procesar: $e',
          matchedProfile: profile.bankName,
        ));
      }
    }

    // ── LLM fallback ──────────────────────────────────────────────────────────
    // If no regex profile produced a successful result, and the sender is a
    // known bank (even without a dedicated parser), ask the LLM to extract the
    // transaction data. Only fires for notification events — SMS events from
    // unknown senders are not sent to the LLM.
    final anyProfileSucceeded = createdTransactionId != null;
    if (!anyProfileSucceeded &&
        event.channel == CaptureChannel.notification &&
        _isKnownBankSender(event.sender) &&
        UserSettingService.instance.isProfileEnabled('generic_llm')) {
      try {
        final llmResult = await _genericLlmFallback.tryParseWithDetails(
          event,
          accountId: null,
        );

        if (llmResult.success && llmResult.transaction != null) {
          final parsedProposal = llmResult.transaction!;
          final bankNameHint = llmResult.resolvedBankName ?? '';

          final resolvedAccountId = await _resolveAccountId(
            bankNameHint,
            currencyCode: parsedProposal.currencyId,
          );

          final proposal = parsedProposal.copyWith(accountId: resolvedAccountId);

          debugPrint(
            '[LLM-FALLBACK] orchestrator: proposal from LLM '
            'bank=$bankNameHint bankRef=${proposal.bankRef} '
            'amount=${proposal.amount} currency=${proposal.currencyId}',
          );

          final isDuplicate = await dedupeChecker.check(proposal);
          if (isDuplicate) {
            debugPrint(
              '[LLM-FALLBACK] orchestrator: duplicate — skipping',
            );
            _logDiagnostic(diagnosticBase.copyWith(
              id: generateUUID(),
              status: CaptureEventStatus.duplicate,
              reason: proposal.bankRef != null && proposal.bankRef!.isNotEmpty
                  ? 'Duplicado por bankRef=${proposal.bankRef} (LLM fallback)'
                  : 'Duplicado (LLM fallback)',
              matchedProfile: _genericLlmFallback.bankName,
              parsedAmount: proposal.amount,
              parsedCurrency: proposal.currencyId,
            ));
          } else {
            // AI auto-categorization for LLM-parsed proposals
            var enhancedProposal = proposal;
            if (proposal.proposedCategoryId == null) {
              final aiResult = await AutoCategorizationService.instance
                  .suggest(proposal: proposal)
                  .timeout(const Duration(seconds: 2), onTimeout: () => null)
                  .catchError((_) => null);
              if (aiResult != null) {
                enhancedProposal = proposal.copyWith(
                  proposedCategoryId: aiResult.categoryId,
                );
              }
            }

            await pendingImportService.insertPendingImport(
              enhancedProposal.toCompanion(
                status: TransactionProposalStatus.pending,
              ),
            );

            createdTransactionId = enhancedProposal.id;

            _logDiagnostic(diagnosticBase.copyWith(
              id: generateUUID(),
              status: CaptureEventStatus.parsedSuccess,
              reason: resolvedAccountId == null
                  ? 'Parseada por IA — sin cuenta asociada'
                  : 'Parseada por IA — propuesta creada',
              matchedProfile: bankNameHint.isNotEmpty
                  ? bankNameHint
                  : _genericLlmFallback.bankName,
              parsedAmount: enhancedProposal.amount,
              parsedCurrency: enhancedProposal.currencyId,
            ));

            try {
              CaptureHealthMonitor.instance.markSuccess();
            } catch (_) {}

            if (onNewPendingImport != null) {
              try {
                final countStream =
                    pendingImportService.watchPendingCount();
                final currentCount = await countStream.first
                    .timeout(const Duration(seconds: 2));
                await onNewPendingImport!(currentCount);
              } catch (e) {
                debugPrint(
                  'CaptureOrchestrator: Error invoking onNewPendingImport (LLM fallback): $e',
                );
              }
            }
          }
        } else {
          _logDiagnostic(diagnosticBase.copyWith(
            id: generateUUID(),
            status: CaptureEventStatus.parsedFailed,
            reason:
                'LLM fallback: ${llmResult.failureReason ?? 'no se pudo extraer transacción'}',
            matchedProfile: _genericLlmFallback.bankName,
          ));
        }
      } catch (e, stackTrace) {
        debugPrint(
          'CaptureOrchestrator: LLM fallback error: $e\n$stackTrace',
        );
        _logDiagnostic(diagnosticBase.copyWith(
          id: generateUUID(),
          status: CaptureEventStatus.parsedFailed,
          reason: 'Excepción en LLM fallback: $e',
          matchedProfile: _genericLlmFallback.bankName,
        ));
      }
    }

    // Register the notification fingerprint after the loop. This runs even
    // when parsing failed or was deduped — so a later repost with the same
    // content is caught by the early-exit in this same method.
    if (fingerprintForMarking != null) {
      try {
        await FingerprintRegistry.instance.markSeen(
          fingerprintForMarking,
          transactionId: createdTransactionId,
        );
      } catch (e) {
        debugPrint('CaptureOrchestrator: markSeen error: $e');
      }
    }
  }

  /// Returns `true` when [sender] is a package name registered in
  /// [BankDetectionService.kPackageToProfileId], i.e. a known bank app — even
  /// if no regex profile has been implemented for it yet.
  bool _isKnownBankSender(String? sender) {
    if (sender == null || sender.isEmpty) return false;
    return BankDetectionService.kPackageToProfileId.containsKey(sender);
  }

  /// Build the baseline diagnostic record for [event] with status `received`.
  CaptureEvent _buildDiagnosticBase(RawCaptureEvent event) {
    final isNotif = event.channel == CaptureChannel.notification;
    final rawText = event.rawText;
    final newlineIdx = rawText.indexOf('\n');
    String? title;
    String content = rawText;
    if (isNotif && newlineIdx > 0) {
      title = rawText.substring(0, newlineIdx).trim();
      content = rawText.substring(newlineIdx + 1).trim();
    }

    final CaptureEventSource source;
    switch (event.channel) {
      case CaptureChannel.notification:
        source = CaptureEventSource.notification;
        break;
      case CaptureChannel.sms:
        source = CaptureEventSource.sms;
        break;
      case CaptureChannel.api:
        source = CaptureEventSource.api;
        break;
      case CaptureChannel.receiptImage:
        source = CaptureEventSource.receiptImage;
        break;
      case CaptureChannel.voice:
        source = CaptureEventSource.voice;
        break;
    }

    return CaptureEvent(
      id: generateUUID(),
      timestamp: event.receivedAt,
      source: source,
      packageName: isNotif ? event.sender : null,
      sender: isNotif ? null : event.sender,
      title: title,
      content: content,
      status: CaptureEventStatus.received,
      reason: 'Notificación recibida',
    );
  }

  /// Human-readable "X time ago" for the diagnostic reason strings.
  String _relativeAgo(DateTime ts) {
    final diff = DateTime.now().difference(ts);
    if (diff.inSeconds < 60) return 'hace <1min';
    if (diff.inMinutes < 60) return 'hace ${diff.inMinutes}min';
    if (diff.inHours < 24) return 'hace ${diff.inHours}h';
    return 'hace ${diff.inDays}d';
  }

  void _logDiagnostic(CaptureEvent event) {
    try {
      CaptureEventLog.instance.log(event);
    } catch (e) {
      debugPrint('CaptureOrchestrator: failed to log diagnostic: $e');
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
