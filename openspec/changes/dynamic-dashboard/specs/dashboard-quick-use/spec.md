# Domain: dashboard-quick-use

## Purpose

Define el contrato del widget `quickUse`: enum `QuickActionId`, mapping action→callback, editor de configuración (chip selector + reorder), defaults y persistencia dentro del `config` del propio descriptor.

## Requirements

### Requirement: Enum `QuickActionId`

El sistema MUST exponer un enum cerrado `QuickActionId` con al menos las siguientes entradas, agrupadas en tres categorías:

**Toggles** (alternan estado de servicios):

- `toggleHiddenMode` — alterna `HiddenModeService.isLocked`.
- `togglePreferredCurrency` — cicla USD ↔ VES en `preferredCurrency`.

**Navegación** (push a páginas):

- `openTransactions`, `openAccounts`, `openBudgets`, `openDebts`, `openGoals`, `openSettings`, `openExchangeRates`.

**Quick transactions** (creación rápida):

- `addExpense`, `addIncome`, `addTransfer`.

Cada `QuickActionId` MUST tener: `displayName` (i18n), `iconData`, `category` (`toggle | navigation | quickTx`), `callback(BuildContext)` registrado en un `QuickActionRegistry`.

### Requirement: Mapping action → callback

`QuickActionRegistry.run(QuickActionId, BuildContext)` MUST ejecutar el callback registrado. Si el `QuickActionId` no tiene callback registrado, MUST loggear warning y NO MUST crashear.

Toggles MUST usar el servicio singleton existente (no re-implementar estado). Navegación MUST usar el router actual de la app. Quick transactions MUST abrir la página de creación con preset de tipo.

#### Scenario: Tap en `toggleHiddenMode`

- GIVEN `HiddenModeService.isLocked == true`
- WHEN el usuario toca el chip
- THEN `isLocked` MUST volverse `false`
- AND todos los widgets dependientes de `visibleAccountIdsStream` MUST actualizarse

#### Scenario: Tap en `togglePreferredCurrency` con USD

- GIVEN `preferredCurrency == 'USD'`
- WHEN el usuario toca el chip
- THEN `preferredCurrency` MUST volverse `'VES'`
- AND `UserSettingService` MUST persistir el cambio con `updateGlobalState: true`
- AND widgets que usan currency efectiva MUST refrescar

#### Scenario: Tap en `addExpense`

- GIVEN dashboard renderizado
- WHEN el usuario toca el chip
- THEN MUST navegar a página de creación con `transactionType='expense'` preseleccionado
- AND si el usuario cancela, MUST volver al dashboard sin alterar nada

#### Scenario: QuickActionId huérfano

- GIVEN `config.chips = ['removedAction']` (action obsoleta tras downgrade)
- WHEN el widget se renderiza
- THEN el chip desconocido MUST omitirse
- AND el resto de chips MUST renderizarse normalmente

### Requirement: `configEditor` del widget `quickUse`

El `configEditor` del `quickUse` MUST abrir un bottom sheet con dos pestañas:

1. **Pestaña "Atajos"**: chips de todos los `QuickActionId` agrupados por categoría. Tap en un chip alterna su presencia en `config.chips`. Chips ya seleccionados MUST mostrarse con check visual.
2. **Pestaña "Orden"**: lista reorderable (`WallexReorderableList`) de los chips actualmente seleccionados, con drag handle.

El sheet MUST tener un botón "Listo" que cierre y persista los cambios. Cerrar con swipe-down o tap fuera MUST equivaler a "Listo" (persistir).

`config.chips` MUST ser una lista de strings (los `QuickActionId.name`). El orden de la lista define el orden de render.

#### Scenario: Selección y reorden

- GIVEN `config.chips = ['toggleHiddenMode', 'addExpense']`
- WHEN el usuario abre `configEditor`, agrega `openBudgets` en pestaña 1, lo arrastra al inicio en pestaña 2 y cierra
- THEN `config.chips` MUST volverse `['openBudgets', 'toggleHiddenMode', 'addExpense']`
- AND el widget en el dashboard MUST reflejar el orden inmediatamente

#### Scenario: Cerrar sheet con swipe

- GIVEN cambios pendientes en el editor
- WHEN el usuario hace swipe-down para cerrar
- THEN los cambios MUST persistir (mismo comportamiento que "Listo")

#### Scenario: Sin chips seleccionados al cerrar

- GIVEN el usuario deselecciona TODOS los chips
- WHEN cierra el sheet
- THEN `config.chips` MUST guardarse como `[]`
- AND el widget MUST mostrar el empty state ("Configurar atajos")

### Requirement: Defaults de `quickUse`

`DashboardWidgetSpec` para `quickUse` MUST exponer `defaultConfig.chips` con la lista por defecto: `['toggleHiddenMode', 'addExpense', 'addIncome', 'openTransactions', 'openExchangeRates']`.

Cuando el widget `quickUse` se añade desde el bottom sheet "Agregar widget" o desde `DashboardLayoutDefaults.fromGoals`, MUST inicializarse con `defaultConfig.chips`.

#### Scenario: Goal `save_usd` añade quickUse

- GIVEN onboarding con `goals={'save_usd'}`
- WHEN se invoca `DashboardLayoutDefaults.fromGoals({'save_usd'})`
- THEN el `quickUse` resultante MUST tener `config.chips` con los 5 defaults
- AND uno de ellos MUST ser `openExchangeRates` (relevante a save_usd)

### Requirement: Persistencia dentro del descriptor

`config.chips` MUST persistirse dentro del `WidgetDescriptor.config` del propio `quickUse` (no en una `SettingKey` separada). Esto MUST viajar con el resto del layout en `SettingKey.dashboardLayout` y sincronizar vía Firebase blob.

NO MUST existir `SettingKey.dashboardQuickUseChips` separada en MVP.

#### Scenario: Sync entre dispositivos

- GIVEN device A configura `chips=['openBudgets', 'addIncome']`
- WHEN A pushea sync y B hace `pullAllData()`
- THEN B MUST renderizar el `quickUse` con esos 2 chips en ese orden

### Requirement: Multi-currency de `togglePreferredCurrency`

`togglePreferredCurrency` MUST cambiar `preferredCurrency` entre USD y VES exclusivamente (las dos monedas soportadas).

El chip MUST mostrar la moneda ACTUAL como label (ej. "USD" cuando preferred=USD), de modo que el tap "promete" cambiar. La actualización del label MUST ser reactiva al stream de `preferredCurrency`.

#### Scenario: Label reactivo

- GIVEN chip mostrando "USD"
- WHEN el usuario lo toca y `preferredCurrency` pasa a VES
- THEN el label MUST actualizarse a "VES" sin necesidad de re-abrir la pantalla

## Out of Scope

- `QuickActionId` adicionales: open AI assistant, batch import, snapshot, share dashboard.
- Atajos a páginas externas (browser, deep links a otras apps).
- Personalización de iconos por chip.
- Long-press para acción secundaria.
- Chips condicionales (ej. ocultar `openDebts` si el usuario no tiene deudas) — todos los chips se muestran siempre que estén en `config.chips`.
- Sincronización selectiva del `quickUse` independiente del layout.
