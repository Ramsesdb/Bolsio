# Exploration: dynamic-dashboard

## Topic

Convertir el dashboard de wallex en un sistema de widgets dinámicos con: catálogo intercambiable, defaults derivados de los `onboardingGoals`, modo edición (quitar/poner/reordenar) y un widget de "uso rápido" con atajos a settings y acciones frecuentes.

## Current State

- **Dashboard estático**: [`lib/app/home/dashboard.page.dart`](lib/app/home/dashboard.page.dart) (1040 líneas) compone manualmente: header, `HorizontalScrollableAccountList`, `_buildRatesCard`, `DashboardCards` (4 cards: salud financiera + 3 charts).
- **State management**: ningún provider/Bloc; servicios singleton (`Service.instance`) con streams `RxDart` (`BehaviorSubject` + `shareValue`/`distinct`).
- **Persistencia clave-valor**: `UserSettingService` (Drift) + map global `appStateSettings`. Patrón ya establecido para `onboardingGoals`, `preferredCurrency`, `preferredRateSource` (JSON-encoded en string).
- **HiddenModeService** [`lib/core/database/services/user-setting/hidden_mode_service.dart`](lib/core/database/services/user-setting/hidden_mode_service.dart):
  - `isLockedStream`: `BehaviorSubject<bool>.seeded(true).stream.distinct()` (l.74).
  - `visibleAccountIdsStream` (l.95): `Rx.combineLatest2(isLockedStream, getAccounts()).distinct(_listEquals).shareValue()` con caché lazy en `_visibleAccountIdsStream`. **Ya está compartido** — el dashboard hace **una sola** suscripción y propaga `visibleIds` por props.
