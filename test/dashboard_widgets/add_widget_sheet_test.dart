import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nitido/app/home/dashboard_widgets/edit/add_widget_sheet.dart';
import 'package:nitido/app/home/dashboard_widgets/models/widget_descriptor.dart';
import 'package:nitido/app/home/dashboard_widgets/registry.dart';
import 'package:nitido/app/home/dashboard_widgets/services/dashboard_layout_service.dart';
import 'package:nitido/core/database/services/user-setting/user_setting_service.dart';

/// Task 3.9 — `AddWidgetSheet` shows the recommended badge for goals and
/// adds a descriptor on tap.
///
/// Spec: `dashboard-edit-mode` § Bottom sheet (Scenarios goals=save_usd,
/// múltiples instancias).
DashboardWidgetSpec _stubSpec(
  WidgetType type,
  String label, {
  Set<String>? recommendedFor,
}) {
  return DashboardWidgetSpec(
    type: type,
    displayName: (_) => label,
    description: (_) => '$label desc',
    icon: Icons.widgets_outlined,
    defaultSize: WidgetSize.fullWidth,
    allowedSizes: const <WidgetSize>{WidgetSize.fullWidth},
    recommendedFor: recommendedFor ?? const <String>{},
    builder: (_, _, {required editing}) => const SizedBox.shrink(),
  );
}

void main() {
  setUp(() {
    DashboardWidgetRegistry.instance.reset();
    appStateSettings.remove(SettingKey.onboardingGoals);
  });

  tearDownAll(() {
    DashboardWidgetRegistry.instance.reset();
    appStateSettings.remove(SettingKey.onboardingGoals);
  });

  testWidgets('shows the "Recomendado" badge only for specs whose '
      'recommendedFor intersects onboardingGoals', (tester) async {
    final registry = DashboardWidgetRegistry.instance;
    registry.register(
      _stubSpec(
        WidgetType.exchangeRateCard,
        'Tasas',
        recommendedFor: <String>{'save_usd'},
      ),
    );
    registry.register(
      _stubSpec(
        WidgetType.totalBalanceSummary,
        'Balance total',
        recommendedFor: <String>{'track_expenses'},
      ),
    );
    registry.register(
      _stubSpec(WidgetType.quickUse, 'Atajos'),
    );

    appStateSettings[SettingKey.onboardingGoals] =
        jsonEncode(<String>['save_usd']);

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: AddWidgetSheet())),
    );

    // Catalog header is present.
    expect(find.text('Agregar widget'), findsOneWidget);

    // All three specs render in the catalog.
    expect(find.text('Tasas'), findsOneWidget);
    expect(find.text('Balance total'), findsOneWidget);
    expect(find.text('Atajos'), findsOneWidget);

    // Only one "Recomendado" badge, attached to the save_usd-matching spec.
    final recommendedBadge = find.text('Recomendado');
    expect(recommendedBadge, findsOneWidget);

    // The badge is in the same tile as "Tasas".
    final tasasTile =
        find.ancestor(of: find.text('Tasas'), matching: find.byType(Material));
    expect(
      find.descendant(of: tasasTile, matching: find.text('Recomendado')),
      findsOneWidget,
    );
  });

  testWidgets('with no goals set, no recommended badge appears',
      (tester) async {
    final registry = DashboardWidgetRegistry.instance;
    registry.register(
      _stubSpec(
        WidgetType.exchangeRateCard,
        'Tasas',
        recommendedFor: <String>{'save_usd'},
      ),
    );

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: AddWidgetSheet())),
    );

    expect(find.text('Tasas'), findsOneWidget);
    expect(find.text('Recomendado'), findsNothing);
  });

  testWidgets('tap on a tile adds a new descriptor to the live service',
      (tester) async {
    final registry = DashboardWidgetRegistry.instance;
    registry.register(_stubSpec(WidgetType.quickUse, 'Atajos'));

    // Reset the service singleton's value by overwriting via a reorder no-op.
    // The singleton is shared across the test session, so we record the
    // baseline length and assert the delta.
    final baseline =
        DashboardLayoutService.instance.current.widgets.length;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Builder(
              builder: (innerContext) => Center(
                child: ElevatedButton(
                  onPressed: () => showAddWidgetSheet(innerContext),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // The sheet is open. Tap the only catalog tile.
    expect(find.text('Atajos'), findsOneWidget);
    await tester.tap(find.text('Atajos'));
    await tester.pumpAndSettle();

    // Sheet closed and one new descriptor was appended to the live service.
    final after = DashboardLayoutService.instance.current.widgets.length;
    expect(after, baseline + 1);
    expect(
      DashboardLayoutService.instance.current.widgets.last.type,
      WidgetType.quickUse,
    );
  });
}
