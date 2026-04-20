import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'notif_fingerprint.dart';

/// Immutable snapshot of a previously observed notification.
@immutable
class SeenFingerprint {
  /// Full stable key (package + nativeId + postTime + contentHash).
  final String stable;

  /// Weaker key (package + contentHash) used to detect reposts with a
  /// different native id.
  final String contentOnly;

  final DateTime firstSeen;
  final DateTime lastSeen;
  final int occurrences;

  /// `id` of the pending import / transaction created from this notif, if any.
  /// Null when the notif was observed but parsing failed or was skipped.
  final String? linkedTransactionId;

  /// `true` once `onNotificationRemoved` fires for this notif. Does NOT erase
  /// the entry — the registry keeps it to recognise later reposts.
  final bool userRemoved;

  const SeenFingerprint({
    required this.stable,
    required this.contentOnly,
    required this.firstSeen,
    required this.lastSeen,
    required this.occurrences,
    required this.linkedTransactionId,
    required this.userRemoved,
  });

  SeenFingerprint copyWith({
    String? stable,
    String? contentOnly,
    DateTime? firstSeen,
    DateTime? lastSeen,
    int? occurrences,
    String? linkedTransactionId,
    bool? userRemoved,
  }) {
    return SeenFingerprint(
      stable: stable ?? this.stable,
      contentOnly: contentOnly ?? this.contentOnly,
      firstSeen: firstSeen ?? this.firstSeen,
      lastSeen: lastSeen ?? this.lastSeen,
      occurrences: occurrences ?? this.occurrences,
      linkedTransactionId: linkedTransactionId ?? this.linkedTransactionId,
      userRemoved: userRemoved ?? this.userRemoved,
    );
  }

  Map<String, dynamic> toJson() => {
        'stable': stable,
        'contentOnly': contentOnly,
        'firstSeen': firstSeen.toIso8601String(),
        'lastSeen': lastSeen.toIso8601String(),
        'occurrences': occurrences,
        'linkedTransactionId': linkedTransactionId,
        'userRemoved': userRemoved,
      };

  static SeenFingerprint? fromJson(Map<String, dynamic> json) {
    try {
      return SeenFingerprint(
        stable: json['stable'] as String? ?? '',
        contentOnly: json['contentOnly'] as String? ?? '',
        firstSeen: DateTime.parse(
          json['firstSeen'] as String? ?? DateTime.now().toIso8601String(),
        ),
        lastSeen: DateTime.parse(
          json['lastSeen'] as String? ?? DateTime.now().toIso8601String(),
        ),
        occurrences: (json['occurrences'] as num?)?.toInt() ?? 1,
        linkedTransactionId: json['linkedTransactionId'] as String?,
        userRemoved: json['userRemoved'] as bool? ?? false,
      );
    } catch (e) {
      return null;
    }
  }
}

/// Persistent registry of recently seen [NotifFingerprint]s.
///
/// Backed by [SharedPreferences] — a single JSON array under [_prefsKey].
/// Keeps an in-memory map mirroring the persisted state so that [lookup]
/// is O(1) for the hot path of every inbound notification.
///
/// Not concurrency-safe across isolates (auto-import runs in the main or
/// foreground isolate, never simultaneously on both).
class FingerprintRegistry {
  static const String _prefsKey = 'capture_fingerprint_registry_v1';
  static const int _softCap = 500;

  /// Default window for [lookup] — beyond 7 days we stop matching even if
  /// the fingerprint happens to still be in the store.
  static const Duration _lookupWindow = Duration(days: 7);

  /// Default window for `contentOnly` matching when the native id changed —
  /// kept tighter than [_lookupWindow] because different id + old time is
  /// very likely a distinct event.
  static const Duration _contentOnlyWindow = Duration(hours: 24);

  static final FingerprintRegistry instance = FingerprintRegistry._();

  FingerprintRegistry._();

  /// Indexed by `stable` — newest wins on collision.
  final Map<String, SeenFingerprint> _byStable = {};

  /// Indexed by `contentOnly` — newest wins on collision.
  final Map<String, SeenFingerprint> _byContent = {};

  bool _hydrated = false;
  bool _hydrating = false;

  /// Mutex-lite — we only have one writer at a time on the capture hot path.
  Future<void>? _pendingPersist;