- **Layout responsivo**: `ResponsiveRowColumn.withSymetricSpacing(direction: BreakPoint.of(context).isLargerThan(BreakpointID.md) ? Axis.horizontal : Axis.vertical, …)` ([`lib/app/home/widgets/dashboard_cards.dart:151`](lib/app/home/widgets/dashboard_cards.dart#L151)). Breakpoints en [`lib/core/presentation/responsive/app_breakpoints.dart`](lib/core/presentation/responsive/app_breakpoints.dart) (`md = 720px`).
- **Reorderable abstraction**: [`lib/core/presentation/widgets/wallex_reorderable_list.dart`](lib/core/presentation/widgets/wallex_reorderable_list.dart) envuelve `ReorderableListView.builder` con `itemBuilder`, `onReorder`, `totalItemCount`, `isOrderEnabled` y manejo de opacidad.
- **Onboarding** [`lib/app/onboarding/onboarding.dart`](lib/app/onboarding/onboarding.dart):
  - `_applyChoices()` (l.165–178): persiste `onboardingGoals`, `preferredCurrency`, `preferredRateSource` con `await UserSettingService.instance.setItem(...)` secuenciales.
  - Invocado en slide 9 Android (`_applyChoicesAndAdvance` l.305) y slide 5 iOS (l.267).
  - Tras s11_ready, `_completeOnboarding` (l.183) escribe `AppDataKey.introSeen='1'` con `updateGlobalState: true` y el router navega al dashboard.
  - `KeyValueService.setItem(updateGlobalState:true)` cachea en `globalStateMap` **antes** de la escritura DB y dispara `appStateKey.currentState?.refreshAppState()` ([`lib/core/database/services/shared/key_value_service.dart:34`](lib/core/database/services/shared/key_value_service.dart#L34)).
- **Firebase sync**: [`lib/core/services/firebase_sync_service.dart`](lib/core/services/firebase_sync_service.dart):
  - `pushUserSettings()` (l.326) sube **blob único** `users/{uid}/userSettings/all` con `{values: {k:v}}`.
  - Last-write-wins por `updatedAt`. No documenta límite (Firestore: 1 MiB/doc).
  - `_userSettingsSyncExclusions` + `_isSensitiveSettingKey` (l.312–321) filtran tokens y datos sensibles.
  - `pullAllData()` itera `raw['values']` y llama `setItem(key, value)` por entrada (l.362–407).

## Affected Areas

- [`lib/app/home/dashboard.page.dart`](lib/app/home/dashboard.page.dart) — refactor del cuerpo scrolleable a iteración sobre layout + edit mode.
- [`lib/app/home/widgets/dashboard_cards.dart`](lib/app/home/widgets/dashboard_cards.dart) — extraer cada card como widget independiente registrable.
- [`lib/app/home/widgets/horizontal_scrollable_account_list.dart`](lib/app/home/widgets/horizontal_scrollable_account_list.dart), [`income_or_expense_card.dart`](lib/app/home/widgets/income_or_expense_card.dart), [`balance_delta_pill.dart`](lib/app/home/widgets/balance_delta_pill.dart) — wrappers en `Spec`.
- [`lib/core/database/services/user-setting/user_setting_service.dart`](lib/core/database/services/user-setting/user_setting_service.dart) — añadir `SettingKey.dashboardLayout` y `SettingKey.dashboardQuickUseChips` (config widget independiente para tamaño manejable).
- [`lib/core/database/sql/initial/seed.dart`](lib/core/database/sql/initial/seed.dart) — seed con `'[]'` o layout default mínimo.
- [`lib/app/onboarding/onboarding.dart`](lib/app/onboarding/onboarding.dart) — `_applyChoices()` añade escritura de `dashboardLayout` con `updateGlobalState:true`.
- [`lib/core/services/firebase_sync_service.dart`](lib/core/services/firebase_sync_service.dart) — verificar que `dashboardLayout` NO esté en `_userSettingsSyncExclusions`.
- `main.dart` — registrar widgets en el `DashboardWidgetRegistry` antes de `runApp`.
- **Crear** `lib/app/home/dashboard_widgets/` con: `models/`, `services/`, `widgets/`, `edit/`, `registry.dart`, `defaults.dart`, `registry_bootstrap.dart`.

## Approaches

### Approach A — Widgets compuestos sobre `appStateSettings` con servicio de layout
**Descripción**: el layout se persiste como JSON en `SettingKey.dashboardLayout` (string), un `DashboardLayoutService` singleton lo expone como `BehaviorSubject<DashboardLayout>` aplicando migraciones por `schemaVersion`. Cada widget se construye desde un `DashboardWidgetRegistry` (mapa `WidgetType → Spec`). El dashboard suscribe el stream y reconstruye solo el cuerpo. Edit mode toggle local del `_DashboardPageState`. Persistencia con debouncer 300 ms.

- Pros: respeta el patrón actual (singleton + stream). Cero deps nuevas. Sincronización Firebase gratuita (ya cubre `userSettings`). Drop-in con migración de schema interna del JSON.
- Cons: cada vez que el usuario reordena rebuilds todo el cuerpo (aceptable: ≤10 widgets). Requiere disciplina para que cada widget consuma streams compartidos (`HiddenModeService.visibleAccountIdsStream` ya viene `shareValue()`).
- Effort: Medium.

### Approach B — Tabla Drift dedicada `dashboard_widgets`
**Descripción**: nueva tabla con columnas `instanceId`, `type`, `position`, `size`, `config` (JSON). Migración v27→v28.

- Pros: queries parciales posibles, futuras analíticas más simples.
- Cons: bump de schema Drift requiere build_runner; sync Firebase no cubre la tabla automáticamente — habría que escribir `pushDashboardWidgets`/`pullDashboardWidgets`. Sobre-ingeniería para ≤20 widgets.
- Effort: High.

### Approach C — `InheritedWidget` `DashboardStreamScope` + Approach A
**Descripción**: además de A, exponer streams compartidos (cuentas visibles, total balance, exchange rates) por `InheritedWidget`.

- Pros: cero re-suscripciones cuando el layout cambia; widgets más desacoplados.
- Cons: redundante — `HiddenModeService.visibleAccountIdsStream` ya hace `shareValue()`. La ganancia real es para totalBalance/transactionStreams, pero se puede aplicar **dentro** del `DashboardLayoutService` exponiéndolos como propiedades del scope solo si medimos un problema real de rebuilds.
- Effort: Low (incremental sobre A).

## Recommendation

**Approach A**, con la nota de C como mejora futura solo si DevTools muestra re-suscripciones costosas. Justificación:

1. La feature aún está en MVP — meter una tabla nueva (B) bloquea la velocidad y no aporta valor inmediato.
2. `HiddenModeService` ya está compartido; los demás streams (`AccountService.getAccounts()`, etc.) son baratos. El riesgo real de cascade es bajo.
3. Sync Firebase: `dashboardLayout` viaja gratis dentro del blob `userSettings/all`. JSON estimado < 4 KB, dentro del 1 MiB de Firestore.
4. Migración de versión: `schemaVersion` dentro del JSON permite evolucionar sin tocar Drift.

Configuración del `quickUse` (chips visibles + orden) se persiste **dentro** del `config` del descriptor del propio widget (no en una `SettingKey` separada) — coherente con el contrato de cada widget y serializable junto al layout.

## Risks

1. **Slide en el que se aplica `_applyChoices`**: en Android es slide 9 (`_applyChoicesAndAdvance`), en iOS slide 5. Hay que añadir la escritura del layout dentro de `_applyChoices` (un solo lugar) y NO en los call sites — patrón existente correcto.
2. **`HiddenModeService.isLockedStream`**: emite `true` por default (l.74). Si el dashboard renderiza un widget que muestra balances antes de que se desbloquee, se ven cuentas filtradas. Aceptable: el patrón actual ya es así.
3. **`_userSettingsSyncExclusions`**: confirmar en `firebase_sync_service.dart:312` que `dashboardLayout` NO esté excluido (queremos que sincronice entre dispositivos).
4. **Seed inicial vs onboarding fresh**: si el seed escribe `'[]'`, el dashboard arrancaría vacío. Solución: el dashboard al detectar layout vacío Y `introSeen='1'` aplica `DashboardLayoutDefaults.fallback()`; el path normal (recién terminó onboarding) ya tiene layout escrito por `_applyChoices`.
5. **Re-suscripciones a streams en edit mode**: si reordenamos widgets y cada uno tiene `StreamBuilder` propio, todos se re-suscriben. Mitigación: `Key(instanceId)` estable + uso de streams ya compartidos. Si DevTools muestra problema → mover a Approach C.
6. **Build_runner**: añadir `SettingKey.dashboardLayout` al enum **no requiere build_runner** (no es freezed). Sí requeriría si convertimos `WidgetDescriptor` en `@freezed`. Recomendación: hacerlo plain Dart con `toJson/fromJson` manuales — menos fricción.
7. **Returning user flow**: post Firebase sync, si el usuario tenía `dashboardLayout` en otro dispositivo, llega gratis. Si no, fallback. Verificar que `pullAllData` corre **antes** del primer render del dashboard — el código lo confirma (`returning_user_flow.dart` lo invoca antes de navegar).

## Ready for Proposal

**Yes**. La exploración respalda Approach A. Siguiente paso: `sdd-propose` para `dynamic-dashboard` consolidando el plan ya aprobado en formato proposal.md (intent, scope, approach, rollback, modules afectados).
