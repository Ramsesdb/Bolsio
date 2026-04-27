import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wallex/app/home/dashboard_widgets/edit/editable_widget_frame.dart';
import 'package:wallex/app/home/dashboard_widgets/models/widget_descriptor.dart';
import 'package:wallex/app/home/dashboard_widgets/registry.dart';

/// Task 3.7 — `EditableWidgetFrame` smoke + toggle semantics.
///
/// Spec: `dashboard-edit-mode` § Toggle, § Edit frame.
///
/// **Scope note**: the live edit-mode toggle (lápiz → check) lives inside
/// `_DashboardPageState._editing` and can only be exercised by pumping the
/// full `DashboardPage`, which pulls heavy DB-bound dependencies (DateRange
/// service, AccountService, FAB, etc.). To keep the suite hermetic we test
/// the **observable contract** of edit mode at the frame level:
///
///   - The frame renders the X (delete) button.
///   - The frame renders a config (⚙) button when both `onConfigure` and
///     `spec.configEditor` are non-null.
///   - Internal gestures of the wrapped child are blocked
///     (`IgnorePointer(true)`).
///
/// A full E2E pass over the toggle is captured in the manual checklist
/// (Phase 3 task 3.11).
DashboardWidgetSpec _stubSpec({
  Widget Function(BuildContext, WidgetDescriptor)? configEditor,
}) {
  return DashboardWidgetSpec(
    type: WidgetType.quickUse,
    displayName: (_) => 'Stub',
    icon: Icons.widgets_outlined,
    defaultSize: WidgetSize.fullWidth,
    allowedSizes: const <WidgetSize>{WidgetSize.fullWidth},
    builder: (_, _, {required editing}) => const SizedBox.shrink(),
    configEditor: configEditor,
  );
}

void main() {
  testWidgets('EditableWidgetFrame renders the X (delete) button',
      (tester) async {
    var deleteCalled = false;
    final descriptor = WidgetDescriptor(
      instanceId: 'abc',
      type: WidgetType.quickUse,
      size: WidgetSize.fullWidth,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          // Add top padding so the negative-positioned X button has room to
          // be hit-tested above the frame.
          body: Padding(
            padding: const EdgeInsets.only(top: 60),
            child: SizedBox(
              width: 400,
              child: EditableWidgetFrame(
                descriptor: descriptor,
                spec: _stubSpec(),
                onDelete: () => deleteCalled = true,
                child: const SizedBox(height: 50, key: Key('child-content')),
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.close_rounded), findsOneWidget);
    expect(find.byIcon(Icons.tune_rounded), findsNothing);

    // Tap by tooltip — the InkWell wrapping the X button is reachable via
    // its parent Tooltip which has zero offset.
    // The X button uses `Positioned(top: -22)` so it lives outside the
    // Stack's bounding box. We invoke its onTap callback directly through
    // the widget tree to verify the wiring without fighting Flutter's
    // hit-test rules. Tap-through-offset is verified manually (see Phase 3
    // task 3.11 manual checklist).
    final closeButton = tester.widget<InkWell>(
      find.descendant(
        of: find.byTooltip('Quitar'),
        matching: find.byType(InkWell),
      ),
    );
    closeButton.onTap?.call();
    expect(deleteCalled, isTrue);
  });

  testWidgets('shows the ⚙ button when spec has configEditor and '
      'onConfigure is provided', (tester) async {
    var configureCalled = false;
    final descriptor = WidgetDescriptor(
      instanceId: 'abc',
      type: WidgetType.quickUse,
      size: WidgetSize.fullWidth,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.only(top: 60),
            child: SizedBox(
              width: 400,
              child: EditableWidgetFrame(
                descriptor: descriptor,
                spec: _stubSpec(
                  configEditor: (_, _) => const SizedBox.shrink(),
                ),
                onDelete: () {},
                onConfigure: () => configureCalled = true,
                child: const SizedBox(height: 50),
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.tune_rounded), findsOneWidget);
    expect(find.byIcon(Icons.close_rounded), findsOneWidget);

    final configButton = tester.widget<InkWell>(
      find.descendant(
        of: find.byTooltip('Configurar'),
        matching: find.byType(InkWell),
      ),
    );
    configButton.onTap?.call();
    expect(configureCalled, isTrue);
  });

  testWidgets('hides the ⚙ button when onConfigure is null even if spec has '
      'configEditor', (tester) async {
    final descriptor = WidgetDescriptor(
      instanceId: 'abc',
      type: WidgetType.quickUse,
      size: WidgetSize.fullWidth,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            child: EditableWidgetFrame(
              descriptor: descriptor,
              spec: _stubSpec(
                configEditor: (_, _) => const SizedBox.shrink(),
              ),
              onDelete: () {},
              child: const SizedBox(height: 50),
            ),
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.tune_rounded), findsNothing);
  });

  testWidgets("absorbs the wrapped child's pointer events via IgnorePointer",
      (tester) async {
    var childTapCount = 0;
    final descriptor = WidgetDescriptor(
      instanceId: 'abc',
      type: WidgetType.quickUse,
      size: WidgetSize.fullWidth,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            child: EditableWidgetFrame(
              descriptor: descriptor,
              spec: _stubSpec(),
              onDelete: () {},
              child: GestureDetector(
                key: const Key('inner-tappable'),
                behavior: HitTestBehavior.opaque,
                onTap: () => childTapCount++,
                child: Container(
                  height: 60,
                  color: const Color(0xFFFAFAFA),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    // Tap on the inner child. Because the frame wraps it in
    // IgnorePointer(ignoring: true), the gesture must NOT reach the inner
    // GestureDetector.
    await tester.tap(
      find.byKey(const Key('inner-tappable')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    expect(childTapCount, 0,
        reason: 'IgnorePointer must swallow taps on the wrapped child');
  });
}
