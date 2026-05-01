import 'package:nitido/app/home/dashboard_widgets/models/dashboard_layout.dart';
import 'package:nitido/app/home/dashboard_widgets/models/widget_descriptor.dart';
import 'package:nitido/core/utils/logger.dart';

/// Result of running [DashboardLayoutMigrator.migrate]. Includes the
/// migrated layout and a flag telling the caller whether the on-disk JSON
/// should be re-persisted (e.g. duplicate instanceIds were regenerated, or
/// a migration step was applied, or unknown widgets were dropped).
class DashboardLayoutMigrationResult {
  final DashboardLayout layout;

  /// `true` when the input JSON differs in shape from the output layout
  /// (migration applied, duplicates regenerated, or unknown widgets
  /// dropped). The service uses this signal to schedule a write-back so the
  /// stored payload converges to the latest schema.
  final bool didMutate;

  /// `true` when the loaded `schemaVersion` was higher than this binary
  /// understands. The caller MUST apply fallback in that case AND MUST NOT
  /// overwrite storage (so a downgrade does not nuke the user's data).
  final bool isFutureVersion;

  const DashboardLayoutMigrationResult({
    required this.layout,
    required this.didMutate,
    required this.isFutureVersion,
  });
}

/// Migrator that brings persisted dashboard JSON to
/// [DashboardLayout.currentSchemaVersion].
///
/// Behaviour (matches `dashboard-layout` § Versionado y migrador):
///   - Missing/0/negative `schemaVersion` → treated as `v1` (initial).
///   - `schemaVersion <= currentSchemaVersion` → chain `vN → vN+1`.
///   - `schemaVersion > currentSchemaVersion` → return empty layout flagged
///     as future-version; the caller applies fallback and does NOT persist.
///   - Unknown widget `type` / `size` → descriptor dropped silently.
///   - Duplicate `instanceId` inside the layout → second + subsequent
///     copies receive a fresh uuid v4.
class DashboardLayoutMigrator {
  const DashboardLayoutMigrator._();

  /// Type alias kept private to avoid accidental misuse from outside.
  /// Each step receives a JSON map at version N and returns a JSON map at
  /// version N+1 (or null when the input is hopelessly broken — caller will
  /// fall through to the empty layout).
  static final Map<int, Map<String, dynamic> Function(Map<String, dynamic>)>
  _steps = <int, Map<String, dynamic> Function(Map<String, dynamic>)>{
    // Reserved for the first real migration. When schemaVersion 2 lands,
    // add `1: _migrateV1ToV2,` and ship the helper below.
  };

  /// Run all applicable migration steps and dedup duplicate ids.
  static DashboardLayoutMigrationResult migrate(
    Map<String, dynamic> rawJson,
  ) {
    var json = Map<String, dynamic>.from(rawJson);
    var didMutate = false;

    final rawVersion = json['schemaVersion'];
    var version = rawVersion is int
        ? rawVersion
        : int.tryParse('${rawVersion ?? ''}') ?? 1;
    if (version < 1) version = 1;

    if (version > DashboardLayout.currentSchemaVersion) {
      Logger.printDebug(
        '[DashboardLayoutMigrator] Loaded schemaVersion=$version is newer '
        'than the binary (current=${DashboardLayout.currentSchemaVersion}). '
        'Returning empty layout flagged as future-version.',
      );
      return DashboardLayoutMigrationResult(
        layout: DashboardLayout.empty(),
        didMutate: false,
        isFutureVersion: true,
      );
    }

    while (version < DashboardLayout.currentSchemaVersion) {
      final step = _steps[version];
      if (step == null) {
        // No step registered for this version — bump the marker and break
        // so we don't loop forever. This branch should never trigger in
        // practice (we only allow migration up to `currentSchemaVersion`).
        Logger.printDebug(
          '[DashboardLayoutMigrator] No migration step registered for '
          'v$version → v${version + 1}. Stopping at v$version.',
        );
        break;
      }
      json = step(json);
      version += 1;
      didMutate = true;
    }
    json['schemaVersion'] = DashboardLayout.currentSchemaVersion;

    // Track raw widget count BEFORE decode so we can detect dropped (unknown)
    // widgets and signal the service to re-persist the cleaned layout.
    final rawWidgets = json['widgets'];
    final rawWidgetCount = rawWidgets is List ? rawWidgets.length : 0;

    final layout = DashboardLayout.fromJson(json);
    if (layout.widgets.length != rawWidgetCount) {
      // Unknown types/sizes were dropped during decode.
      didMutate = true;
    }

    final dedupResult = _dedupInstanceIds(layout.widgets);
    if (dedupResult.changed) {
      didMutate = true;
    }

    return DashboardLayoutMigrationResult(
      layout: layout.copyWith(widgets: dedupResult.widgets),
      didMutate: didMutate,
      isFutureVersion: false,
    );
  }

  static _DedupResult _dedupInstanceIds(List<WidgetDescriptor> widgets) {
    final seen = <String>{};
    final out = <WidgetDescriptor>[];
    var changed = false;
    for (final w in widgets) {
      if (seen.add(w.instanceId)) {
        out.add(w);
      } else {
        final regenerated = w.withRegeneratedId();
        seen.add(regenerated.instanceId);
        out.add(regenerated);
        changed = true;
      }
    }
    return _DedupResult(widgets: out, changed: changed);
  }
}

class _DedupResult {
  final List<WidgetDescriptor> widgets;
  final bool changed;
  const _DedupResult({required this.widgets, required this.changed});
}
