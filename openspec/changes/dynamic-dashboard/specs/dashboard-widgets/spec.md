# Domain: dashboard-widgets

## Purpose

Define el contrato del registry de widgets (`DashboardWidgetRegistry`, `DashboardWidgetSpec`), el inventario de widgets MVP (7 entradas), los streams que cada widget consume y los parámetros que lee de su `config`.

## Requirements

### Requirement: `DashboardWidgetSpec`

Cada widget MUST exponer un `DashboardWidgetSpec` con: `type: WidgetType`, `defaultSize: WidgetSize`, `allowedSizes: Set<WidgetSize>` (no vacío, contiene `defaultSize`), `defaultConfig: Map<String,dynamic>`, `builder: Widget Function(BuildContext, WidgetDescriptor, {bool editing})`, `displayName: String Function(BuildContext)` (i18n), `iconBuilder: IconData Function()`, `recommendedFor: Set<String>` (set de `onboardingGoals`), `configEditor: Widget Function(...)?` (opcional, solo para widgets con configuración editable).

`builder` MUST ser pure y NO MUST tener side effects fuera de subscribirse a streams ya compartidos.

### Requirement: `DashboardWidgetRegistry`

El registry MUST exponer:

- `register(DashboardWidgetSpec spec)`: lanza `StateError` si ya existe un spec del mismo `type`.
- `get(WidgetType type) -> DashboardWidgetSpec?`: retorna `null` si no existe.
- `recommendedFor(Set<String> goals) -> List<DashboardWidgetSpec>`: filtra y ordena por relevancia.
- `all() -> List<DashboardWidgetSpec>`: lista completa, orden de inserción.

El registry MUST inicializarse antes de `runApp` vía `registerDashboardWidgets()` (invocado desde `main.dart`).

#### Scenario: Registro doble del mismo type

- GIVEN un `WidgetType.totalBalanceSummary` ya registrado
- WHEN se invoca `register()` con otro spec del mismo type
- THEN MUST lanzar `StateError`

#### Scenario: Build con type ausente

- GIVEN un layout con un `WidgetDescriptor` cuyo `type` no existe en el registry
- WHEN el dashboard intenta construirlo
- THEN MUST omitirlo del render
- AND MUST loggear un warning (no crash)

### Requirement: Inventario MVP (7 widgets)

#### `totalBalanceSummary`

- `defaultSize`: `fullWidth`. `allowedSizes`: {`medium`, `fullWidth`}.
- `defaultConfig`: `{'currency': null, 'showDelta': true, 'period': '30d'}`.
- Consume: `HiddenModeService.visibleAccountIdsStream`, `AccountService.getAccountsBalance()` filtrado por la moneda efectiva.
- Cuando `config.currency` es `null`, MUST resolver a `preferredCurrency`.
- `recommendedFor`: {`track_expenses`, `save_usd`, `reduce_debt`, `budget`}.

##### Scenario: Hidden mode activo

- GIVEN `HiddenModeService.isLockedStream` emite `true` y hay 2 cuentas filtradas
- WHEN el widget calcula el total
- THEN MUST excluir las cuentas filtradas
- AND MUST mostrar el total restante con su delta

#### `accountCarousel`

- `defaultSize`: `fullWidth`. `allowedSizes`: {`fullWidth`}.
- `defaultConfig`: `{'showHidden': false}`.
- Consume: `HiddenModeService.visibleAccountIdsStream` + `AccountService.getAccounts()`.
- `recommendedFor`: {`save_usd`, `reduce_debt`}.

##### Scenario: Sin cuentas

- GIVEN un usuario sin cuentas
- WHEN se renderiza el widget
- THEN MUST mostrar empty state con CTA a "crear cuenta", NO MUST crashear

#### `incomeExpensePeriod`

- `defaultSize`: `medium`. `allowedSizes`: {`medium`, `fullWidth`}.
- `defaultConfig`: `{'period': '30d', 'currency': null}`.
- Consume: stream de transacciones por periodo + `visibleAccountIdsStream`.
- `recommendedFor`: {`track_expenses`, `budget`, `analyze`}.

##### Scenario: Periodo sin movimientos

