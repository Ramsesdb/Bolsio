import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kilatex/core/services/auto_import/capture/models/capture_event.dart';

/// Simple counter bag over a window of [CaptureEvent]s.
@immutable
class CaptureEventCounters {
  final int received;
  final int parsedSuccess;
  final int parsedFailed;
  final int filteredOut;
  final int duplicate;

  const CaptureEventCounters({
    required this.received,
    required this.parsedSuccess,
    required this.parsedFailed,
    required this.filteredOut,
    required this.duplicate,
  });

  static const empty = CaptureEventCounters(
    received: 0,
    parsedSuccess: 0,
    parsedFailed: 0,
    filteredOut: 0,
    duplicate: 0,
  );
}

/// In-memory ring buffer of recent diagnostic [CaptureEvent]s, with best-effort
/// persistence of the last 100 entries to [SharedPreferences].
///
/// Singleton — the orchestrator and the diagnostics page both talk to it
/// through [instance].
class CaptureEventLog {
  static const int _bufferSize = 200;
  static const int _persistSize = 100;
  static const String _prefsKey = 'capture_event_log';

  static final CaptureEventLog instance = CaptureEventLog._();

  CaptureEventLog._();

  /// Events ordered oldest -> newest (ring buffer semantics).
  final List<CaptureEvent> _events = [];

  final ValueNotifier<List<CaptureEvent>> _notifier =
      ValueNotifier<List<CaptureEvent>>(const []);

  bool _hydrated = false;
  bool _hydrating = false;

  /// Reactive view of the buffer (newest last in the underlying list, but the
  /// public view returns an unmodifiable copy for UI consumption).
  ValueListenable<List<CaptureEvent>> get listenable => _notifier;

  /// Current snapshot of the buffer.
  List<CaptureEvent> get events => List.unmodifiable(_notifier.value);

  /// Load the last persisted events into memory. Safe to call multiple times.
  Future<void> hydrate() async {
    if (_hydrated || _hydrating) return;
    _hydrating = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          final restored = <CaptureEvent>[];
          for (final entry in decoded) {
            if (entry is Map<String, dynamic>) {
              try {
                restored.add(CaptureEvent.fromJson(entry));
              } catch (e) {
                debugPrint('CaptureEventLog: skipping corrupt entry: $e');
              }
            }
          }
          _events
            ..clear()
            ..addAll(restored);
          _publish();
        }
      }
    } catch (e) {
      debugPrint('CaptureEventLog: hydrate error: $e');
    } finally {
      _hydrated = true;
      _hydrating = false;
    }
  }

  /// Append a new event. Fire-and-forget: if persistence fails the in-memory
  /// buffer still updates.
  void log(CaptureEvent event) {
    _events.add(event);
    if (_events.length > _bufferSize) {
      _events.removeRange(0, _events.length - _bufferSize);
    }
    _publish();
    unawaited(_persist());
  }

  /// Clear both the in-memory buffer and the persisted copy.
  Future<void> clear() async {
    _events.clear();
    _publish();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefsKey);
    } catch (e) {
      debugPrint('CaptureEventLog: clear persistence error: $e');
    }
  }

  /// Counters over the last 24 hours.
  CaptureEventCounters counters24h() {
    final cutoff = DateTime.now().subtract(const Duration(hours: 24));
    return _countersSince(cutoff);
  }

  /// Counters over the last 7 days.
  CaptureEventCounters counters7d() {
    final cutoff = DateTime.now().subtract(const Duration(days: 7));
    return _countersSince(cutoff);
  }

  CaptureEventCounters _countersSince(DateTime cutoff) {
    int received = 0;
    int parsedSuccess = 0;
    int parsedFailed = 0;
    int filteredOut = 0;
    int duplicate = 0;

    for (final e in _events) {
      if (e.timestamp.isBefore(cutoff)) continue;
      switch (e.status) {
        case CaptureEventStatus.received:
          received++;
          break;
        case CaptureEventStatus.parsedSuccess:
          parsedSuccess++;
          break;
        case CaptureEventStatus.parsedFailed:
          parsedFailed++;
          break;
        case CaptureEventStatus.filteredOut:
          filteredOut++;
          break;
        case CaptureEventStatus.duplicate:
          duplicate++;
          break;
        case CaptureEventStatus.systemEvent:
          // Internal lifecycle events do not feed any counter chip.
          break;
      }
    }

    return CaptureEventCounters(
      received: received,
      parsedSuccess: parsedSuccess,
      parsedFailed: parsedFailed,
      filteredOut: filteredOut,
      duplicate: duplicate,
    );
  }

  /// Serialize the last [limit] events as a JSON string — used by the "Copy
  /// diagnostic" button on the diagnostics screen.
  String exportJson({int limit = 50}) {
    final tail = _events.length <= limit
        ? List<CaptureEvent>.from(_events)
        : _events.sublist(_events.length - limit);
    final encoded = tail.map((e) => e.toJson()).toList();
    return const JsonEncoder.withIndent('  ').convert(encoded);
  }

  void _publish() {
    _notifier.value = List.unmodifiable(_events);
  }

  Future<void> _persist() async {
    try {
      final tail = _events.length <= _persistSize
          ? _events
          : _events.sublist(_events.length - _persistSize);
      final encoded = jsonEncode(tail.map((e) => e.toJson()).toList());
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, encoded);
    } catch (e) {
      debugPrint('CaptureEventLog: persist error: $e');
    }
  }
}
