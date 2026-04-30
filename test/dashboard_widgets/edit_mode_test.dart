import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bolsio/app/home/dashboard_widgets/edit/editable_widget_frame.dart';
import 'package:bolsio/app/home/dashboard_widgets/models/widget_descriptor.dart';
import 'package:bolsio/app/home/dashboard_widgets/registry.dart';

/// Task 3.7 — `EditableWidgetFrame` smoke + toggle semantics.
///
/// Spec: `dashboard-edit-mode` § Toggle, § Edit frame.
///
/// **Scope note**: el toggle real (lápiz → check) vive en
/// `_DashboardPageState._editing` y solo se exercita pumpando todo el
/// `DashboardPage`, que tira dependencias pesadas (DateRange, AccountService,
/// FAB...). Para mantener la suite hermética testeamos el contrato
/// observable a nivel de frame:
///
///   - El frame renderiza el botón X (delete) y dispara `onDelete` al tap.
///   - El frame renderiza el botón ⚙ cuando el spec tiene `configEditor`
///     y se pasa `onConfigure`.
///   - Los gestos internos del child se bloquean (`IgnorePointer(true)`).
///   - El header con `displayName` aparece siempre y NUNCA anota
///     "(oculto)" — el estado oculto se comunica solo en el placeholder.
///   - Cuando `showEmptyPlaceholder == true`, el body se reemplaza por el
///     placeholder con el mensaje específico de
///     `spec.hiddenPlaceholderMessage` o, si es `null`, un fallback
///     genérico.
DashboardWidgetSpec _stubSpec({
  Widget Function(BuildContext, WidgetDescriptor)? configEditor,
  String label = 'Stub',
  String Function(BuildContext)? hiddenPlaceholderMessage,
}) {
  return DashboardWidgetSpec(
    type: WidgetType.quickUse,
    displayName: (_) => label,
    icon: Icons.widgets_outlined,
    defaultSize: WidgetSize.fullWidth,
    allowedSizes: const <WidgetSize>{WidgetSize.fullWidth},
    builder: (_, _, {required editing}) => const SizedBox.shrink(),
    configEditor: configEditor,
    hiddenPlaceholderMessage: hiddenPlaceholderMessage,
  );
}

void main() {
  testWidgets('EditableWidgetFrame X (delete) button is tappable and fires '
      'onDelete', (tester) async {
    var deleteCalled = false;
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
              onDelete: () => deleteCalled = true,
              child: const SizedBox(height: 50, key: Key('child-content')),
            ),
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.close_rounded), findsOneWidget);
    expect(find.byIcon(Icons.tune_rounded), findsNothing);

    // Bug 1 — Wave 5: el X vivía en `Positioned(top: -22)`, fuera del
    // bounding-box del Stack, y nunca recibía hit-test. Ahora vive dentro
    // del frame; un tap real (no invocando `onTap` manualmente) tiene que
    // disparar el callback.
    await tester.tap(find.byTooltip('Quitar'));
    await tester.pumpAndSettle();
    expect(deleteCalled, isTrue);
  });

  testWidgets('shows the ⚙ button when spec has configEditor and '
      'onConfigure is provided, and ⚙ tap fires onConfigure', (tester) async {
    var configureCalled = false;
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
              onConfigure: () => configureCalled = true,
              child: const SizedBox(height: 50),
            ),
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.tune_rounded), findsOneWidget);
    expect(find.byIcon(Icons.close_rounded), findsOneWidget);

    await tester.tap(find.byTooltip('Configurar'));
    await tester.pumpAndSettle();
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

    // Tap on the inner child. Como el frame lo envuelve en
    // `IgnorePointer(ignoring: true)`, el gesto NO debe llegar al
    // GestureDetector interno.
    await tester.tap(
      find.byKey(const Key('inner-tappable')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    expect(
      childTapCount,
      0,
      reason: 'IgnorePointer must swallow taps on the wrapped child',
    );
  });

  testWidgets('renders the displayName header always', (tester) async {
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
              spec: _stubSpec(label: 'Mi widget'),
              onDelete: () {},
              child: const SizedBox(height: 50),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Mi widget'), findsOneWidget);
  });

  testWidgets('renders empty placeholder with spec-provided message and '
      'keeps header clean (no "(oculto)" suffix) when showEmptyPlaceholder '
      'is true', (tester) async {
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
                label: 'Pendientes',
                hiddenPlaceholderMessage: (_) =>
                    'Aparecerá cuando tengas movimientos por revisar',
              ),
              onDelete: () {},
              showEmptyPlaceholder: true,
              child: const SizedBox(
                key: Key('real-body'),
                height: 200,
              ),
            ),
          ),
        ),
      ),
    );

    // Header: nombre limpio, sin sufijo "(oculto)".
    expect(find.text('Pendientes'), findsOneWidget);
    expect(find.text('Pendientes (oculto)'), findsNothing);
    // Body: mensaje específico del spec + ícono de "oculto".
    expect(
      find.text('Aparecerá cuando tengas movimientos por revisar'),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.visibility_off_outlined), findsOneWidget);
    // El copy genérico viejo no debe aparecer ya en ningún lado.
    expect(find.text('Sin contenido por ahora'), findsNothing);
    // Real child no debe aparecer cuando showEmptyPlaceholder está activo.
    expect(find.byKey(const Key('real-body')), findsNothing);
  });

  testWidgets('falls back to a generic message when the spec does NOT '
      'provide hiddenPlaceholderMessage', (tester) async {
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
              // Sin hiddenPlaceholderMessage → debe usar el fallback.
              spec: _stubSpec(label: 'Genérico'),
              onDelete: () {},
              showEmptyPlaceholder: true,
              child: const SizedBox(height: 50),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Genérico'), findsOneWidget);
    expect(
      find.text('Este widget aparecerá cuando tenga datos'),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.visibility_off_outlined), findsOneWidget);
  });
}
