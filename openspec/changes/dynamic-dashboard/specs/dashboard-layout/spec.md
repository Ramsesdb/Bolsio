# Domain: dashboard-layout

## Purpose

Define el contrato del modelo de layout del dashboard dinámico de bolsio: estructuras de datos (`DashboardLayout`, `WidgetDescriptor`, `WidgetType`, `WidgetSize`), versionado/migraciones, persistencia en `SettingKey.dashboardLayout`, serialización JSON, defaults derivados de `onboardingGoals` y comportamiento de fallback.

## Requirements

### Requirement: Modelo `DashboardLayout`

El sistema MUST exponer una clase inmutable `DashboardLayout` con los campos: `schemaVersion: int` (entero positivo), `widgets: List<WidgetDescriptor>` (orden significativo, lista nunca `null`).

`DashboardLayout` MUST ofrecer `toJson()` y `fromJson(Map<String,dynamic>)` simétricos. Round-trip JSON SHALL preservar orden, `schemaVersion`, todos los `instanceId`, todos los `config`.

#### Scenario: Round-trip JSON preserva estado

- GIVEN un `DashboardLayout` con `schemaVersion=1` y 3 widgets en orden A, B, C
- WHEN se serializa con `toJson()` y se deserializa con `fromJson()`
- THEN el resultado MUST ser igual al original (mismo orden, mismos `instanceId`, mismos `config`)

#### Scenario: JSON malformado

- GIVEN una cadena JSON inválida o un `Map` sin clave `widgets`
- WHEN se invoca `DashboardLayout.fromJson()` o el parser de la persistencia
- THEN el sistema MUST tratarlo como layout vacío y aplicar el flujo de fallback (ver `Fallback`)
- AND NO MUST lanzar la excepción al consumer del stream

### Requirement: `WidgetDescriptor`

`WidgetDescriptor` MUST contener: `instanceId: String` (uuid v4 único dentro del layout), `type: WidgetType`, `size: WidgetSize`, `config: Map<String, dynamic>` (nunca `null`, default `{}`).

Dos descriptores en un mismo `DashboardLayout` MUST tener `instanceId` distintos. Si al deserializar se detectan duplicados, el sistema MUST regenerar los `instanceId` duplicados.

#### Scenario: instanceId duplicado en JSON

- GIVEN un layout persistido donde dos descriptores comparten `instanceId`
- WHEN se carga vía `DashboardLayoutService.load()`
- THEN el segundo (y subsiguientes) MUST recibir un nuevo `instanceId` v4
- AND el layout corregido MUST persistirse de vuelta

### Requirement: Enums `WidgetType` y `WidgetSize`

`WidgetType` MUST ser un enum cerrado con al menos: `totalBalanceSummary`, `accountCarousel`, `incomeExpensePeriod`, `recentTransactions`, `exchangeRateCard`, `quickUse`, `pendingImportsAlert`.

`WidgetSize` MUST ser un enum cerrado con: `medium` (≈50% del ancho), `fullWidth` (100%). NO MUST exponer otros tamaños en MVP.

Cuando se deserializa un `type` o `size` desconocido (versión futura), el descriptor MUST descartarse silenciosamente sin abortar la carga del layout completo.

#### Scenario: WidgetType desconocido

- GIVEN un layout con un descriptor cuyo `type='futureWidget'`
- WHEN se carga el layout
- THEN ese descriptor MUST descartarse
- AND el resto de widgets válidos MUST cargar normalmente
- AND el layout depurado MUST re-persistirse

### Requirement: Versionado y migrador

El layout MUST incluir `schemaVersion` (inicial = `1`). `DashboardLayoutService` MUST encadenar migraciones `vN → vN+1` antes de exponer el layout al consumer.

Si `schemaVersion` cargado es mayor que el conocido por el binario, el sistema MUST aplicar fallback (no romper la app de un usuario que downgradeó).

#### Scenario: Migración v1 a futuro v2

- GIVEN un layout almacenado con `schemaVersion=1`
- WHEN el binario tiene migrador hasta v2
- THEN el servicio MUST aplicar `migrateV1ToV2`, actualizar `schemaVersion=2`, persistir y emitir el resultado migrado

#### Scenario: schemaVersion futuro

- GIVEN `schemaVersion=99` cargado
- WHEN el binario solo soporta hasta v1
- THEN el sistema MUST aplicar fallback (`DashboardLayoutDefaults.fallback()`) y NO MUST sobrescribir el storage hasta que el usuario edite explícitamente

### Requirement: Persistencia en `SettingKey.dashboardLayout`

El sistema MUST persistir el layout serializado como `String` JSON en `SettingKey.dashboardLayout` (vía `UserSettingService`). NO MUST introducir tablas Drift dedicadas.

`SettingKey.dashboardLayout` MUST sincronizar vía `firebase_sync_service` (NO debe estar en `_userSettingsSyncExclusions`).

