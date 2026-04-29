import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wallex/app/budgets/budgets_page.dart';
import 'package:wallex/app/calculator/calculator.page.dart';
import 'package:wallex/app/currencies/currency_manager.dart';
import 'package:wallex/app/home/dashboard_widgets/models/widget_descriptor.dart';
import 'package:wallex/app/home/dashboard_widgets/widgets/quick_use/quick_action_dispatcher.dart';
import 'package:wallex/app/settings/settings_page.dart';
import 'package:wallex/core/routes/destinations.dart';

/// Tests del bug-fix "quick-use chips deben switch tab en lugar de push".
///
/// El dispatcher expone dos seams `@visibleForTesting` (`_QuickNav.tabSwitcher`
/// y `_QuickNav.pusher` — accedidos vía `QuickActionDispatcher.debugXxx`
/// helpers porque son private). Aquí accedemos a través de los wrappers
/// públicos `debug*` añadidos al final del archivo del dispatcher.
///
/// Nota: NO instalamos los hooks directamente sobre `_QuickNav` porque es
/// privado al archivo del dispatcher. En su lugar el archivo expone helpers
/// `@visibleForTesting` públicos que reenvían a `_QuickNav`.
void main() {
  // Ancho de mobile (xs < md=720). El dispatcher detecta el layout vía
  // BreakPoint.of(context) usando MediaQuery, así que cada test envuelve la
  // chip en un MediaQuery con `size.width = 400` para forzar mobile.
  const mobileSize = Size(400, 800);

  // Capturadores reseteados antes de cada test.
  late List<AppMenuDestinationsID> tabSwitches;
  late List<Widget> pushedPages;

  setUp(() {
    tabSwitches = <AppMenuDestinationsID>[];
    pushedPages = <Widget>[];

    QuickActionDispatcherTestHooks.installTabSwitcher((id) {
      tabSwitches.add(id);
      // Devolvemos true para simular que el shell estaba montado y aceptó
      // el cambio de tab. El test verifica que el dispatcher NO cae al
      // fallback de push en este escenario.
      return true;
    });
    QuickActionDispatcherTestHooks.installPusher((page) {
      pushedPages.add(page);
    });
  });

  tearDown(() {
    QuickActionDispatcherTestHooks.resetHooks();
  });

  /// Pumpea un `Builder` con la `mobileSize` y dispara la acción del
  /// chip [id] sobre el contexto resultante.
  Future<void> tapAction(WidgetTester tester, QuickActionId id) async {
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: mobileSize),
        child: MaterialApp(
          home: Builder(
            builder: (context) {
              return ElevatedButton(
                onPressed: () =>
                    QuickActionDispatcher.run(id.name, context),
                child: const Text('tap'),
              );
            },
          ),
        ),
      ),
    );
    await tester.tap(find.byType(ElevatedButton));
    await tester.pump();
  }

  group('quick action dispatcher — switch tab on mobile', () {
    testWidgets(
      'openTransactions cambia el tab a transactions sin push',
      (tester) async {
        await tapAction(tester, QuickActionId.openTransactions);

        expect(
          tabSwitches,
          equals(<AppMenuDestinationsID>[
            AppMenuDestinationsID.transactions,
          ]),
        );
        expect(pushedPages, isEmpty);
      },
    );

    testWidgets(
      'goToReports cambia el tab a stats sin push',
      (tester) async {
        await tapAction(tester, QuickActionId.goToReports);

        expect(
          tabSwitches,
          equals(<AppMenuDestinationsID>[AppMenuDestinationsID.stats]),
        );
        expect(pushedPages, isEmpty);
      },
    );
  });

  group('quick action dispatcher — push para destinos sin tab', () {
    testWidgets('goToBudgets hace push de BudgetsPage', (tester) async {
      await tapAction(tester, QuickActionId.goToBudgets);

      expect(tabSwitches, isEmpty);
      expect(pushedPages, hasLength(1));
      expect(pushedPages.single, isA<BudgetsPage>());
    });

    testWidgets('goToSettings hace push de SettingsPage', (tester) async {
      await tapAction(tester, QuickActionId.goToSettings);

      expect(tabSwitches, isEmpty);
      expect(pushedPages, hasLength(1));
      expect(pushedPages.single, isA<SettingsPage>());
    });

    testWidgets(
      'openExchangeRates hace push de CurrencyManagerPage',
      (tester) async {
        await tapAction(tester, QuickActionId.openExchangeRates);

        expect(tabSwitches, isEmpty);
        expect(pushedPages, hasLength(1));
        expect(pushedPages.single, isA<CurrencyManagerPage>());
      },
    );

    testWidgets('goToCalculator hace push de CalculatorPage', (tester) async {
      await tapAction(tester, QuickActionId.goToCalculator);

      expect(tabSwitches, isEmpty);
      expect(pushedPages, hasLength(1));
      expect(pushedPages.single, isA<CalculatorPage>());
    });
  });

  group('quick action dispatcher — desktop layout cae a push', () {
    testWidgets(
      'En layout desktop (≥md) openTransactions hace push aunque haya tab',
      (tester) async {
        // Desktop: width ≥ 720 → `BreakPoint.of` devuelve md o mayor →
        // `_QuickNav` no intenta switchTab y delega en push.
        await tester.pumpWidget(
          MediaQuery(
            data: const MediaQueryData(size: Size(1200, 800)),
            child: MaterialApp(
              home: Builder(
                builder: (context) {
                  return ElevatedButton(
                    onPressed: () => QuickActionDispatcher.run(
                      QuickActionId.openTransactions.name,
                      context,
                    ),
                    child: const Text('tap'),
                  );
                },
              ),
            ),
          ),
        );
        await tester.tap(find.byType(ElevatedButton));
        await tester.pump();

        expect(tabSwitches, isEmpty);
        expect(pushedPages, hasLength(1));
      },
    );
  });
}
