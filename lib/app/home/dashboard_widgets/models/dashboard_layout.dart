import 'package:kilatex/app/home/dashboard_widgets/models/widget_descriptor.dart';

/// Immutable serializable representation of the dashboard layout.
///
/// Stored as a JSON-encoded `String` in `SettingKey.dashboardLayout` (see
/// `dashboard-layout` spec § Persistencia). The list order is significant:
/// it is the actual render order of the widgets on screen.
///
/// Versioning lives in [schemaVersion]; the migrator
/// (`DashboardLayoutMigrator`) chains `vN → vN+1` migrations before this
/// class is ever instantiated, so consumers always observe the
/// [currentSchemaVersion].
class DashboardLayout {
  /// The current binary's schema version. Bump this whenever the layout
  /// shape changes in a non-additive way and add a migration step in
  /// [DashboardLayoutMigrator].
  static const int currentSchemaVersion = 1;

  final int schemaVersion;
  final List<WidgetDescriptor> widgets;

  const DashboardLayout({
    required this.schemaVersion,
    required this.widgets,
  });

  /// Empty layout pinned to [currentSchemaVersion]. Used as the seed value
  /// for `BehaviorSubject` and as the "fall through" when persisted JSON is
  /// invalid.
  factory DashboardLayout.empty() {
    return const DashboardLayout(
      schemaVersion: currentSchemaVersion,
      widgets: <WidgetDescriptor>[],
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'schemaVersion': schemaVersion,
      'widgets': widgets.map((w) => w.toJson()).toList(growable: false),
    };
  }

  /// Best-effort, non-throwing decoder.
  ///
  /// Behaviour:
  ///   - Missing or non-list `widgets` → empty layout at [currentSchemaVersion].
  ///   - Missing `schemaVersion` → treated as `1` (initial).
  ///   - Unknown widget `type` / `size` → the descriptor is dropped (the
  ///     layout still loads — see spec scenario "WidgetType desconocido").
  ///
  /// Note: this method does NOT regenerate duplicate `instanceId`s nor run
  /// migrations. That is the migrator's job — call
  /// `DashboardLayoutMigrator.migrate(json)` instead when reading from
  /// persistence.
  factory DashboardLayout.fromJson(Map<String, dynamic> json) {
    final rawVersion = json['schemaVersion'];
    final schemaVersion = rawVersion is int
        ? rawVersion
        : int.tryParse('${rawVersion ?? ''}') ?? 1;

    final rawWidgets = json['widgets'];
    final widgets = <WidgetDescriptor>[];
    if (rawWidgets is List) {
      for (final entry in rawWidgets) {
        if (entry is! Map) continue;
        final descriptor = WidgetDescriptor.fromJson(
          Map<String, dynamic>.from(entry),
        );
        if (descriptor != null) widgets.add(descriptor);
      }
    }

    return DashboardLayout(
      schemaVersion: schemaVersion,
      widgets: List<WidgetDescriptor>.unmodifiable(widgets),
    );
  }

  DashboardLayout copyWith({
    int? schemaVersion,
    List<WidgetDescriptor>? widgets,
  }) {
    return DashboardLayout(
      schemaVersion: schemaVersion ?? this.schemaVersion,
      widgets: widgets == null
          ? List<WidgetDescriptor>.unmodifiable(this.widgets)
          : List<WidgetDescriptor>.unmodifiable(widgets),
    );
  }

  /// Convenience: lookup a descriptor by its [instanceId]. Returns `null`
  /// when no match is found.
  WidgetDescriptor? findByInstanceId(String instanceId) {
    for (final w in widgets) {
      if (w.instanceId == instanceId) return w;
    }
    return null;
  }

  bool get isEmpty => widgets.isEmpty;

  @override
  String toString() =>
      'DashboardLayout(schemaVersion: $schemaVersion, '
      'widgets: ${widgets.length})';
}