Las escrituras del servicio MUST estar debounced 300 ms; un `flush()` MUST forzar escritura inmediata (usado al salir de edit mode y en `dispose`).

#### Scenario: Múltiples ediciones rápidas

- GIVEN el usuario hace 5 reordenamientos en menos de 300 ms
- WHEN cada cambio invoca `save(layout)`
- THEN el sistema MUST escribir UNA sola vez en DB tras 300 ms desde la última edición
- AND el blob Firestore MUST recibir el último estado, no estados intermedios

#### Scenario: Salida de edit mode

- GIVEN un cambio pendiente en el debouncer
- WHEN el dashboard sale de edit mode o se llama `flush()`
- THEN la escritura MUST realizarse de inmediato sin esperar al timer

### Requirement: Defaults por `onboardingGoals`

`DashboardLayoutDefaults.fromGoals(Set<String>)` MUST mapear cada goal a un set de `WidgetType` recomendados:

| Goal | Widgets recomendados (orden) |
|------|------------------------------|
| `track_expenses` | `quickUse`, `totalBalanceSummary`, `recentTransactions`, `incomeExpensePeriod` |
| `save_usd` | `quickUse`, `totalBalanceSummary` (USD), `exchangeRateCard`, `accountCarousel` |
| `reduce_debt` | `quickUse`, `totalBalanceSummary`, `accountCarousel`, `recentTransactions` |
| `budget` | `quickUse`, `totalBalanceSummary`, `incomeExpensePeriod`, `recentTransactions` |
| `analyze` | `quickUse`, `incomeExpensePeriod`, `recentTransactions`, `exchangeRateCard` |

La unión MUST: deduplicar por `WidgetType` (primera aparición gana), preservar el orden de selección de los goals, garantizar `quickUse` siempre presente y en posición 0, capar el total a 8 widgets.

#### Scenario: Goal único `save_usd`

- GIVEN `onboardingGoals = {'save_usd'}` y `preferredCurrency='USD'`
- WHEN se invoca `DashboardLayoutDefaults.fromGoals({'save_usd'})`
- THEN el layout MUST contener exactamente: `quickUse`, `totalBalanceSummary` (con `config.currency='USD'`), `exchangeRateCard`, `accountCarousel`

#### Scenario: Multi-goal con dedup

- GIVEN `onboardingGoals = {'track_expenses', 'budget', 'analyze'}`
- WHEN se invoca `fromGoals(...)`
- THEN el layout MUST tener `quickUse` en posición 0
- AND NO MUST repetir `WidgetType` (un solo `recentTransactions`, un solo `incomeExpensePeriod`)
- AND el total de widgets MUST ser ≤ 8

#### Scenario: Cap a 8 widgets

- GIVEN una unión de goals que produciría 12 widgets
- WHEN se aplica el cap
- THEN solo los primeros 8 (después de dedup) MUST quedar en el layout

### Requirement: Fallback

`DashboardLayoutDefaults.fallback()` MUST devolver: `quickUse`, `totalBalanceSummary` (en `preferredCurrency`), `accountCarousel`, `recentTransactions`.

El dashboard MUST aplicar `fallback()` cuando: `dashboardLayout` cargado es vacío/null/JSON inválido AND `introSeen='1'`. Tras aplicar fallback, MUST persistirlo para no recalcularlo en próximos arranques.

#### Scenario: Returning user sin layout en Firebase

- GIVEN un usuario logueado con `introSeen='1'` cuyo blob `userSettings/all` no incluye `dashboardLayout`
- WHEN el dashboard arranca tras `pullAllData()`
- THEN MUST aplicar `fallback()` y renderizar 4 widgets
- AND MUST persistir el layout vía `save()` para que se sincronice

#### Scenario: introSeen='0' con layout vacío

- GIVEN un usuario que aún no terminó onboarding
- WHEN el dashboard fuera renderizado por algún motivo (no debería pasar, pero defensivo)
- THEN NO MUST aplicar fallback (el flujo de onboarding lo escribirá en `_applyChoices`)

### Requirement: Multi-currency en widgets

Cuando un widget consume importes monetarios y su `config.currency` es `null`, MUST usar `preferredCurrency` (USD o VES) del usuario. Cuando `config.currency` es explícito, MUST respetarlo aún si difiere de `preferredCurrency`.

#### Scenario: Usuario VES con widget `totalBalanceSummary` config USD

- GIVEN `preferredCurrency='VES'` y un descriptor con `config={'currency': 'USD'}`
- WHEN el widget se renderiza
- THEN MUST mostrar el total en USD (no convertido a VES)

## Out of Scope

- Tabla Drift dedicada `dashboard_widgets`.
- Multi-dashboard (más de una página configurable).
- Resize libre por el usuario más allá de `medium` / `fullWidth`.
- Migración de usuarios legacy (la app no se ha publicado).
- Sincronización selectiva por widget (todo viaja en el blob completo `userSettings/all`).
- Compresión del JSON (estimado < 4 KB).
