import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:rxdart/rxdart.dart';
import 'package:kilatex/app/home/dashboard_widgets/models/dashboard_layout.dart';
import 'package:kilatex/app/home/dashboard_widgets/models/migrator.dart';
import 'package:kilatex/app/home/dashboard_widgets/models/widget_descriptor.dart';
import 'package:kilatex/core/database/services/user-setting/user_setting_service.dart';
import 'package:kilatex/core/utils/debouncer.dart';
import 'package:kilatex/core/utils/logger.dart';

/// Singleton service that owns the in-memory copy of the dashboard layout
/// and persists changes to `SettingKey.dashboardLayout` (debounced 300 ms).
///
/// Architecture (see `dashboard-layout` § Persistencia + design.md ADR-1, 3):
///   - One [BehaviorSubject] seeded with [DashboardLayout.empty]. Consumers
///     subscribe via [stream] and read [current] synchronously.
///   - [save] coalesces rapid edits into a single DB write via a 300 ms
///     [Debouncer]. [flush] forces an immediate write — used on edit-mode
///     exit, sheet close, and `AppLifecycleState.paused`.
///   - Mutations (`add`, `removeByInstanceId`, `reorder`, `updateConfig`,
///     `resetToFallback`) update the subject immediately so the UI re-renders
///     synchronously, then schedule a debounced write to disk.
///   - All persistence goes through [UserSettingService] so Firebase sync
///     happens automatically (the layout is NOT in
///     `_userSettingsSyncExclusions`).
class DashboardLayoutService {
  DashboardLayoutService._()
    : _userSettingServiceOverride = null,
      _writerOverride = null,
      _debounceMs = 300;

  static final DashboardLayoutService instance = DashboardLayoutService._();

  /// Test-only constructor. Allows injecting a fake user-setting service or
  /// — preferred for unit tests that just need to verify debounce/persist
  /// semantics — a [writer] callback that replaces the real DB write.
  ///
  /// Pass either:
  ///   - [userSettingService] → full service substitute (rarely useful in
  ///     unit tests because the real class requires a Drift DB).
  ///   - [writer] → simple `Future<void> Function(String encoded)` invoked
  ///     instead of `setItem`. Recommended path for the test suite.
  @visibleForTesting
  DashboardLayoutService.forTesting({
    UserSettingService? userSettingService,
    Future<void> Function(String encoded)? writer,
    int debounceMs = 300,
  }) : _userSettingServiceOverride = userSettingService,
       _writerOverride = writer,
       _debounceMs = debounceMs;

  final UserSettingService? _userSettingServiceOverride;
  final Future<void> Function(String encoded)? _writerOverride;
  final int _debounceMs;

  UserSettingService get _userSettingService =>
      _userSettingServiceOverride ?? UserSettingService.instance;

  late final Debouncer _saveDebouncer = Debouncer(milliseconds: _debounceMs);

  /// `true` while [_saveDebouncer] has a pending write that has not yet
  /// flushed. Tracked separately because [Debouncer] does not expose its
  /// internal timer state.
  bool _hasPendingSave = false;

  /// Set when the loaded `schemaVersion` was higher than this binary
  /// understands. While `true`, the service refuses to persist (so a
  /// downgrade does NOT corrupt the stored payload). The flag flips off
  /// on the next [resetToFallback] / explicit user edit.
  bool _persistenceLocked = false;

  final BehaviorSubject<DashboardLayout> _controller =
      BehaviorSubject<DashboardLayout>.seeded(DashboardLayout.empty());

  /// Stream of layout snapshots. `distinct()` is intentionally omitted —
  /// callers that need it can layer it themselves; equality between two
  /// `DashboardLayout` objects is structural (deep map compare) and not
  /// worth the cost on every emission.
  Stream<DashboardLayout> get stream => _controller.stream;

  /// Synchronous view of the current layout. Always non-null.
  DashboardLayout get current => _controller.value;

  /// `true` when the persisted layout had a schemaVersion higher than this
  /// binary understands. The dashboard MUST apply fallback in that case
  /// (see spec scenario "schemaVersion futuro").
  bool get isFutureVersion => _persistenceLocked;

  // ─────────── Load / save / flush ───────────

