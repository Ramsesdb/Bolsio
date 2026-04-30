import 'package:flutter_test/flutter_test.dart';
import 'package:bolsio/app/home/dashboard_widgets/models/dashboard_layout.dart';
import 'package:bolsio/app/home/dashboard_widgets/models/widget_descriptor.dart';
import 'package:bolsio/app/home/dashboard_widgets/services/dashboard_layout_service.dart';

/// Task 3.8 — drag reorder persists the new order via
/// `DashboardLayoutService.reorder`.
///
/// Spec: `dashboard-edit-mode` § Drag-and-drop (Scenario "reordenar tres
/// widgets").
///
/// **Scope note**: pumping `_DashboardEditBody` with a real
/// `ReorderableListView` inside a `Scaffold` requires synthesizing a
/// long-press + drag gesture across the live widget tree, which in turn
/// requires the full `DashboardPage` (DB-bound). To keep this test fast and
/// hermetic we simulate what `ReorderableListView.onReorder(from, to)`
/// dispatches — a single call to `service.reorder(from, to)` — and verify
/// the service produces the expected new order on its stream. The end-to-
/// end gesture path is captured in the manual checklist (Phase 3 task 3.11).
WidgetDescriptor _stub(String id) => WidgetDescriptor(
      instanceId: id,
      type: WidgetType.quickUse,
      size: WidgetSize.fullWidth,
    );

void main() {
  test('three widgets — moving the first to position 2 produces b,a,c',
      () async {
    final service = DashboardLayoutService.forTesting(
      writer: (_) async {},
    );
    service.add(_stub('a'));
    service.add(_stub('b'));
    service.add(_stub('c'));

    // ReorderableListView semantics: when `to > from`, `to` is post-removal,
    // so dragging from 0 to 2 moves "a" past "b" → b,a,c.
    service.reorder(0, 2);

    expect(
      service.current.widgets.map((w) => w.instanceId).toList(),
      equals(<String>['b', 'a', 'c']),
    );
  });

  test('three widgets — moving the last to position 0 produces c,a,b',
      () async {
    final service = DashboardLayoutService.forTesting(
      writer: (_) async {},
    );
    service.add(_stub('a'));
    service.add(_stub('b'));
    service.add(_stub('c'));

    service.reorder(2, 0);

    expect(
      service.current.widgets.map((w) => w.instanceId).toList(),
      equals(<String>['c', 'a', 'b']),
    );
  });

  test('reorder emits a new layout on the stream within the same microtask',
      () async {
    final service = DashboardLayoutService.forTesting(
      writer: (_) async {},
    );
    service.add(_stub('a'));
    service.add(_stub('b'));
    service.add(_stub('c'));

    final emissions = <DashboardLayout>[];
    final sub = service.stream.listen(emissions.add);

    service.reorder(0, 2);
    await Future<void>.delayed(Duration.zero);

    expect(emissions, isNotEmpty);
    expect(
      emissions.last.widgets.map((w) => w.instanceId).toList(),
      equals(<String>['b', 'a', 'c']),
    );
    await sub.cancel();
  });

  test('reorder schedules a debounced write via the writer callback',
      () async {
    var writes = 0;
    String? lastEncoded;
    final service = DashboardLayoutService.forTesting(
      debounceMs: 10,
      writer: (encoded) async {
        writes++;
        lastEncoded = encoded;
      },
    );
    service.add(_stub('a'));
    service.add(_stub('b'));
    service.add(_stub('c'));

    service.reorder(0, 2);

    // Wait long enough for the debounce window to elapse.
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(writes, greaterThanOrEqualTo(1));
    expect(lastEncoded, contains('"b"'));
    expect(lastEncoded, contains('"a"'));
    expect(lastEncoded, contains('"c"'));
  });
}