  /// Ensure the in-memory cache is loaded from disk. Safe to call multiple
  /// times. `await`ing this once at start-of-day is enough; subsequent
  /// callers hit the fast path.
  Future<void> hydrate() async {
    if (_hydrated || _hydrating) return;
    _hydrating = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      _byStable.clear();
      _byContent.clear();
      for (final entry in decoded) {
        if (entry is! Map) continue;
        final parsed = SeenFingerprint.fromJson(
          entry.map((k, v) => MapEntry(k.toString(), v)),
        );
        if (parsed == null) continue;
        if (parsed.stable.isNotEmpty) _byStable[parsed.stable] = parsed;
        if (parsed.contentOnly.isNotEmpty) {
          // Keep the newest entry under the contentOnly key.
          final existing = _byContent[parsed.contentOnly];
          if (existing == null || existing.lastSeen.isBefore(parsed.lastSeen)) {
            _byContent[parsed.contentOnly] = parsed;
          }
        }
      }
    } catch (e) {
      debugPrint('FingerprintRegistry: hydrate error: $e');
    } finally {
      _hydrated = true;
      _hydrating = false;
    }
  }

  /// Look up a fingerprint.
  ///
  /// Strategy:
  /// 1. Exact `stable` match within [_lookupWindow] → returns it as-is.
  /// 2. Else `contentOnly` match within [_contentOnlyWindow] → returns it.
  /// 3. Else `null`.
  Future<SeenFingerprint?> lookup(NotifFingerprint fp) async {
    await hydrate();
    final now = DateTime.now();

    final byStable = _byStable[fp.stable];
    if (byStable != null &&
        now.difference(byStable.lastSeen) <= _lookupWindow) {
      return byStable;
    }

    final byContent = _byContent[fp.contentOnly];
    if (byContent != null &&
        now.difference(byContent.lastSeen) <= _contentOnlyWindow) {
      return byContent;
    }

    return null;
  }

  /// Upsert a fingerprint.
  ///
  /// Idempotent — calling with the same [fp] twice only bumps `lastSeen`
  /// and `occurrences`. If a [transactionId] is provided on a subsequent
  /// call, it overwrites a previously-null link (useful when the first
  /// call happens before the tx is persisted).
  Future<void> markSeen(
    NotifFingerprint fp, {
    String? transactionId,
  }) async {
    await hydrate();
    final now = DateTime.now();
    final existing = _byStable[fp.stable] ?? _byContent[fp.contentOnly];

    final SeenFingerprint upserted;
    if (existing == null) {
      upserted = SeenFingerprint(
        stable: fp.stable,
        contentOnly: fp.contentOnly,
        firstSeen: now,
        lastSeen: now,
        occurrences: 1,
        linkedTransactionId: transactionId,
        userRemoved: false,
      );
    } else {
      upserted = existing.copyWith(
        stable: fp.stable,
        contentOnly: fp.contentOnly,
        lastSeen: now,
        occurrences: existing.occurrences + 1,
        linkedTransactionId:
            transactionId ?? existing.linkedTransactionId,
      );
    }

    _byStable[upserted.stable] = upserted;
    _byContent[upserted.contentOnly] = upserted;
    _enforceSoftCap();
    _schedulePersist();
  }

  /// Mark a fingerprint as user-removed. Does NOT delete — the registry
  /// keeps the entry so we can still detect later reposts.
  Future<void> markRemoved(NotifFingerprint fp) async {
    await hydrate();
    final now = DateTime.now();
    final existing = _byStable[fp.stable] ?? _byContent[fp.contentOnly];

    final SeenFingerprint upserted;
    if (existing == null) {
      upserted = SeenFingerprint(
        stable: fp.stable,
        contentOnly: fp.contentOnly,
        firstSeen: now,
        lastSeen: now,
        occurrences: 1,
        linkedTransactionId: null,
        userRemoved: true,
      );
    } else {
      upserted = existing.copyWith(
        lastSeen: now,
        userRemoved: true,
      );
    }

    _byStable[upserted.stable] = upserted;
    _byContent[upserted.contentOnly] = upserted;
    _enforceSoftCap();
    _schedulePersist();
  }

  /// Drop entries whose `lastSeen` is older than [age]. Called from the
  /// health monitor once per day to keep the on-disk payload bounded.
  Future<void> pruneOlderThan(Duration age) async {
    await hydrate();
    final cutoff = DateTime.now().subtract(age);
    final before = _byStable.length;
    _byStable.removeWhere((_, v) => v.lastSeen.isBefore(cutoff));
    // Rebuild content index from the surviving set to avoid dangling keys.
    _byContent.clear();
    for (final v in _byStable.values) {
      if (v.contentOnly.isEmpty) continue;
      final existing = _byContent[v.contentOnly];
      if (existing == null || existing.lastSeen.isBefore(v.lastSeen)) {
        _byContent[v.contentOnly] = v;
      }
    }
    final after = _byStable.length;
    if (before != after) {
      _schedulePersist();
      debugPrint(
        'FingerprintRegistry: pruned ${before - after} entries older than $age',
      );
    }
  }

  /// Testing / diagnostics helper: snapshot of the current cache.
  @visibleForTesting
  List<SeenFingerprint> debugEntries() => List.unmodifiable(_byStable.values);

  /// Testing helper: reset the in-memory + persisted state.
  @visibleForTesting
  Future<void> debugClear() async {
    _byStable.clear();
    _byContent.clear();
    _hydrated = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefsKey);
    } catch (_) {}
  }

  void _enforceSoftCap() {
    if (_byStable.length <= _softCap) return;
    // Drop the oldest-by-lastSeen entries until we're back at the cap.
    final sorted = _byStable.values.toList()
      ..sort((a, b) => a.lastSeen.compareTo(b.lastSeen));
    final toRemove = _byStable.length - _softCap;
    for (int i = 0; i < toRemove; i++) {
      final drop = sorted[i];
      _byStable.remove(drop.stable);
      final inContent = _byContent[drop.contentOnly];
      if (inContent != null && inContent.stable == drop.stable) {
        _byContent.remove(drop.contentOnly);
      }
    }
  }

  void _schedulePersist() {
    // Coalesce bursts of writes.
    _pendingPersist ??= Future<void>.microtask(() async {
      try {
        await _persist();
      } finally {
        _pendingPersist = null;
      }
    });
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final snapshot = _byStable.values.map((e) => e.toJson()).toList();
      await prefs.setString(_prefsKey, jsonEncode(snapshot));
    } catch (e) {
      debugPrint('FingerprintRegistry: persist error: $e');
    }
  }
}
