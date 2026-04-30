import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:notification_listener_service/notification_listener_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kilatex/core/services/auto_import/background/wallex_background_service.dart';
import 'package:kilatex/core/services/auto_import/capture/capture_event_log.dart';
import 'package:kilatex/core/services/auto_import/capture/models/capture_event.dart';
import 'package:kilatex/core/services/auto_import/capture/notification_capture_source.dart';
import 'package:kilatex/core/services/auto_import/capture/permission_coordinator.dart';
import 'package:kilatex/core/services/auto_import/dedupe/fingerprint_registry.dart';
import 'package:kilatex/core/utils/uuid.dart';

/// Coarse-grained health status of the notification listener pipeline.
///
/// The native `NotificationListenerService` can report itself as "permission
/// granted" while the stream is silently dead (MIUI/Xiaomi revokes the bind,
/// the service process is killed, etc.). The [CaptureHealthMonitor] combines
/// permission checks + last-event timestamps to surface a more honest status.
enum CaptureHealthStatus {
  /// Subscribed and events have been flowing recently (or service just started).
  healthy,

  /// Subscribed but no events in a long time — possible zombie state.
  stale,

  /// Stream is not subscribed (cancelled / never started / error).
  unsubscribed,

  /// OS no longer reports the listener permission as granted.
  permissionMissing,

  /// Status has not been evaluated yet (e.g. on first boot).
  unknown,
}

/// How long without any inbound event before we consider the listener stale.
///
/// Kept shorter on Xiaomi/POCO-like devices to recover faster from
/// notification-listener zombie states that can appear overnight.
const Duration kStaleEventThreshold = Duration(hours: 8);

/// Grace period after (re)starting the monitor during which we report
/// [CaptureHealthStatus.healthy] even without any events yet.
const Duration kFreshStartGrace = Duration(minutes: 5);

/// How often the monitor wakes up to re-evaluate health and (optionally)
/// re-subscribe. Kept at 60 s as a compromise between responsiveness and
/// wakelock / battery usage inside the foreground service isolate.
const Duration kMonitorInterval = Duration(seconds: 60);

/// Periodic forced refresh of the native listener subscription even while
/// healthy, to proactively heal silent OEM binder drops.
const Duration kProactiveReconnectInterval = Duration(hours: 3);

/// After this many *consecutive* reconnect failures we escalate to a full
/// pipeline restart (stop + start of the background service) rather than
/// retrying a soft re-subscribe. Set at 2 so the first reconnect attempt has
/// already happened and a second one also failed — strong signal that the
/// native binder is wedged and Dart-side retries won't fix it.
const int kConsecutiveFailThresholdForRestart = 2;

/// Throttle for pipeline restarts — do not bounce the foreground service more
/// than once per hour even if we keep failing. Prevents a restart loop if the
/// service itself fails to start (e.g. OEM killed the autostart permission).
const Duration kMinPipelineRestartInterval = Duration(hours: 1);

/// Singleton that watches the liveness of the capture pipeline and tries to
/// auto-heal it by re-subscribing the native stream when needed.
class CaptureHealthMonitor {
  static final CaptureHealthMonitor instance = CaptureHealthMonitor._();

  CaptureHealthMonitor._();

  static const String _prefsLastEventAt = 'capture_health_last_event_at';
  static const String _prefsLastSuccessAt = 'capture_health_last_success_at';
  static const String _prefsLastResubscribeAt =
      'capture_health_last_resubscribe_at';
  static const String _prefsLastBatteryWarnAt = 'capture_health_last_battery_warn_at';
  static const String _prefsLastFpPruneAt = 'capture_health_last_fp_prune_at';
  static const String _prefsLastPipelineRestartAt =
      'capture_health_last_pipeline_restart_at';

  /// Run fingerprint-registry pruning at most once every 24h so we don't
  /// spam SharedPreferences from every health tick.
  static const Duration _fpPruneInterval = Duration(hours: 24);

