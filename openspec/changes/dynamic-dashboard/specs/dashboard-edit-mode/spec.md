# Domain: dashboard-edit-mode

## Purpose

Define el modo edición del dashboard: cómo se entra/sale, el frame visual de cada widget en edición, eliminación con confirmación, drag-and-drop para reordenar, bottom sheet de "Agregar widget" con marcado de recomendados, persistencia con debounce y manejo de salida (`flush`).

## Requirements

### Requirement: Toggle de edit mode

El dashboard MUST exponer un toggle `_editing` (estado local de `_DashboardPageState`). El toggle MUST activarse vía un botón con icono lápiz en el header del dashboard, y desactivarse al tocar el mismo botón (que entonces muestra icono "check") o al pulsar el botón de retroceso del sistema.

Cuando `_editing == true`:

- Todos los widgets MUST renderizarse en `WidgetSize.fullWidth` temporalmente (lista vertical).
- El layout grid 2-col (`medium` widgets) MUST restaurarse al salir.
- El header MUST mostrar el botón "check" sustituyendo al lápiz.

#### Scenario: Entrar y salir de edit mode

- GIVEN el dashboard en modo view con widgets `medium` lado a lado
- WHEN el usuario toca el lápiz
- THEN `_editing` MUST volverse `true`
- AND todos los widgets MUST pasar a render `fullWidth`
- WHEN el usuario toca "check"
- THEN `_editing` MUST volverse `false`
- AND el grid 2-col MUST restaurarse según `WidgetSize` original

#### Scenario: Botón de retroceso

- GIVEN edit mode activo
- WHEN el usuario pulsa back del sistema
- THEN MUST salir de edit mode (no MUST salir de la app/dashboard)
- AND `flush()` MUST invocarse antes de cambiar de pantalla

### Requirement: Edit frame por widget

Cuando `editing == true`, cada widget MUST envolverse en un frame que muestra:

- Un botón "X" (icono close) en la esquina superior derecha — eliminar.
- Un drag handle (icono `drag_indicator`) en la esquina superior izquierda — reordenar.
- Un borde/sombra distintivo que comunique modo edición.

El contenido del widget MUST seguir renderizándose con datos en vivo (no MUST congelarse). Sin embargo, los gestos internos del widget (taps, navegación) MUST estar deshabilitados durante edición — solo X y drag deben responder.

#### Scenario: Tap en contenido durante edición

- GIVEN edit mode activo y un widget `accountCarousel`
- WHEN el usuario toca una cuenta del carrusel
- THEN NO MUST navegar a detalle de cuenta
- AND el tap MUST ser absorbido por el frame de edición sin efecto

### Requirement: Eliminación con confirmación

Tap en X MUST mostrar un diálogo de confirmación con texto i18n: "¿Eliminar {displayName} del dashboard?" y botones "Cancelar" / "Eliminar".

Confirmar MUST: remover el `WidgetDescriptor` del layout por `instanceId`, persistir vía `DashboardLayoutService.save()` (debounced), animar la salida con default Flutter.

Cancelar MUST cerrar el diálogo sin alterar el layout.

#### Scenario: Eliminar widget y reabrir app

- GIVEN un layout de 5 widgets
- WHEN el usuario elimina uno y confirma
- WHEN el usuario sale del edit mode (dispara `flush()`)
- WHEN el usuario cierra y reabre la app
- THEN el layout MUST tener exactamente 4 widgets (sin el eliminado)

#### Scenario: Eliminar `quickUse`

- GIVEN un layout con `quickUse`
- WHEN el usuario lo elimina
- THEN MUST permitirse (no es widget bloqueado en MVP)
- AND el usuario MUST poder re-agregarlo desde "Agregar widget"

### Requirement: Drag-and-drop para reordenar

En edit mode, el dashboard MUST usar `WallexReorderableList` (wrapper sobre `ReorderableListView`) con `Key(ValueKey(instanceId))` por item.

`onReorder(oldIndex, newIndex)` MUST: mutar la lista localmente para feedback inmediato, persistir vía `save()` (debounced 300 ms).

#### Scenario: Reordenar tres widgets

- GIVEN widgets A, B, C en orden
- WHEN el usuario arrastra B a la posición 0
- THEN el orden visual MUST volverse B, A, C inmediatamente
- AND tras 300 ms (o al salir/`flush`) la persistencia MUST reflejar B, A, C
- AND los `StreamSubscription` de A y C NO MUST recrearse (gracias a las keys estables)

### Requirement: Bottom sheet "Agregar widget"

Un botón "+ Agregar widget" MUST estar visible solo en edit mode al final de la lista. Tap abre `_AddWidgetSheet` (modal bottom sheet) que MUST listar todos los widgets del registry con:

- Sección "Recomendados para ti" arriba: filtrada por `onboardingGoals`, marcada con badge "Recomendado".
- Sección "Todos los widgets" abajo: el resto.

Cada item MUST mostrar `iconBuilder()`, `displayName(context)`, una breve descripción i18n, y un check si ya está en el layout (no oculta — permite múltiples instancias del mismo type, ej. dos `incomeExpensePeriod` con `period` distinto).

Tap en un item MUST: instanciar un nuevo `WidgetDescriptor` con `instanceId` v4 nuevo y `defaultConfig` y `defaultSize`, agregarlo al final del layout, persistir, cerrar el sheet.

#### Scenario: Goals = {save_usd}, abrir sheet

- GIVEN `onboardingGoals = {'save_usd'}` y `quickUse`, `totalBalanceSummary`, `accountCarousel` ya en layout
- WHEN el usuario abre el sheet
- THEN "Recomendados" MUST mostrar `exchangeRateCard` (entre otros) con badge
- AND `pendingImportsAlert` MUST aparecer en "Todos los widgets" sin badge

#### Scenario: Múltiples instancias del mismo type

- GIVEN un layout con un `incomeExpensePeriod` de `period='30d'`
- WHEN el usuario añade otro `incomeExpensePeriod`
- THEN MUST agregarse con `defaultConfig` (otro `instanceId`)
- AND ambos MUST coexistir en el layout

### Requirement: Persistencia con debounce

Toda mutación en edit mode (reorder, delete, add, config change) MUST invocar `DashboardLayoutService.save(layout)` con debounce 300 ms.

`flush()` MUST invocarse: al salir de edit mode, en `dispose` del `_DashboardPageState`, y al pausar la app (`AppLifecycleState.paused`).

#### Scenario: App backgrounded durante edición pendiente

- GIVEN una mutación pendiente en el debouncer
- WHEN la app va a background (`paused`)
- THEN `flush()` MUST forzar la escritura inmediata
- AND si la app es matada, el cambio MUST persistir tras reapertura

#### Scenario: Crash durante edit mode

- GIVEN una mutación dentro de la ventana de 300 ms
- WHEN la app crashea antes del `flush`
- THEN el cambio MAY perderse (aceptable en MVP)
- AND el layout previo MUST seguir cargando consistente

## Out of Scope

- Resize de widget por gesto (pinch / handles laterales).
- Drag-and-drop multi-columna en edit mode.
- Undo/redo de cambios.
- Botón "Restablecer según mis objetivos" en el header.
- Animaciones custom de entrada/salida de widgets.
- Selección múltiple para borrar varios widgets a la vez.
- Bloqueo de widgets "core" (todos son removibles en MVP).
