import 'package:flutter_test/flutter_test.dart';
import 'package:bolsio/app/home/dashboard_widgets/models/dashboard_layout.dart';
import 'package:bolsio/app/home/dashboard_widgets/models/migrator.dart';
import 'package:bolsio/app/home/dashboard_widgets/models/widget_descriptor.dart';

/// Task 3.2 — `DashboardLayoutMigrator`.
///
/// Spec: `dashboard-layout` § Versionado y migrador; § Modelo
/// `WidgetDescriptor` Scenario instanceId duplicado.
void main() {
  group('DashboardLayoutMigrator.migrate', () {
    test('schemaVersion=1 with valid widgets is a no-op', () {
      final json = <String, dynamic>{
        'schemaVersion': 1,
        'widgets': <Map<String, dynamic>>[
          <String, dynamic>{
            'instanceId': 'a',
            'type': WidgetType.totalBalanceSummary.name,
            'size': WidgetSize.fullWidth.name,
            'config': <String, dynamic>{},
          },
          <String, dynamic>{
            'instanceId': 'b',
            'type': WidgetType.exchangeRateCard.name,
            'size': WidgetSize.medium.name,
            'config': <String, dynamic>{'displayCurrency': 'USD'},
          },
        ],
      };

      final result = DashboardLayoutMigrator.migrate(json);

      expect(result.isFutureVersion, isFalse);
      expect(result.didMutate, isFalse);
      expect(result.layout.schemaVersion, DashboardLayout.currentSchemaVersion);
      expect(result.layout.widgets.length, 2);
      expect(result.layout.widgets[0].instanceId, 'a');
      expect(result.layout.widgets[1].instanceId, 'b');
    });

    test('missing schemaVersion is treated as v1 (no-op)', () {
      final json = <String, dynamic>{
        'widgets': <Map<String, dynamic>>[
          <String, dynamic>{
            'instanceId': 'a',
            'type': WidgetType.quickUse.name,
            'size': WidgetSize.fullWidth.name,
            'config': <String, dynamic>{},
          },
        ],
      };

      final result = DashboardLayoutMigrator.migrate(json);

      expect(result.isFutureVersion, isFalse);
      expect(result.layout.schemaVersion, DashboardLayout.currentSchemaVersion);
      expect(result.layout.widgets.length, 1);
    });

    test('malformed widgets array yields empty layout, not a crash', () {
      // `widgets` here is a primitive — the migrator should fall through to
      // an empty layout instead of crashing.
      final json = <String, dynamic>{
        'schemaVersion': 1,
        'widgets': 'not-a-list',
      };

      final result = DashboardLayoutMigrator.migrate(json);

      expect(result.isFutureVersion, isFalse);
      expect(result.layout.widgets, isEmpty);
    });

    test('schemaVersion higher than currentSchemaVersion → '
        'isFutureVersion=true, empty layout, no migration applied', () {
      final json = <String, dynamic>{
        'schemaVersion': DashboardLayout.currentSchemaVersion + 5,
        'widgets': <Map<String, dynamic>>[
          <String, dynamic>{
            'instanceId': 'future-widget',
            'type': WidgetType.quickUse.name,
            'size': WidgetSize.fullWidth.name,
            'config': <String, dynamic>{'shouldNotLeak': true},
          },
        ],
      };

      final result = DashboardLayoutMigrator.migrate(json);

      expect(result.isFutureVersion, isTrue);
      expect(result.didMutate, isFalse);
      expect(result.layout.widgets, isEmpty);
    });

    test('unknown WidgetType is dropped silently and didMutate=true', () {
      final json = <String, dynamic>{
        'schemaVersion': 1,
        'widgets': <Map<String, dynamic>>[
          <String, dynamic>{
            'instanceId': 'good',
            'type': WidgetType.quickUse.name,
            'size': WidgetSize.fullWidth.name,
            'config': <String, dynamic>{},
          },
          <String, dynamic>{
            'instanceId': 'bad',
            'type': 'someTypeFromTheFuture',
            'size': WidgetSize.medium.name,
            'config': <String, dynamic>{},
          },
        ],
      };

      final result = DashboardLayoutMigrator.migrate(json);

      expect(result.isFutureVersion, isFalse);
      expect(result.didMutate, isTrue,
          reason: 'dropping unknown widget MUST trigger a write-back signal');
      expect(result.layout.widgets.length, 1);
      expect(result.layout.widgets.single.instanceId, 'good');
    });

    test('unknown WidgetSize is dropped silently and didMutate=true', () {
      final json = <String, dynamic>{
        'schemaVersion': 1,
        'widgets': <Map<String, dynamic>>[
          <String, dynamic>{
            'instanceId': 'good',
            'type': WidgetType.totalBalanceSummary.name,
            'size': WidgetSize.medium.name,
            'config': <String, dynamic>{},
          },
          <String, dynamic>{
            'instanceId': 'bad-size',
            'type': WidgetType.exchangeRateCard.name,
            'size': 'jumbo',
            'config': <String, dynamic>{},
          },
        ],
      };

      final result = DashboardLayoutMigrator.migrate(json);

      expect(result.didMutate, isTrue);
      expect(result.layout.widgets.length, 1);
      expect(result.layout.widgets.single.instanceId, 'good');
    });

    test('duplicate instanceId is regenerated and didMutate=true', () {
      // The first descriptor wins; subsequent copies receive a fresh uuid.
      final json = <String, dynamic>{
        'schemaVersion': 1,
        'widgets': <Map<String, dynamic>>[
          <String, dynamic>{
            'instanceId': 'duplicate',
            'type': WidgetType.quickUse.name,
            'size': WidgetSize.fullWidth.name,
            'config': <String, dynamic>{'tag': 'first'},
          },
          <String, dynamic>{
            'instanceId': 'duplicate',
            'type': WidgetType.totalBalanceSummary.name,
            'size': WidgetSize.fullWidth.name,
            'config': <String, dynamic>{'tag': 'second'},
          },
          <String, dynamic>{
            'instanceId': 'duplicate',
            'type': WidgetType.exchangeRateCard.name,
            'size': WidgetSize.medium.name,
            'config': <String, dynamic>{'tag': 'third'},
          },
        ],
      };

      final result = DashboardLayoutMigrator.migrate(json);

      expect(result.didMutate, isTrue);
      expect(result.layout.widgets.length, 3);
      // First occurrence keeps the original id.
      expect(result.layout.widgets[0].instanceId, 'duplicate');
      // Subsequent copies get fresh, non-empty, distinct ids.
      expect(result.layout.widgets[1].instanceId, isNot('duplicate'));
      expect(result.layout.widgets[1].instanceId.isNotEmpty, isTrue);
      expect(result.layout.widgets[2].instanceId, isNot('duplicate'));
      expect(result.layout.widgets[2].instanceId.isNotEmpty, isTrue);
      expect(
        result.layout.widgets[1].instanceId,
        isNot(equals(result.layout.widgets[2].instanceId)),
      );
      // Tags survive — only the id was changed.
      expect(result.layout.widgets[0].config['tag'], 'first');
      expect(result.layout.widgets[1].config['tag'], 'second');
      expect(result.layout.widgets[2].config['tag'], 'third');
    });

    test('empty widgets list is a clean no-op', () {
      final json = <String, dynamic>{
        'schemaVersion': 1,
        'widgets': <Map<String, dynamic>>[],
      };

      final result = DashboardLayoutMigrator.migrate(json);

      expect(result.didMutate, isFalse);
      expect(result.isFutureVersion, isFalse);
      expect(result.layout.widgets, isEmpty);
    });

    test('schemaVersion=0 is normalized to v1', () {
      final json = <String, dynamic>{
        'schemaVersion': 0,
        'widgets': <Map<String, dynamic>>[
          <String, dynamic>{
            'instanceId': 'a',
            'type': WidgetType.quickUse.name,
            'size': WidgetSize.fullWidth.name,
            'config': <String, dynamic>{},
          },
        ],
      };

      final result = DashboardLayoutMigrator.migrate(json);

      expect(result.layout.schemaVersion, DashboardLayout.currentSchemaVersion);
      expect(result.layout.widgets.length, 1);
    });
  });
}
