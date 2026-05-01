import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nitido/app/home/dashboard_widgets/dashboard_layout_body.dart';
import 'package:nitido/app/home/dashboard_widgets/models/dashboard_layout.dart';
import 'package:nitido/app/home/dashboard_widgets/models/widget_descriptor.dart';
import 'package:nitido/app/home/dashboard_widgets/registry.dart';

/// Task 3.6 — `DashboardLayoutBody` renderiza N items según layout dado.
///
/// Spec: `dashboard-widgets` § Estabilidad por `instanceId`.
///
/// Pumps [DashboardLayoutBody] (extracted from `dashboard.page.dart` so the
/// test does NOT pull the heavy DB-bound dependencies of the real page).
DashboardWidgetSpec _stubSpec(
  WidgetType type,
  String label, {
  bool Function(WidgetDescriptor)? shouldRender,
}) {
  return DashboardWidgetSpec(
    type: type,
    displayName: (_) => label,
    icon: Icons.widgets_outlined,
    defaultSize: WidgetSize.fullWidth,
    allowedSizes: const <WidgetSize>{
      WidgetSize.medium,
      WidgetSize.fullWidth,
    },
    builder: (_, descriptor, {required editing}) {
      // Use a unique key derived from the descriptor so the test can find
      // the rendered widget even when the body wraps it in a slot.
      return Container(
        key: ValueKey<String>('stub-${descriptor.instanceId}'),
        height: 32,
        alignment: Alignment.center,
        child: Text('$label::${descriptor.instanceId}'),
      );
    },
    shouldRender: shouldRender,
  );
}

Widget _harness(Widget child) {
  return MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: 400,
        height: 800,
        child: child,
      ),
    ),
  );
}

void main() {
  setUp(() {
    DashboardWidgetRegistry.instance.reset();
  });

  tearDownAll(() {
    DashboardWidgetRegistry.instance.reset();
  });

  testWidgets('renders three slots with stable layout-slot-<instanceId> keys',
      (tester) async {
    final registry = DashboardWidgetRegistry.instance;
    registry.register(_stubSpec(WidgetType.quickUse, 'QU'));
    registry.register(_stubSpec(WidgetType.totalBalanceSummary, 'TBS'));
    registry.register(_stubSpec(WidgetType.exchangeRateCard, 'ERC'));

    final layout = DashboardLayout(
      schemaVersion: DashboardLayout.currentSchemaVersion,
      widgets: <WidgetDescriptor>[
        WidgetDescriptor(
          instanceId: 'id-1',
          type: WidgetType.quickUse,
          size: WidgetSize.fullWidth,
        ),
        WidgetDescriptor(
          instanceId: 'id-2',
          type: WidgetType.totalBalanceSummary,
          size: WidgetSize.fullWidth,
        ),
        WidgetDescriptor(
          instanceId: 'id-3',
          type: WidgetType.exchangeRateCard,
          size: WidgetSize.fullWidth,
        ),
      ],
    );

    await tester.pumpWidget(_harness(DashboardLayoutBody(layout: layout)));

    // Each slot is keyed with `layout-slot-<instanceId>`.
    expect(
      find.byKey(const ValueKey<String>('layout-slot-id-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('layout-slot-id-2')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('layout-slot-id-3')),
      findsOneWidget,
    );

    // Stub builders rendered with their own keys.
    expect(
      find.byKey(const ValueKey<String>('stub-id-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('stub-id-2')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('stub-id-3')),
      findsOneWidget,
    );
  });

  testWidgets('descriptors with unregistered types are skipped silently',
      (tester) async {
    // Only register quickUse — totalBalanceSummary will be missing.
    DashboardWidgetRegistry.instance
        .register(_stubSpec(WidgetType.quickUse, 'QU'));

    final layout = DashboardLayout(
      schemaVersion: DashboardLayout.currentSchemaVersion,
      widgets: <WidgetDescriptor>[
        WidgetDescriptor(
          instanceId: 'rendered',
          type: WidgetType.quickUse,
          size: WidgetSize.fullWidth,
        ),
        WidgetDescriptor(
          instanceId: 'skipped',
          type: WidgetType.totalBalanceSummary,
          size: WidgetSize.fullWidth,
        ),
      ],
    );

    await tester.pumpWidget(_harness(DashboardLayoutBody(layout: layout)));

    expect(
      find.byKey(const ValueKey<String>('layout-slot-rendered')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('layout-slot-skipped')),
      findsNothing,
    );
  });

  testWidgets('empty layout renders SizedBox.shrink with no slots',
      (tester) async {
    DashboardWidgetRegistry.instance
        .register(_stubSpec(WidgetType.quickUse, 'QU'));

    await tester.pumpWidget(_harness(DashboardLayoutBody(layout: DashboardLayout.empty())));

    // No slots emitted when widgets list is empty.
    expect(
      find.byWidgetPredicate((w) => w is DashboardLayoutSlot),
      findsNothing,
    );
  });

  testWidgets(
      'descriptors with shouldRender == false are skipped in view mode',
      (tester) async {
    final registry = DashboardWidgetRegistry.instance;
    // QU se muestra siempre (sin predicado), TBS está oculto por
    // `shouldRender: false`.
    registry.register(_stubSpec(WidgetType.quickUse, 'QU'));
    registry.register(
      _stubSpec(
        WidgetType.totalBalanceSummary,
        'TBS',
        shouldRender: (_) => false,
      ),
    );

    final layout = DashboardLayout(
      schemaVersion: DashboardLayout.currentSchemaVersion,
      widgets: <WidgetDescriptor>[
        WidgetDescriptor(
          instanceId: 'visible',
          type: WidgetType.quickUse,
          size: WidgetSize.fullWidth,
        ),
        WidgetDescriptor(
          instanceId: 'hidden',
          type: WidgetType.totalBalanceSummary,
          size: WidgetSize.fullWidth,
        ),
      ],
    );

    await tester.pumpWidget(_harness(DashboardLayoutBody(layout: layout)));

    expect(
      find.byKey(const ValueKey<String>('layout-slot-visible')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('layout-slot-hidden')),
      findsNothing,
      reason: 'view mode debe saltarse los slots cuyo shouldRender es false',
    );
  });

  testWidgets(
      'descriptors with shouldRender == true are rendered like normal',
      (tester) async {
    final registry = DashboardWidgetRegistry.instance;
    registry.register(
      _stubSpec(
        WidgetType.quickUse,
        'QU',
        shouldRender: (_) => true,
      ),
    );

    final layout = DashboardLayout(
      schemaVersion: DashboardLayout.currentSchemaVersion,
      widgets: <WidgetDescriptor>[
        WidgetDescriptor(
          instanceId: 'visible',
          type: WidgetType.quickUse,
          size: WidgetSize.fullWidth,
        ),
      ],
    );

    await tester.pumpWidget(_harness(DashboardLayoutBody(layout: layout)));

    expect(
      find.byKey(const ValueKey<String>('layout-slot-visible')),
      findsOneWidget,
    );
  });
}
