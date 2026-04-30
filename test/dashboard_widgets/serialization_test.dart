import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:bolsio/app/home/dashboard_widgets/models/dashboard_layout.dart';
import 'package:bolsio/app/home/dashboard_widgets/models/widget_descriptor.dart';

/// Task 3.1 — round-trip JSON `WidgetDescriptor` / `DashboardLayout`.
///
/// Spec: `dashboard-layout` § Modelo `DashboardLayout` (Scenario round-trip).
void main() {
  group('WidgetDescriptor — toJson/fromJson round-trip', () {
    test('every WidgetType / WidgetSize survives encode → decode', () {
      for (final type in WidgetType.values) {
        for (final size in WidgetSize.values) {
          final descriptor = WidgetDescriptor(
            instanceId: 'fixed-id-${type.name}-${size.name}',
            type: type,
            size: size,
            config: const <String, dynamic>{
              'displayCurrency': 'USD',
              'period': '30d',
              'showDeltaPill': true,
              'limit': 5,
            },
          );

          final encoded = jsonEncode(descriptor.toJson());
          final decodedJson =
              jsonDecode(encoded) as Map<String, dynamic>;
          final decoded = WidgetDescriptor.fromJson(decodedJson);

          expect(decoded, isNotNull, reason: '${type.name}/${size.name}');
          expect(decoded!.instanceId, descriptor.instanceId);
          expect(decoded.type, descriptor.type);
          expect(decoded.size, descriptor.size);
          expect(decoded.config['displayCurrency'], 'USD');
          expect(decoded.config['period'], '30d');
          expect(decoded.config['showDeltaPill'], isTrue);
          expect(decoded.config['limit'], 5);
        }
      }
    });

    test('empty config round-trips to an empty map', () {
      final descriptor = WidgetDescriptor(
        instanceId: 'empty-cfg',
        type: WidgetType.totalBalanceSummary,
        size: WidgetSize.fullWidth,
      );

      final encoded = jsonEncode(descriptor.toJson());
      final decoded = WidgetDescriptor.fromJson(
        jsonDecode(encoded) as Map<String, dynamic>,
      );

      expect(decoded, isNotNull);
      expect(decoded!.config, isEmpty);
    });

    test('config with primitive types (string/int/bool/list/map) survives', () {
      final descriptor = WidgetDescriptor(
        instanceId: 'cfg-mix',
        type: WidgetType.quickUse,
        size: WidgetSize.fullWidth,
        config: const <String, dynamic>{
          'chips': <String>[
            'toggleHiddenMode',
            'addExpense',
            'openTransactions',
          ],
          'count': 7,
          'enabled': false,
          'nested': <String, dynamic>{'k': 'v', 'n': 1},
        },
      );

      final encoded = jsonEncode(descriptor.toJson());
      final decoded = WidgetDescriptor.fromJson(
        jsonDecode(encoded) as Map<String, dynamic>,
      );

      expect(decoded, isNotNull);
      expect(
        (decoded!.config['chips'] as List<dynamic>).cast<String>(),
        equals(<String>[
          'toggleHiddenMode',
          'addExpense',
          'openTransactions',
        ]),
      );
      expect(decoded.config['count'], 7);
      expect(decoded.config['enabled'], isFalse);
      final nested = Map<String, dynamic>.from(
        decoded.config['nested'] as Map,
      );
      expect(nested['k'], 'v');
      expect(nested['n'], 1);
    });

    test('fromJson returns null for unknown type', () {
      final json = <String, dynamic>{
        'instanceId': 'x',
        'type': 'someTypeThatDoesNotExist',
        'size': 'medium',
        'config': <String, dynamic>{},
      };
      expect(WidgetDescriptor.fromJson(json), isNull);
    });

    test('fromJson returns null for unknown size', () {
      final json = <String, dynamic>{
        'instanceId': 'x',
        'type': WidgetType.totalBalanceSummary.name,
        'size': 'jumbo',
        'config': <String, dynamic>{},
      };
      expect(WidgetDescriptor.fromJson(json), isNull);
    });

    test('fromJson regenerates a missing/empty instanceId', () {
      final json = <String, dynamic>{
        'instanceId': '',
        'type': WidgetType.quickUse.name,
        'size': WidgetSize.fullWidth.name,
        'config': <String, dynamic>{},
      };
      final decoded = WidgetDescriptor.fromJson(json);
      expect(decoded, isNotNull);
      expect(decoded!.instanceId, isNotEmpty);
    });
  });

  group('DashboardLayout — toJson/fromJson round-trip', () {
    test('layout with N descriptors preserves order and content', () {
      final layout = DashboardLayout(
        schemaVersion: DashboardLayout.currentSchemaVersion,
        widgets: <WidgetDescriptor>[
          WidgetDescriptor(
            instanceId: 'a',
            type: WidgetType.quickUse,
            size: WidgetSize.fullWidth,
            config: const <String, dynamic>{
              'chips': <String>['toggleHiddenMode'],
            },
          ),
          WidgetDescriptor(
            instanceId: 'b',
            type: WidgetType.totalBalanceSummary,
            size: WidgetSize.fullWidth,
          ),
          WidgetDescriptor(
            instanceId: 'c',
            type: WidgetType.exchangeRateCard,
            size: WidgetSize.medium,
            config: const <String, dynamic>{'displayCurrency': 'USD'},
          ),
        ],
      );

      final encoded = jsonEncode(layout.toJson());
      final decoded = DashboardLayout.fromJson(
        jsonDecode(encoded) as Map<String, dynamic>,
      );

      expect(decoded.schemaVersion, DashboardLayout.currentSchemaVersion);
      expect(decoded.widgets.length, 3);
      expect(decoded.widgets[0].instanceId, 'a');
      expect(decoded.widgets[0].type, WidgetType.quickUse);
      expect(
        (decoded.widgets[0].config['chips'] as List<dynamic>).cast<String>(),
        equals(<String>['toggleHiddenMode']),
      );
      expect(decoded.widgets[1].instanceId, 'b');
      expect(decoded.widgets[2].size, WidgetSize.medium);
      expect(decoded.widgets[2].config['displayCurrency'], 'USD');
    });

    test('empty layout round-trips', () {
      final layout = DashboardLayout.empty();
      final encoded = jsonEncode(layout.toJson());
      final decoded = DashboardLayout.fromJson(
        jsonDecode(encoded) as Map<String, dynamic>,
      );
      expect(decoded.schemaVersion, DashboardLayout.currentSchemaVersion);
      expect(decoded.widgets, isEmpty);
    });

    test('unknown widget entries are dropped silently', () {
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
            'type': 'futureWidgetType',
            'size': 'medium',
            'config': <String, dynamic>{},
          },
        ],
      };
      final decoded = DashboardLayout.fromJson(json);
      expect(decoded.widgets.length, 1);
      expect(decoded.widgets.single.instanceId, 'good');
    });

    test('missing widgets key yields empty layout', () {
      final json = <String, dynamic>{'schemaVersion': 1};
      final decoded = DashboardLayout.fromJson(json);
      expect(decoded.widgets, isEmpty);
    });
  });
}
