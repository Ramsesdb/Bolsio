import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:notification_listener_service/notification_listener_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wallex/core/services/auto_import/capture/capture_event_log.dart';
import 'package:wallex/core/services/auto_import/capture/models/capture_event.dart';
import 'package:wallex/core/services/auto_import/capture/notification_capture_source.dart';
import 'package:wallex/core/services/auto_import/capture/permission_coordinator.dart';
import 'package:wallex/core/services/auto_import/dedupe/fingerprint_registry.dart';
import 'package:wallex/core/utils/uuid.dart';

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
/// 24 hours is a reasonable window for a bank notification listener — most
/// users at least get a balance / push at that cadence. Set to 2 minutes
/// temporarily for manual QA of the stale banner.
const Duration kStaleEventThreshold = Duration(hours: 24);

/// Grace period after (re)starting the monitor during which we report
/// [CaptureHealthStatus.healthy] even without any events yet.
const Duration kFreshStartGrace = Duration(minutes: 5);

/// How often the monitor wakes up to re-evaluate health and (optionally)
/// re-subscribe. Kept at 60 s as a compromise between responsiveness and
/// wakelock / battery usage inside the foreground service isolate.
const Duration kMonitorInterval = Duration(seconds: 60);

/// Singleton that watches the liveness of the capture pipeline and tries to
/// auto-heal it by re-subscribing the native stream when needed.
class CaptureHealthMonitor {
  static final CaptureHealthMonitor instance = CaptureHealthMonitor._();

  CaptureHealthMonitor._();

  static const String _prefsLastEventAt = 'capture_health_last_event_at';
  static const String _prefsLastSuccessAt = 'capture_health_last_success_at';
  static const String _prefsLastBatteryWarnAt = 'capture_health_last_battery_warn_at';
  static const String _prefsLastFpPruneAt = 'capture_health_last_fp_prune_at';

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

  Future<void> _hydrate() async {
    if (_hydrated) return;
    _hydrated = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastEventMs = prefs.getInt(_prefsLastEventAt);
      final lastSuccessMs = prefs.getInt(_prefsLastSuccessAt);
      if (lastEventMs != null) {
        _lastEventAt = DateTime.fromMillisecondsSinceEpoch(lastEventMs);
      }
      if (lastSuccessMs != null) {
        _lastSuccessAt = DateTime.fromMillisecondsSinceEpoch(lastSuccessMs);
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
        // Preventive toggle: only if we had at least one healthy event before.
        if (lastEvent != null || forceResubscribe) {
          await _tryResubscribe(reason: 'stale');
        }
        return;
      }

      _setStatus(CaptureHealthStatus.healthy);

      if (forceResubscribe) {
        await _tryResubscribe(reason: 'user-forced');
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
    try {
      await src.ensureSubscribed(forceReconnect: true);
      CaptureEventLog.instance.log(CaptureEvent(
        id: generateUUID(),
        timestamp: DateTime.now(),
        source: CaptureEventSource.notification,
        content: 'Health monitor reconectó listener (motivo: $reason)',
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
