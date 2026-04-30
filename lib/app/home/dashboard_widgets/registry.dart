import 'package:flutter/material.dart';
import 'package:kilatex/app/home/dashboard_widgets/models/widget_descriptor.dart';

/// Builder signature for a widget instance. Receives:
///   - [context]    — the build context (use for theme/i18n).
///   - [descriptor] — the layout entry being rendered. `descriptor.config`
///                    holds the per-instance settings.
///   - [editing]    — `true` when the dashboard is in edit mode. Widgets
///                    should disable internal gestures and avoid expensive
///                    work while editing.
typedef DashboardWidgetBuilder =
    Widget Function(
      BuildContext context,
      WidgetDescriptor descriptor, {
      required bool editing,
    });

/// Builder signature for the optional config editor (a bottom sheet).
typedef DashboardWidgetConfigEditorBuilder =
    Widget Function(BuildContext context, WidgetDescriptor descriptor);

/// Builder for the i18n-resolved display name. Receives [context] so the
/// implementation can pull the current `slang` translations.
typedef DashboardWidgetDisplayNameBuilder =
    String Function(BuildContext context);

/// Spec describing one widget type. Each entry of [WidgetType] MUST have a
/// matching spec registered via [DashboardWidgetRegistry.register] before
/// `runApp` (see `dashboard-widgets` § `DashboardWidgetRegistry`).
@immutable
class DashboardWidgetSpec {
  final WidgetType type;

  /// i18n display name. Resolved lazily via the supplied [BuildContext]
  /// so locale changes propagate without re-registering the spec.
  final DashboardWidgetDisplayNameBuilder displayName;

  /// Short i18n description used in the "Add widget" sheet. Optional —
  /// when `null`, the sheet falls back to [displayName] only.
  final DashboardWidgetDisplayNameBuilder? description;

  /// Icon shown in the catalog and edit-mode chrome.
  final IconData icon;

  /// Default size used when the user adds the widget from the catalog.
  /// MUST be present in [allowedSizes].
  final WidgetSize defaultSize;

  /// All sizes the widget supports. MUST contain at least [defaultSize]
  /// and MUST NOT be empty.
  final Set<WidgetSize> allowedSizes;

  /// Default value for `WidgetDescriptor.config` when the user adds an
  /// instance. The builder should treat unknown keys as additive (forward
  /// compatibility).
  final Map<String, dynamic> defaultConfig;

  /// `onboardingGoals` for which this widget is recommended in the "Add
  /// widget" sheet. Empty set means "never recommended automatically".
  final Set<String> recommendedFor;

  /// `true` when only one instance of this widget MAY exist in the
  /// layout. The catalog disables the entry when one is already present
  /// and `add()` callers should validate too.
  final bool unique;

  /// Builds the runtime widget. MUST be pure (no side effects beyond
  /// subscribing to already-shared streams).
  final DashboardWidgetBuilder builder;

  /// Optional bottom-sheet builder for editing this widget's config.
  /// `null` for widgets without user-configurable settings.
  final DashboardWidgetConfigEditorBuilder? configEditor;

  /// Predicado opcional que indica si el widget DEBE renderizarse en modo
  /// view. `null` (default) significa "siempre se muestra".
  ///
  /// Casos de uso: widgets con auto-hide (p. ej. `pendingImportsAlert`
  /// solo se ve si hay pendientes). En modo edit el predicado se ignora —
  /// el frame siempre aparece para que el usuario pueda quitar el widget
  /// aunque su body esté vacío en este momento.
  ///
  /// Debe ser sincrónico y barato (lectura de un getter cacheado o de un
  /// `ValueNotifier`). El renderer lo evalúa una vez por frame, no se
  /// suscribe a streams.
  final bool Function(WidgetDescriptor descriptor)? shouldRender;