  /// Drop fingerprints whose `lastSeen` is older than this age (in-memory +
  /// persisted copy). 30 days matches the window we use for bankRef lookups.
  static const Duration _fpPruneMaxAge = Duration(days: 30);

  /// Do not spam the event log with the "battery optimization still on"
  /// warning more than once per day.
  static const Duration _batteryWarnInterval = Duration(hours: 24);

  /// Last time ANY inbound native event reached the source (before filtering).
  DateTime? _lastEventAt;
  DateTime? get lastEventAt => _lastEventAt;

  /// Last time the orchestrator produced a successful parsed proposal.
  DateTime? _lastSuccessAt;
  DateTime? get lastSuccessAt => _lastSuccessAt;

  /// Last time we successfully forced a listener re-subscribe.
  DateTime? _lastResubscribeAt;
  DateTime? get lastResubscribeAt => _lastResubscribeAt;

  /// Reactive copy of [lastResubscribeAt] so the UI can rebuild when the
  /// monitor re-binds the native stream without having to poll every minute.
  final ValueNotifier<DateTime?> _lastResubscribeAtNotifier =
      ValueNotifier<DateTime?>(null);
  ValueListenable<DateTime?> get lastResubscribeAtNotifier =>
      _lastResubscribeAtNotifier;

  /// Last time we escalated to a full pipeline restart (stop + start of the
  /// foreground service). Null if we have never had to do one.
  DateTime? _lastPipelineRestartAt;
  DateTime? get lastPipelineRestartAt => _lastPipelineRestartAt;

  final ValueNotifier<DateTime?> _lastPipelineRestartAtNotifier =
      ValueNotifier<DateTime?>(null);
  ValueListenable<DateTime?> get lastPipelineRestartAtNotifier =>
      _lastPipelineRestartAtNotifier;

  /// Count of consecutive reconnect attempts that did NOT result in an
  /// `isSubscribed == true` listener. Reset to 0 on any success. When this
  /// crosses [kConsecutiveFailThresholdForRestart] we escalate to a pipeline
  /// restart (throttled by [kMinPipelineRestartInterval]).
  int _consecutiveReconnectFailures = 0;

  /// Set once [start] has been called. Used to implement the fresh-start grace
  /// period for the [CaptureHealthStatus.healthy] verdict.
  DateTime? _startedAt;

  Timer? _timer;
  bool _hydrated = false;
  bool _checking = false;

  /// Weak reference to the notification source — so the monitor can ask it to
  /// re-subscribe. Set by the orchestrator every time it builds a new source.
  NotificationCaptureSource? _notifSource;

  final ValueNotifier<CaptureHealthStatus> _statusNotifier =
      ValueNotifier<CaptureHealthStatus>(CaptureHealthStatus.unknown);

  /// Reactive status for the UI.
  ValueListenable<CaptureHealthStatus> get statusNotifier => _statusNotifier;

  /// Current status snapshot.
  CaptureHealthStatus get status => _statusNotifier.value;

  /// Convenience for the banner: is the stream currently subscribed at the
  /// Dart level? Falls back to `false` if we have no source bound.
  bool get isSubscribed => _notifSource?.isSubscriptionAlive ?? false;

  /// Register the notification source whose subscription we should watch.
  ///
  /// Idempotent: passing the same source twice is a no-op. Passing a new
  /// source replaces the previous one.
  void bindNotificationSource(NotificationCaptureSource source) {
    _notifSource = source;
  }

  /// Clear the bound source. Called when the orchestrator stops all sources.
  void unbindNotificationSource() {
    _notifSource = null;
  }

  /// Start the periodic health check. Safe to call multiple times —
  /// the existing timer is reused if one is already running.
  Future<void> start() async {
    if (_timer != null) return; // Already running — idempotent.
    _startedAt = DateTime.now();
    await _hydrate();
    // Run one immediate tick so the UI doesn't sit on `unknown`.
    unawaited(_tick());
    _timer = Timer.periodic(kMonitorInterval, (_) => _tick());
  }