- GIVEN un periodo sin transacciones
- WHEN se renderiza
- THEN MUST mostrar `0` en ingresos y gastos sin mensaje de error

#### `recentTransactions`

- `defaultSize`: `fullWidth`. `allowedSizes`: {`fullWidth`}.
- `defaultConfig`: `{'limit': 5, 'showCategories': true}`.
- Consume: `TransactionService` últimas N (cap entre 1 y 20).
- `recommendedFor`: {`track_expenses`, `reduce_debt`, `budget`, `analyze`}.

##### Scenario: limit fuera de rango

- GIVEN `config.limit = 50`
- WHEN se renderiza
- THEN MUST capar a 20

#### `exchangeRateCard`

- `defaultSize`: `medium`. `allowedSizes`: {`medium`, `fullWidth`}.
- `defaultConfig`: `{'pair': 'USD_VES', 'source': null}`.
- Consume: `ExchangeRateService` con `preferredRateSource` cuando `source` es `null`.
- `recommendedFor`: {`save_usd`, `analyze`}.

##### Scenario: Sin tasa disponible

- GIVEN el provider no devuelve tasa
- WHEN se renderiza
- THEN MUST mostrar último valor cacheado con timestamp
- AND si no hay caché, MUST mostrar "—" sin crashear

##### Scenario: Multi-currency par

- GIVEN `config.pair='USD_VES'` y `preferredCurrency='VES'`
- WHEN se renderiza
- THEN MUST mostrar el par tal cual (USD→VES) sin invertir

#### `quickUse`

- `defaultSize`: `fullWidth`. `allowedSizes`: {`fullWidth`}.
- `defaultConfig`: `{'chips': [<defaults>]}` — ver dominio `dashboard-quick-use`.
- `recommendedFor`: TODOS los goals (siempre presente).
- `configEditor`: NO `null` — abre bottom sheet de dos pestañas.

##### Scenario: Sin chips configurados

- GIVEN `config.chips = []`
- WHEN se renderiza
- THEN MUST mostrar empty state con CTA "Configurar atajos" que abre el `configEditor`

#### `pendingImportsAlert`

- `defaultSize`: `fullWidth`. `allowedSizes`: {`fullWidth`}.
- `defaultConfig`: `{}`.
- Consume: stream de auto-import service (notificaciones pendientes).
- Comportamiento: si hay 0 pendientes, MUST renderizar `SizedBox.shrink()` (ocupa cero alto, no rompe el grid).
- `recommendedFor`: ninguno por default (el usuario lo añade manualmente desde "Agregar widget").

##### Scenario: Sin pendientes

- GIVEN 0 imports pendientes
- WHEN se renderiza el widget
- THEN MUST devolver un widget de altura 0
- AND el reordenamiento del layout MUST mantener su posición lógica

### Requirement: Streams compartidos

Los widgets MUST suscribirse a streams ya compartidos (`shareValue()` o equivalente). En particular, `HiddenModeService.visibleAccountIdsStream` ya hace `shareValue()` y todos los widgets que necesiten cuentas visibles MUST consumirlo (no re-implementar el filtro).

#### Scenario: Múltiples widgets consumen visibleAccountIdsStream

- GIVEN 3 widgets activos que dependen de cuentas visibles
- WHEN el layout se renderiza
- THEN MUST haber exactamente UNA suscripción upstream a `getAccounts()`
- AND el toggle de hidden mode MUST reflejarse en los 3 widgets simultáneamente

### Requirement: Estabilidad por `instanceId`

Cada widget MUST construirse con `Key(ValueKey(descriptor.instanceId))` para que reordenamientos no fuercen rebuild ni re-suscripción a streams.

#### Scenario: Reorder de A y B

- GIVEN widgets A (instanceId=`u1`) y B (instanceId=`u2`)
- WHEN se invierte su orden en el layout
- THEN sus `State` y `StreamSubscription` MUST preservarse (no dispose/init)

## Out of Scope

- Widgets adicionales: AI tip, sparkline 30d, debts summary, goals progress, budget burn-down, savings rate, category breakdown extendido.
- Animaciones de entrada/salida custom.
- Drag-and-drop multi-columna.
- Configuración de tamaño por widget en MVP (queda en defaults declarados).
- Lazy load de widgets fuera de viewport.
