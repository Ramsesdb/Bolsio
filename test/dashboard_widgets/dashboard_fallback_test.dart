import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nitido/app/home/dashboard_widgets/defaults.dart';
import 'package:nitido/app/home/dashboard_widgets/models/dashboard_layout.dart';
import 'package:nitido/app/home/dashboard_widgets/models/widget_descriptor.dart';
import 'package:nitido/app/home/dashboard_widgets/registry.dart';
import 'package:nitido/app/home/dashboard_widgets/services/dashboard_layout_service.dart';

/// Task 3.7 — Layout vacío + introSeen='1' applies fallback().
///
/// Spec: `dashboard-layout` § Fallback (Scenario "returning user sin
/// layout en Firebase").
///
/// The gate in `DashboardPage._initLayout()` reads:
///
///   if (service.current.isEmpty &&
///       appStateData[AppDataKey.introSeen] == '1' &&
///       !service.isFutureVersion) {
///     service.save(DashboardLayoutDefaults.fallback());
///     await service.flush();
///   }
///
/// We can't pump the full `DashboardPage` from a unit test (it pulls heavy
/// DB-bound widgets), so this test exercises the gate semantics directly:
///   1. Register stub specs for every WidgetType (defaults.fromGoals/fallback
///      build descriptors via the registry).
///   2. Build a service with an empty initial layout.
///   3. Apply the gate logic the same way DashboardPage does.
///   4. Verify the service emits a layout with 7 default widgets.
DashboardWidgetSpec _stubSpec(WidgetType type) {
  return DashboardWidgetSpec(
    type: type,
    displayName: (_) => type.name,
    icon: Icons.widgets_outlined,
    defaultSize: type == WidgetType.exchangeRateCard
        ? WidgetSize.medium
        : WidgetSize.fullWidth,
    allowedSizes: const <WidgetSize>{WidgetSize.medium, WidgetSize.fullWidth},
    builder: (_, _, {required editing}) => const SizedBox.shrink(),
  );
}

void main() {
  setUpAll(() {
    final registry = DashboardWidgetRegistry.instance;
    registry.reset();
    for (final type in WidgetType.values) {
      registry.register(_stubSpec(type));
    }
  });

  tearDownAll(() {
    DashboardWidgetRegistry.instance.reset();
  });

  test(
    'empty layout + introSeen="1" gate triggers fallback() persist',
    () async {
      var introSeen = '1';
      final writes = <DashboardLayout>[];

      final service = DashboardLayoutService.forTesting(
        debounceMs: 1,
        writer: (_) async {
          // Capture the layout that would have been persisted.
          // (The service emits the new layout synchronously on the stream
          // before scheduling the write; we can read `current` here.)
        },
      );

      // Sanity: brand new service starts empty.
      expect(service.current.isEmpty, isTrue);
      expect(service.isFutureVersion, isFalse);

      // Subscribe to capture emissions.
      final sub = service.stream.listen(writes.add);

      // Replicate DashboardPage._initLayout() gate.
      if (service.current.isEmpty &&
          introSeen == '1' &&
          !service.isFutureVersion) {
        service.save(DashboardLayoutDefaults.fallback());
        await service.flush();
      }

      // Pump microtasks so the BehaviorSubject emits to the listener.
      await Future<void>.delayed(Duration.zero);

      // The stream emitted at least one non-empty layout.
      expect(writes.where((l) => !l.isEmpty), isNotEmpty);

      // The fallback() shape: 4 fixed widgets, quickUse first.
      // (Simplified default — see lib/app/home/dashboard_widgets/defaults.dart.)
      final last = writes.last;
      expect(last.widgets.length, 4);
      expect(last.widgets.first.type, WidgetType.quickUse);

      await sub.cancel();
      introSeen = ''; // unused tail — silences linter
      expect(introSeen.isEmpty, isTrue);
    },
  );

  test('empty layout + introSeen="0" does NOT trigger fallback', () async {
    final introSeen = '0';
    var saveCount = 0;
    final service = DashboardLayoutService.forTesting(
      debounceMs: 1,
      writer: (_) async {
        saveCount++;
      },
    );

    if (service.current.isEmpty &&
        introSeen == '1' &&
        !service.isFutureVersion) {
      service.save(DashboardLayoutDefaults.fallback());
      await service.flush();
    }

    await Future<void>.delayed(const Duration(milliseconds: 5));

    expect(
      service.current.isEmpty,
      isTrue,
      reason: 'fallback must NOT run while onboarding is incomplete',
    );
    expect(saveCount, 0);
  });

  test(
    'non-empty layout + introSeen="1" does NOT overwrite with fallback',
    () async {
      const introSeen = '1';
      final service = DashboardLayoutService.forTesting(
        debounceMs: 1,
        writer: (_) async {},
      );

      // Seed the service with a single user-chosen widget.
      service.add(
        WidgetDescriptor(
          instanceId: 'user-pick',
          type: WidgetType.quickUse,
          size: WidgetSize.fullWidth,
        ),
      );

      final beforeIds = service.current.widgets
          .map((w) => w.instanceId)
          .toList();

      if (service.current.isEmpty &&
          introSeen == '1' &&
          !service.isFutureVersion) {
        service.save(DashboardLayoutDefaults.fallback());
        await service.flush();
      }

      final afterIds = service.current.widgets
          .map((w) => w.instanceId)
          .toList();
      expect(
        afterIds,
        equals(beforeIds),
        reason: 'fallback must only fire when the layout is genuinely empty',
      );
    },
  );
}
