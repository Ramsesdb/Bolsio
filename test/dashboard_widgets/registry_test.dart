import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wallex/app/home/dashboard_widgets/models/widget_descriptor.dart';
import 'package:wallex/app/home/dashboard_widgets/registry.dart';

/// Task 3.4 — `DashboardWidgetRegistry`.
///
/// Spec: `dashboard-widgets` § `DashboardWidgetRegistry` (Scenarios registro
/// doble, build con type ausente, recommendedFor por goal).
///
/// We avoid invoking the real `registerDashboardWidgets()` bootstrap (which
/// pulls in heavy widget code with DB-bound dependencies). Instead each test
/// resets the registry and registers a hand-crafted lightweight spec —
/// enough to verify the registry's public contract.
DashboardWidgetSpec _stubSpec(
  WidgetType type, {
  Set<String>? recommendedFor,
  bool unique = false,
  WidgetSize defaultSize = WidgetSize.fullWidth,
  Set<WidgetSize>? allowedSizes,
}) {
  return DashboardWidgetSpec(
    type: type,
    displayName: (_) => type.name,
    icon: Icons.widgets_outlined,
    defaultSize: defaultSize,
    allowedSizes: allowedSizes ??
        const <WidgetSize>{WidgetSize.medium, WidgetSize.fullWidth},
    recommendedFor: recommendedFor ?? const <String>{},
    unique: unique,
    builder: (_, _, {required editing}) => const SizedBox.shrink(),
  );
}

void main() {
  setUp(() {
    DashboardWidgetRegistry.instance.reset();
  });

  tearDownAll(() {
    DashboardWidgetRegistry.instance.reset();
  });

  group('register / get', () {
    test('register + get round-trip for every WidgetType', () {
      final registry = DashboardWidgetRegistry.instance;
      for (final type in WidgetType.values) {
        registry.register(_stubSpec(type));
      }
      for (final type in WidgetType.values) {
        final spec = registry.get(type);
        expect(spec, isNotNull, reason: 'missing spec for ${type.name}');
        expect(spec!.type, type);
      }
    });

    test('get returns null for an unregistered type', () {
      final registry = DashboardWidgetRegistry.instance;
      registry.register(_stubSpec(WidgetType.quickUse));
      expect(registry.get(WidgetType.exchangeRateCard), isNull);
    });

    test('register throws StateError when called twice for the same type', () {
      final registry = DashboardWidgetRegistry.instance;
      registry.register(_stubSpec(WidgetType.quickUse));
      expect(
        () => registry.register(_stubSpec(WidgetType.quickUse)),
        throwsStateError,
      );
    });

    test('register throws when allowedSizes is empty', () {
      final registry = DashboardWidgetRegistry.instance;
      expect(
        () => registry.register(
          _stubSpec(
            WidgetType.quickUse,
            allowedSizes: const <WidgetSize>{},
          ),
        ),
        throwsStateError,
      );
    });

    test('register throws when defaultSize is not in allowedSizes', () {
      final registry = DashboardWidgetRegistry.instance;
      expect(
        () => registry.register(
          _stubSpec(
            WidgetType.quickUse,
            defaultSize: WidgetSize.medium,
            allowedSizes: const <WidgetSize>{WidgetSize.fullWidth},
          ),
        ),
        throwsStateError,
      );
    });
  });

  group('all', () {
    test('returns specs in registration order', () {
      final registry = DashboardWidgetRegistry.instance;
      registry.register(_stubSpec(WidgetType.totalBalanceSummary));
      registry.register(_stubSpec(WidgetType.quickUse));
      registry.register(_stubSpec(WidgetType.exchangeRateCard));

      final types = registry.all().map((s) => s.type).toList();
      expect(
        types,
        equals(<WidgetType>[
          WidgetType.totalBalanceSummary,
          WidgetType.quickUse,
          WidgetType.exchangeRateCard,
        ]),
      );
    });

    test('returns an empty list when nothing is registered', () {
      final registry = DashboardWidgetRegistry.instance;
      expect(registry.all(), isEmpty);
    });
  });

  group('recommendedFor', () {
    test('promotes specs whose recommendedFor intersects the goals', () {
      final registry = DashboardWidgetRegistry.instance;
      registry.register(
        _stubSpec(WidgetType.totalBalanceSummary), // no recommendation
      );
      registry.register(
        _stubSpec(
          WidgetType.exchangeRateCard,
          recommendedFor: <String>{'save_usd'},
        ),
      );
      registry.register(
        _stubSpec(WidgetType.quickUse), // no recommendation
      );
      registry.register(
        _stubSpec(
          WidgetType.recentTransactions,
          recommendedFor: <String>{'save_usd', 'track_expenses'},
        ),
      );

      final result =
          registry.recommendedFor(<String>{'save_usd'}).map((s) => s.type).toList();

      // recommendedFor for save_usd: exchangeRateCard, recentTransactions
      // (in registration order). The remaining specs trail in registration
      // order.
      expect(
        result,
        equals(<WidgetType>[
          WidgetType.exchangeRateCard,
          WidgetType.recentTransactions,
          WidgetType.totalBalanceSummary,
          WidgetType.quickUse,
        ]),
      );
    });

    test('with empty goals returns specs in registration order', () {
      final registry = DashboardWidgetRegistry.instance;
      registry.register(
        _stubSpec(
          WidgetType.exchangeRateCard,
          recommendedFor: <String>{'save_usd'},
        ),
      );
      registry.register(_stubSpec(WidgetType.totalBalanceSummary));

      final result =
          registry.recommendedFor(<String>{}).map((s) => s.type).toList();
      expect(
        result,
        equals(<WidgetType>[
          WidgetType.exchangeRateCard,
          WidgetType.totalBalanceSummary,
        ]),
      );
    });

    test('a goal that no spec recommends still returns every spec', () {
      final registry = DashboardWidgetRegistry.instance;
      registry.register(_stubSpec(WidgetType.totalBalanceSummary));
      registry.register(_stubSpec(WidgetType.quickUse));

      final result = registry
          .recommendedFor(<String>{'goal_no_spec_cares_about'}).map((s) => s.type)
          .toList();
      expect(
        result,
        equals(<WidgetType>[
          WidgetType.totalBalanceSummary,
          WidgetType.quickUse,
        ]),
      );
    });
  });
}