  /// Mensaje específico mostrado en el placeholder de edit mode cuando
  /// `shouldRender` devuelve `false`. Permite explicar al usuario, en
  /// términos del dominio del widget, *cuándo* aparecerá automáticamente
  /// (p. ej. "Aparecerá cuando tengas movimientos por revisar").
  ///
  /// Cuando es `null`, el frame usa un fallback genérico
  /// ("Este widget aparecerá cuando tenga datos"). Solo aplica a widgets
  /// que declaran `shouldRender`; los demás nunca muestran el placeholder.
  final DashboardWidgetDisplayNameBuilder? hiddenPlaceholderMessage;

  const DashboardWidgetSpec({
    required this.type,
    required this.displayName,
    required this.icon,
    required this.defaultSize,
    required this.allowedSizes,
    required this.builder,
    this.description,
    this.defaultConfig = const <String, dynamic>{},
    this.recommendedFor = const <String>{},
    this.unique = false,
    this.configEditor,
    this.shouldRender,
    this.hiddenPlaceholderMessage,
  });
}

/// Static registry of [DashboardWidgetSpec]. Populated once at app boot
/// from `registry_bootstrap.dart` (invoked from `main.dart`).
///
/// The registry is a process-wide singleton (no instance state worth
/// scoping). Tests can [reset] between runs via the test-only API.
class DashboardWidgetRegistry {
  DashboardWidgetRegistry._();

  static final DashboardWidgetRegistry instance = DashboardWidgetRegistry._();

  /// Insertion-ordered map. `LinkedHashMap` semantics matter for [all] —
  /// the catalog renders widgets in the order they were registered.
  final Map<WidgetType, DashboardWidgetSpec> _specs =
      <WidgetType, DashboardWidgetSpec>{};

  /// Register [spec]. Throws [StateError] when a spec for the same
  /// `WidgetType` is already registered (see scenario "Registro doble del
  /// mismo type").
  void register(DashboardWidgetSpec spec) {
    if (_specs.containsKey(spec.type)) {
      throw StateError(
        'DashboardWidgetRegistry: ${spec.type.name} is already registered.',
      );
    }
    if (spec.allowedSizes.isEmpty) {
      throw StateError(
        'DashboardWidgetRegistry: ${spec.type.name} must declare at least '
        'one allowed size.',
      );
    }
    if (!spec.allowedSizes.contains(spec.defaultSize)) {
      throw StateError(
        'DashboardWidgetRegistry: ${spec.type.name} defaultSize '
        '(${spec.defaultSize.name}) is not in allowedSizes '
        '(${spec.allowedSizes.map((s) => s.name).join(', ')}).',
      );
    }
    _specs[spec.type] = spec;
  }

  /// Lookup a spec by [type]. Returns `null` when not registered (the
  /// renderer logs a warning and skips the widget — see scenario "Build
  /// con type ausente").
  DashboardWidgetSpec? get(WidgetType type) => _specs[type];

  /// All registered specs in registration order.
  List<DashboardWidgetSpec> all() =>
      List<DashboardWidgetSpec>.unmodifiable(_specs.values);

  /// Filter and order specs by relevance for the given [goals]. Order:
  ///   1. Specs whose `recommendedFor` intersects [goals] (registration
  ///      order preserved within this group).
  ///   2. The remaining specs (registration order preserved).
  ///
  /// Specs marked `unique` are still returned — the caller decides whether
  /// to disable them based on the active layout.
  List<DashboardWidgetSpec> recommendedFor(Set<String> goals) {
    final recommended = <DashboardWidgetSpec>[];
    final rest = <DashboardWidgetSpec>[];
    for (final spec in _specs.values) {
      if (spec.recommendedFor.any(goals.contains)) {
        recommended.add(spec);
      } else {
        rest.add(spec);
      }
    }
    return List<DashboardWidgetSpec>.unmodifiable(<DashboardWidgetSpec>[
      ...recommended,
      ...rest,
    ]);
  }

  /// Test-only reset. Production code never calls this — the registry is
  /// initialized once before `runApp`.
  @visibleForTesting
  void reset() => _specs.clear();
}