  /// Stop the periodic health check and release the bound source.
  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    _startedAt = null;
    unbindNotificationSource();
  }

  /// Called by [NotificationCaptureSource] for every inbound event, BEFORE
  /// allowlist filtering — this is the strongest liveness signal we have.
  void markEvent() {
    final now = DateTime.now();
    _lastEventAt = now;
    unawaited(_persist(key: _prefsLastEventAt, value: now));
    // Fast path: if we were stale/unsubscribed the UI should flip green now.
    _recomputeStatus();
  }

  /// Called by [CaptureOrchestrator] when a proposal is successfully parsed.
  void markSuccess() {
    final now = DateTime.now();
    _lastSuccessAt = now;
    unawaited(_persist(key: _prefsLastSuccessAt, value: now));
  }

  /// Force an immediate health check + re-subscribe attempt. Called by the
  /// UI when the user taps the health banner.
  Future<void> forceCheck() => _tick(forceResubscribe: true);

  /// User-triggered deep repair cascade. Unlike [forceCheck] which is just an
  /// on-demand version of the regular timer tick, this method escalates
  /// proactively:
  ///
  ///   1. Re-run the [PermissionCoordinator] check (permissions may have
  ///      been granted in system settings while the app was in background).
  ///   2. Force re-subscribe the native notification stream.
  ///   3. If the listener is still not subscribed, bounce the whole
  ///      foreground service (stop + start). This is the nuclear option and
  ///      is what the user actually wants when they tap "Repair listener"
  ///      in despair.
  ///
  /// Returns `true` if, at the end of the cascade, the listener looks
  /// healthy (subscribed + permissions OK). Returns `false` if something is
  /// still wrong — the UI can use that to show a follow-up hint.
  ///
  /// Unlike the automatic escalation path, the pipeline-restart here is
  /// NOT throttled: the user is explicitly asking for it, so their
  /// intent overrides the 1 h guard.
  Future<bool> repairNow() async {
    final now = DateTime.now();
    CaptureEventLog.instance.log(CaptureEvent(
      id: generateUUID(),
      timestamp: now,
      source: CaptureEventSource.notification,
      content: 'Reparación manual solicitada desde la UI',
      status: CaptureEventStatus.systemEvent,
      reason: 'manual-repair',
    ));

    // Step 1: re-check permissions.
    try {
      await PermissionCoordinator.instance.check();
    } catch (e) {
      debugPrint('CaptureHealthMonitor: repair permission check error: $e');
    }

    // Step 2: force re-subscribe. Reuses _tryResubscribe so the event log
    // stays consistent and the consecutive-failure counter still tracks.
    await _tryResubscribe(reason: 'manual-repair');

    // Quick read of the resulting state so step 3 has accurate data.
    final src = _notifSource;
    final subscribed = src?.isSubscriptionAlive ?? false;

    // Step 3: if still broken, bounce the whole service. Skip the 1h
    // throttle because the user is driving.
    if (!subscribed) {
      CaptureEventLog.instance.log(CaptureEvent(
        id: generateUUID(),
        timestamp: DateTime.now(),
        source: CaptureEventSource.notification,
        content:
            'Listener sigue desconectado tras reintento — reiniciando servicio',
        status: CaptureEventStatus.systemEvent,
        reason: 'manual-repair: escalada a stop+start',
      ));
      try {
        await WallexBackgroundService.instance.stopService();
        await WallexBackgroundService.instance.startService();
        final stamp = DateTime.now();
        _lastPipelineRestartAt = stamp;
        _lastPipelineRestartAtNotifier.value = stamp;
        unawaited(_persist(key: _prefsLastPipelineRestartAt, value: stamp));
        _consecutiveReconnectFailures = 0;
      } catch (e) {
        debugPrint('CaptureHealthMonitor: manual repair restart error: $e');
      }
    }

    // Final health snapshot.
    await _tick();
    return status == CaptureHealthStatus.healthy;
  }

  Future<void> _hydrate() async {
    if (_hydrated) return;
    _hydrated = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastEventMs = prefs.getInt(_prefsLastEventAt);
      final lastSuccessMs = prefs.getInt(_prefsLastSuccessAt);
      final lastResubscribeMs = prefs.getInt(_prefsLastResubscribeAt);
      final lastPipelineRestartMs =
          prefs.getInt(_prefsLastPipelineRestartAt);
      if (lastEventMs != null) {
        _lastEventAt = DateTime.fromMillisecondsSinceEpoch(lastEventMs);
      }
      if (lastSuccessMs != null) {
        _lastSuccessAt = DateTime.fromMillisecondsSinceEpoch(lastSuccessMs);
      }
      if (lastResubscribeMs != null) {
        _lastResubscribeAt = DateTime.fromMillisecondsSinceEpoch(
          lastResubscribeMs,
        );
        _lastResubscribeAtNotifier.value = _lastResubscribeAt;
      }
      if (lastPipelineRestartMs != null) {
        _lastPipelineRestartAt = DateTime.fromMillisecondsSinceEpoch(
          lastPipelineRestartMs,
        );
        _lastPipelineRestartAtNotifier.value = _lastPipelineRestartAt;
      }
    } catch (e) {
      debugPrint('CaptureHealthMonitor: hydrate error: $e');
    }
  }

  Future<void> _persist({
    required String key,
    required DateTime value,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(key, value.millisecondsSinceEpoch);
    } catch (e) {
      debugPrint('CaptureHealthMonitor: persist error: $e');
    }
  }

  Future<void> _tick({bool forceResubscribe = false}) async {
    if (_checking) return;
    _checking = true;
    try {
      final hasListenerPermission = await _checkPermission();
      // Consult the permission coordinator for the wider picture (listener +
      // POST_NOTIFICATIONS + battery-opt whitelist). The health monitor is
      // the single authority behind the UI banner, so any critical permission
      // missing flips us to `permissionMissing` regardless of what the native
      // listener itself reports.
      final permsState = await _safePermissionCheck();
      final subscribed = isSubscribed;
      final now = DateTime.now();
      final lastEvent = _lastEventAt;
      final freshStart =
          _startedAt != null && now.difference(_startedAt!) < kFreshStartGrace;
      final stale = lastEvent == null
          ? !freshStart
          : now.difference(lastEvent) >= kStaleEventThreshold;

      // Rate-limited warning: battery optimizations on and listener is
      // running. Doesn't block critical-grant but gives diagnostic breadcrumb.
      if (permsState != null &&
          !permsState.batteryOptimizationsIgnored &&
          hasListenerPermission) {
        unawaited(_maybeWarnBatteryOptimization());
      }

      if (!hasListenerPermission ||
          (permsState != null && !permsState.allCriticalGranted)) {
        _setStatus(CaptureHealthStatus.permissionMissing);
        return;
      }

      if (!subscribed) {
        _setStatus(CaptureHealthStatus.unsubscribed);
        await _tryResubscribe(reason: 'unsubscribed');
        return;
      }

      if (stale) {
        _setStatus(CaptureHealthStatus.stale);
        // Always re-subscribe when stale. Requiring a previous event can trap
        // us in a dead-on-arrival state on some OEMs.
        await _tryResubscribe(reason: 'stale');
        return;
      }

      _setStatus(CaptureHealthStatus.healthy);

      if (forceResubscribe) {
        await _tryResubscribe(reason: 'user-forced');
      } else {
        await _maybeProactiveResubscribe(now);
      }

      // Opportunistic daily chore: prune the fingerprint registry so it
      // doesn't grow without bound. Cheap — the registry caps itself at
      // 500 entries anyway, but pruning earlier keeps disk writes small.
      unawaited(_maybePruneFingerprints());
    } catch (e) {
      debugPrint('CaptureHealthMonitor: tick error: $e');
    } finally {
      _checking = false;
    }
  }

  Future<void> _maybePruneFingerprints() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastMs = prefs.getInt(_prefsLastFpPruneAt);
      final now = DateTime.now();
      if (lastMs != null) {
        final last = DateTime.fromMillisecondsSinceEpoch(lastMs);
        if (now.difference(last) < _fpPruneInterval) return;
      }
      await prefs.setInt(_prefsLastFpPruneAt, now.millisecondsSinceEpoch);
      await FingerprintRegistry.instance.pruneOlderThan(_fpPruneMaxAge);
    } catch (e) {
      debugPrint('CaptureHealthMonitor: fingerprint prune error: $e');
    }
  }

  Future<void> _maybeProactiveResubscribe(DateTime now) async {
    // Avoid aggressive churn right after startup.
    if (_startedAt != null && now.difference(_startedAt!) < kFreshStartGrace) {
      return;
    }

    final last = _lastResubscribeAt;
    if (last != null && now.difference(last) < kProactiveReconnectInterval) {
      return;
    }

    await _tryResubscribe(reason: 'proactive-refresh');
  }

  Future<bool> _checkPermission() async {
    final src = _notifSource;
    try {
      if (src != null) {
        return await src.hasPermission();
      }
      // Fallback: no source bound yet — query the plugin directly.
      return await NotificationListenerService.isPermissionGranted();
    } catch (e) {
      debugPrint('CaptureHealthMonitor: permission check error: $e');
      return false;
    }
  }

  /// Consult [PermissionCoordinator] for the full permissions snapshot.
  /// Returns `null` if the lookup throws — the caller then falls back to
  /// the legacy listener-only check and we don't artificially flip the
  /// banner red on a transient error.
  Future<CapturePermissionsState?> _safePermissionCheck() async {
    try {
      return await PermissionCoordinator.instance.check();
    } catch (e) {
      debugPrint('CaptureHealthMonitor: coordinator check error: $e');
      return null;
    }
  }

  /// Log a warning about the app not being in the battery-optimization
  /// whitelist, rate-limited to once per [_batteryWarnInterval] to keep the
  /// diagnostic buffer useful.
  Future<void> _maybeWarnBatteryOptimization() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastMs = prefs.getInt(_prefsLastBatteryWarnAt);
      final now = DateTime.now();
      if (lastMs != null) {
        final last = DateTime.fromMillisecondsSinceEpoch(lastMs);
        if (now.difference(last) < _batteryWarnInterval) return;
      }
      await prefs.setInt(_prefsLastBatteryWarnAt, now.millisecondsSinceEpoch);
      CaptureEventLog.instance.log(CaptureEvent(
        id: generateUUID(),
        timestamp: now,
        source: CaptureEventSource.notification,
        content: 'Wallex no está en la lista blanca de optimización de batería.',
        status: CaptureEventStatus.systemEvent,
        reason: 'El sistema puede matar el foreground service en Doze. '
            'Sugerir al usuario que abra la pantalla de permisos.',
      ));
    } catch (e) {
      debugPrint('CaptureHealthMonitor: battery warn error: $e');
    }
  }

  Future<void> _tryResubscribe({required String reason}) async {
    final src = _notifSource;
    if (src == null) return;
    bool succeeded = false;
    try {
      await src.ensureSubscribed(forceReconnect: true);
      // ensureSubscribed can silently return without flipping
      // `isSubscriptionAlive` true on some OEMs where the native bind is
      // wedged. Treat that as a failure for escalation purposes even though
      // no exception was thrown.
      succeeded = src.isSubscriptionAlive;
      final now = DateTime.now();
      _lastResubscribeAt = now;
      _lastResubscribeAtNotifier.value = now;
      unawaited(_persist(key: _prefsLastResubscribeAt, value: now));
      CaptureEventLog.instance.log(CaptureEvent(
        id: generateUUID(),
        timestamp: now,
        source: CaptureEventSource.notification,
        content: succeeded
            ? 'Health monitor reconectó listener (motivo: $reason)'
            : 'Reconexión de listener completó sin error pero '
                'isSubscribed=false (motivo: $reason)',
        status: CaptureEventStatus.systemEvent,
        reason: 'Reintento automatico de suscripcion al stream nativo',
      ));
    } catch (e) {
      debugPrint('CaptureHealthMonitor: resubscribe error: $e');
      CaptureEventLog.instance.log(CaptureEvent(
        id: generateUUID(),
        timestamp: DateTime.now(),
        source: CaptureEventSource.notification,
        content: 'Fallo al reconectar listener: $e',
        status: CaptureEventStatus.systemEvent,
        reason: 'Excepcion en ensureSubscribed() (motivo: $reason)',
      ));
    }

    if (succeeded) {
      _consecutiveReconnectFailures = 0;
      return;
    }

    _consecutiveReconnectFailures += 1;
    if (_consecutiveReconnectFailures >= kConsecutiveFailThresholdForRestart) {
      await _maybeRestartPipeline(
        reason: 'pipeline-restart-after-$_consecutiveReconnectFailures-fails',
      );
    }
  }

  /// Escalation path: the soft re-subscribe cycle has failed repeatedly, so
  /// bounce the whole foreground service. This makes the plugin re-create its
  /// isolate + re-run `CaptureOrchestrator.applySettings()` from scratch,
  /// which is the only way to recover when MIUI has suspended the native
  /// binder at the OS level.
  ///
  /// Throttled by [kMinPipelineRestartInterval] so we can't end up in a
  /// tight loop if the service itself can't be restarted (e.g. the OEM
  /// autostart permission was revoked and stopService() + startService()
  /// keeps returning immediately).
  Future<void> _maybeRestartPipeline({required String reason}) async {
    final now = DateTime.now();
    final last = _lastPipelineRestartAt;
    if (last != null &&
        now.difference(last) < kMinPipelineRestartInterval) {
      debugPrint(
        'CaptureHealthMonitor: skip pipeline restart — throttled '
        '(last=${last.toIso8601String()})',
      );
      return;
    }

    CaptureEventLog.instance.log(CaptureEvent(
      id: generateUUID(),
      timestamp: now,
      source: CaptureEventSource.notification,
      content:
          'Reiniciando pipeline de captura tras fallos consecutivos ($reason)',
      status: CaptureEventStatus.systemEvent,
      reason: 'Escalada automatica: stopService() + startService()',
    ));

    try {
      await WallexBackgroundService.instance.stopService();
      await WallexBackgroundService.instance.startService();
    } catch (e) {
      debugPrint('CaptureHealthMonitor: pipeline restart error: $e');
      CaptureEventLog.instance.log(CaptureEvent(
        id: generateUUID(),
        timestamp: DateTime.now(),
        source: CaptureEventSource.notification,
        content: 'Fallo al reiniciar pipeline: $e',
        status: CaptureEventStatus.systemEvent,
        reason: 'Excepcion en stopService()/startService()',
      ));
    }

    // Update the timestamp regardless of outcome — the throttle must apply
    // even to failed attempts so we don't hammer the plugin.
    _lastPipelineRestartAt = now;
    _lastPipelineRestartAtNotifier.value = now;
    unawaited(_persist(key: _prefsLastPipelineRestartAt, value: now));

    // Reset the counter so the next cycle is measured fresh.
    _consecutiveReconnectFailures = 0;
  }

  void _recomputeStatus() {
    // Lightweight recompute, no permission check — called from the hot path
    // (markEvent). The next timer tick will do the full audit.
    if (isSubscribed) {
      _setStatus(CaptureHealthStatus.healthy);
    }
  }

  void _setStatus(CaptureHealthStatus status) {
    if (_statusNotifier.value == status) return;
    _statusNotifier.value = status;
  }
}