  /// Read the layout from `SettingKey.dashboardLayout`, run migrations,
  /// dedup duplicate `instanceId`s, and emit on [stream].
  ///
  /// Behaviour:
  ///   - Empty/null/invalid JSON → emits empty layout, does NOT write back.
  ///   - Future schemaVersion → emits empty layout, sets [isFutureVersion],
  ///     does NOT write back (preserves user data for inspection).
  ///   - Migration applied / duplicates regenerated / unknown widgets
  ///     dropped → emits cleaned layout AND schedules a debounced save so
  ///     storage converges.
  Future<void> load() async {
    final raw = appStateSettings[SettingKey.dashboardLayout];
    if (raw == null || raw.isEmpty || raw == '[]') {
      _controller.add(DashboardLayout.empty());
      return;
    }

    Map<String, dynamic>? parsed;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        parsed = Map<String, dynamic>.from(decoded);
      } else if (decoded is List) {
        // Tolerate the seed shape `'[]'` (a bare list of widgets) for
        // forward-compat with users who hand-edit the DB.
        parsed = <String, dynamic>{
          'schemaVersion': DashboardLayout.currentSchemaVersion,
          'widgets': decoded,
        };
      }
    } on FormatException catch (e) {
      Logger.printDebug(
        '[DashboardLayoutService] Invalid JSON in dashboardLayout: $e. '
        'Falling back to empty layout (raw is preserved on disk).',
      );
    }

    if (parsed == null) {
      _controller.add(DashboardLayout.empty());
      return;
    }

    final result = DashboardLayoutMigrator.migrate(parsed);
    _persistenceLocked = result.isFutureVersion;
    _controller.add(result.layout);

    if (result.didMutate && !result.isFutureVersion) {
      // Schedule a write so the on-disk JSON converges to the latest
      // schema. Debounced — multiple loads in quick succession (rare)
      // collapse into a single write.
      _scheduleSave();
    }
  }

  /// Replace the current layout and schedule a debounced write to disk.
  ///
  /// Most callers do NOT call [save] directly: the mutation helpers
  /// (`add`, `removeByInstanceId`, `reorder`, `updateConfig`,
  /// `resetToFallback`) already do so. [save] is exposed for the special
  /// case where the caller computed a new layout outside of these helpers
  /// (e.g. onboarding's `_applyChoices` pre-seed via `setItem` directly,
  /// or a future "import from JSON" feature).
  void save(DashboardLayout layout) {
    _controller.add(layout);
    _scheduleSave();
  }

  /// Force an immediate write. Cancels the pending debounce and persists
  /// the current value synchronously (within Flutter's microtask queue).
  /// Used on edit-mode exit, sheet close, and `AppLifecycleState.paused`.
  Future<void> flush() async {
    if (!_hasPendingSave) return;
    _hasPendingSave = false;
    await _writeNow();
  }

  void _scheduleSave() {
    if (_persistenceLocked) {
      Logger.printDebug(
        '[DashboardLayoutService] Persistence locked (future schemaVersion). '
        'Skipping save.',
      );
      return;
    }
    _hasPendingSave = true;
    _saveDebouncer.run(() {
      _hasPendingSave = false;
      // Fire-and-forget: errors are logged inside _writeNow.
      // ignore: discarded_futures
      _writeNow();
    });
  }

  Future<void> _writeNow() async {
    try {
      final encoded = jsonEncode(current.toJson());
      final writer = _writerOverride;
      if (writer != null) {
        await writer(encoded);
        return;
      }
      await _userSettingService.setItem(
        SettingKey.dashboardLayout,
        encoded,
        updateGlobalState: true,
      );
    } catch (e) {
      Logger.printDebug(
        '[DashboardLayoutService] Error persisting layout: $e',
      );
    }
  }

  // ─────────── Mutations ───────────

  /// Append [descriptor] to the end of the layout and schedule a save.
  /// Caller is responsible for enforcing uniqueness rules
  /// (`DashboardWidgetSpec.unique`); this method does NOT validate.
  void add(WidgetDescriptor descriptor) {
    final next = List<WidgetDescriptor>.from(current.widgets)..add(descriptor);
    _controller.add(current.copyWith(widgets: next));
    _scheduleSave();
  }

  /// Remove the descriptor with the given [instanceId]. No-op when not
  /// found.
  void removeByInstanceId(String instanceId) {
    final next = current.widgets
        .where((w) => w.instanceId != instanceId)
        .toList(growable: false);
    if (next.length == current.widgets.length) return;
    _controller.add(current.copyWith(widgets: next));
    _scheduleSave();
  }

  /// Reorder the widget at index [from] to index [to] (`ReorderableListView`
  /// semantics: when [to] > [from], the index is post-removal). No-op when
  /// indices are out of range or equal.
  void reorder(int from, int to) {
    final widgets = current.widgets;
    if (from < 0 || from >= widgets.length) return;
    if (to < 0 || to > widgets.length) return;
    if (from == to) return;

    final next = List<WidgetDescriptor>.from(widgets);
    final moved = next.removeAt(from);
    final insertAt = to > from ? to - 1 : to;
    next.insert(insertAt, moved);
    _controller.add(current.copyWith(widgets: next));
    _scheduleSave();
  }

  /// Replace the `config` map of the widget with the given [instanceId].
  /// No-op when not found.
  void updateConfig(String instanceId, Map<String, dynamic> config) {
    final widgets = current.widgets;
    var changed = false;
    final next = <WidgetDescriptor>[];
    for (final w in widgets) {
      if (w.instanceId == instanceId) {
        next.add(w.copyWith(config: config));
        changed = true;
      } else {
        next.add(w);
      }
    }
    if (!changed) return;
    _controller.add(current.copyWith(widgets: next));
    _scheduleSave();
  }

  /// Replace the entire layout with [layout] and schedule a save. This is
  /// the building block used by the higher-level "Restablecer según mis
  /// objetivos" action — that action lives in the UI (Phase 4) and calls
  /// this method with `DashboardLayoutDefaults.fromGoals(currentGoals)`.
  void resetToFallback(DashboardLayout layout) {
    _persistenceLocked = false;
    _controller.add(layout);
    _scheduleSave();
  }

  /// Close the underlying subject. Mainly for tests — the singleton lives
  /// for the entire app lifetime in production.
  @visibleForTesting
  Future<void> dispose() async {
    await flush();
    await _controller.close();
  }
}
