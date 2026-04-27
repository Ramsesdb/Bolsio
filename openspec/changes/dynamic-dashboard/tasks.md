# Tasks: Dashboard de widgets dinámicos

## Decisiones tomadas

Estas tres open questions del `design.md` quedan resueltas para guiar la implementación:

1. **Chips de `quickUse`**: se persisten dentro de `WidgetDescriptor.config['chips']` (lista de strings con `QuickActionId.name`). NO se introduce `SettingKey.dashboardQuickUseChips`. Razón: coherencia con el contrato de cada widget y serialización conjunta con el resto del layout.
2. **Cap de 8 widgets**: aplica a widgets renderizados por el usuario. `quickUse` cuenta hacia el cap. `pendingImportsAlert` cuenta SOLO cuando `count > 0` (cuando renderiza `SizedBox.shrink()` no consume slot visible). El cap se enforce en `DashboardLayoutDefaults.fromGoals` pero NO en edit mode (el usuario puede superar 8 manualmente si quiere).
3. **Unicidad de `incomeExpensePeriod`**: SE PERMITEN múltiples instancias con `config` distinto (ej. uno solo income con `period='30d'`, otro solo expense con `period='90d'`). El `instanceId` v4 garantiza unicidad lógica. El registry NO fuerza singletons salvo que el `DashboardWidgetSpec.unique == true` (ningún widget MVP marca `unique=true`).

## Mapa de oleadas mergeables

| Wave | Fases incluidas | Mergeable cuando |
|------|-----------------|------------------|
| Wave 1 | Phase 1 + Phase 2.1 | Modelos, persistencia, registry, sync verify y wrappers de widgets actuales (refactor sin cambio funcional) |
| Wave 2 | Phase 2.2 + Phase 2.3 | Renderizado dinámico del dashboard + defaults de onboarding |
| Wave 3 | Phase 2.4 + Phase 2.5 + Phase 3 + Phase 4 | Edit mode, quickUse, testing y polish |

---

## Phase 1: Infrastructure

### 1.1 Crear `WidgetSize`, `WidgetType`, `QuickActionId` enums

- [x] Archivo: `lib/app/home/dashboard_widgets/models/widget_descriptor.dart` (Create — solo enums por ahora)
- Spec: `dashboard-layout` § Enums `WidgetType` y `WidgetSize`; `dashboard-quick-use` § Enum `QuickActionId`
- Estimación: XS
- Dependencias: ninguna

### 1.2 Crear clase `WidgetDescriptor` con `toJson` / `fromJson` / `copyWith`

- [x] Archivo: `lib/app/home/dashboard_widgets/models/widget_descriptor.dart` (Modify — añadir clase)
- Spec: `dashboard-layout` § Modelo `WidgetDescriptor` (Scenario instanceId duplicado)
- Estimación: S
- Dependencias: 1.1

### 1.3 Crear clase `DashboardLayout` con `schemaVersion` y `toJson` / `fromJson`

- [x] Archivo: `lib/app/home/dashboard_widgets/models/dashboard_layout.dart` (Create)
- Spec: `dashboard-layout` § Modelo `DashboardLayout` (Scenario round-trip JSON, JSON malformado)
- Estimación: S
- Dependencias: 1.2

### 1.4 Crear `DashboardLayoutMigrator` (v1 → vN)

- [x] Archivo: `lib/app/home/dashboard_widgets/models/migrator.dart` (Create)
- Spec: `dashboard-layout` § Versionado y migrador (Scenario migración v1→v2, schemaVersion futuro)
- Estimación: S
- Dependencias: 1.3

### 1.5 Añadir `SettingKey.dashboardLayout` al enum existente

- [x] Archivo: `lib/core/database/services/user-setting/user_setting_service.dart` (Modify)
- Archivo: `lib/core/database/sql/initial/seed.dart` (Modify — seed con `'[]'`)
- Spec: `dashboard-layout` § Persistencia en `SettingKey.dashboardLayout`
- Estimación: XS
- Dependencias: ninguna (puede correr en paralelo con 1.1–1.4)

### 1.6 Verificar que `dashboardLayout` NO está en `_userSettingsSyncExclusions`

- [x] Archivo: `lib/core/services/firebase_sync_service.dart` (Verify only — sin cambios de código)
- Spec: `dashboard-layout` § Persistencia en `SettingKey.dashboardLayout` (sync vía `firebase_sync_service`)
- Estimación: XS
- Dependencias: 1.5

### 1.7 Crear `DashboardLayoutService` singleton (load/save/flush)

- [x] Archivo: `lib/app/home/dashboard_widgets/services/dashboard_layout_service.dart` (Create)
- Implementa: `BehaviorSubject<DashboardLayout>`, `load()`, `save()` con debouncer 300 ms, `flush()` síncrono
- Spec: `dashboard-layout` § Persistencia (Scenarios múltiples ediciones rápidas, salida edit mode)
- Estimación: M
- Dependencias: 1.3, 1.4, 1.5

### 1.8 Añadir métodos de mutación al service (`add`, `removeByInstanceId`, `reorder`, `updateConfig`, `resetToFallback`)

- [x] Archivo: `lib/app/home/dashboard_widgets/services/dashboard_layout_service.dart` (Modify)
- Spec: `dashboard-edit-mode` § Persistencia con debounce
- Estimación: S
- Dependencias: 1.7

### 1.9 Crear `DashboardWidgetRegistry` y `DashboardWidgetSpec`

- [x] Archivo: `lib/app/home/dashboard_widgets/registry.dart` (Create)
- API: `register`, `get`, `recommendedFor(Set<String> goals)`, `all()`
- Spec: `dashboard-widgets` § `DashboardWidgetRegistry` (Scenario registro doble, build con type ausente)
- Estimación: S
- Dependencias: 1.1

### 1.10 Crear `registry_bootstrap.dart` con `registerDashboardWidgets()` (placeholder vacío)

- [x] Archivo: `lib/app/home/dashboard_widgets/registry_bootstrap.dart` (Create)
- Estimación: XS
- Dependencias: 1.9

### 1.11 Invocar `registerDashboardWidgets()` desde `main.dart` antes de `runApp`

- [x] Archivo: `lib/main.dart` (Modify)
- Spec: `dashboard-widgets` § `DashboardWidgetRegistry` ("MUST inicializarse antes de runApp")
- Estimación: XS
- Dependencias: 1.10

---

## Phase 2: Implementation MVP

### Phase 2.1: Wrappers de widgets actuales (refactor sin cambio funcional)

#### 2.1.1 Crear `TotalBalanceSummaryWidget` envolviendo `_buildTotalBalance`

- [x] Archivo: `lib/app/home/dashboard_widgets/widgets/total_balance_summary_widget.dart` (Create)
- Refactor: extraer lógica de `dashboard.page.dart::_buildTotalBalance` sin cambio funcional
- Registrar `DashboardWidgetSpec` en `registry_bootstrap.dart`
- Spec: `dashboard-widgets` § `totalBalanceSummary` (Scenario hidden mode activo)
- Estimación: S
- Dependencias: 1.9, 1.10

#### 2.1.2 Crear `AccountCarouselWidget` envolviendo `HorizontalScrollableAccountList`

- [x] Archivo: `lib/app/home/dashboard_widgets/widgets/account_carousel_widget.dart` (Create)
- Registrar spec en bootstrap
- Spec: `dashboard-widgets` § `accountCarousel` (Scenario sin cuentas)
- Estimación: S
- Dependencias: 1.9, 1.10

#### 2.1.3 Crear `IncomeExpensePeriodWidget` envolviendo `IncomeOrExpenseCard`

- [x] Archivo: `lib/app/home/dashboard_widgets/widgets/income_expense_period_widget.dart` (Create)
- Registrar spec en bootstrap
- Spec: `dashboard-widgets` § `incomeExpensePeriod` (Scenario periodo sin movimientos)
- Estimación: S
- Dependencias: 1.9, 1.10

#### 2.1.4 Crear `RecentTransactionsWidget` (lista corta con tap → ruta)

- [x] Archivo: `lib/app/home/dashboard_widgets/widgets/recent_transactions_widget.dart` (Create)
- Registrar spec en bootstrap
- Spec: `dashboard-widgets` § `recentTransactions` (Scenario limit fuera de rango)
- Estimación: S
- Dependencias: 1.9, 1.10

#### 2.1.5 Crear `ExchangeRateCardWidget` extrayendo `_buildRatesCard`

- [x] Archivo: `lib/app/home/dashboard_widgets/widgets/exchange_rate_card_widget.dart` (Create)
- Refactor: extraer `_buildRatesCard` sin cambio funcional
- Registrar spec en bootstrap
- Spec: `dashboard-widgets` § `exchangeRateCard` (Scenario sin tasa, multi-currency par)
- Estimación: S
- Dependencias: 1.9, 1.10

#### 2.1.6 Crear `PendingImportsAlertWidget` (con `SizedBox.shrink()` cuando count=0)

- [x] Archivo: `lib/app/home/dashboard_widgets/widgets/pending_imports_alert_widget.dart` (Create)
- Registrar spec en bootstrap
- Spec: `dashboard-widgets` § `pendingImportsAlert` (Scenario sin pendientes)
- Estimación: S
- Dependencias: 1.9, 1.10

### Phase 2.2: Renderizado dinámico (refactor `dashboard.page.dart`)

#### 2.2.1 Reemplazar el body scrolleable por `StreamBuilder<DashboardLayout>`

- [x] Archivo: `lib/app/home/dashboard.page.dart` (Modify)
- Mantener header fijo. Renderizar widgets desde `DashboardLayoutService.instance.stream` iterando con `WidgetDescriptor.size` (grid 2-col agrupando `medium` adyacentes / `fullWidth` ocupa fila completa).
- Cada widget envuelto en `KeyedSubtree(key: ValueKey(descriptor.instanceId))`
- Spec: `dashboard-widgets` § Estabilidad por `instanceId` (Scenario reorder de A y B)
- Estimación: M
- Dependencias: 2.1.1, 2.1.2, 2.1.3, 2.1.4, 2.1.5, 2.1.6

#### 2.2.2 Implementar fallback en `initState`

- [x] Archivo: `lib/app/home/dashboard.page.dart` (Modify)
- Detectar `dashboardLayout` vacío Y `appStateSettings[AppDataKey.introSeen] == '1'` → aplicar `DashboardLayoutDefaults.fallback()` y persistir
- Spec: `dashboard-layout` § Fallback (Scenario returning user sin layout, introSeen='0' con layout vacío)
- Estimación: S
- Dependencias: 2.2.1, 2.3.1

#### 2.2.3 Borrar/limpiar el código estático legacy detrás de feature flag de pánico

- [x] Archivo: `lib/app/home/dashboard.page.dart` (Modify)
- Mantener branch `appStateSettings['dashboardDynamicEnabled']` para rollback (default `'1'`)
- Estimación: S
- Dependencias: 2.2.1

### Phase 2.3: Defaults de onboarding

#### 2.3.1 Crear `DashboardLayoutDefaults.fromGoals` y `.fallback`

- [x] Archivo: `lib/app/home/dashboard_widgets/defaults.dart` (Create)
- Mapping de la tabla del spec, dedupe por `WidgetType` (primera aparición), `quickUse` siempre en posición 0, cap a 8
- Spec: `dashboard-layout` § Defaults por `onboardingGoals` (Scenarios goal único, multi-goal dedup, cap 8)
- Spec: `dashboard-layout` § Fallback
- Estimación: M
- Dependencias: 1.9 (registry para resolver `defaultConfig` por type), 1.3

#### 2.3.2 Hook en `_applyChoices()` del onboarding

- [x] Archivo: `lib/app/onboarding/onboarding.dart` (Modify)
- Tras persistir `onboardingGoals`, escribir `DashboardLayoutDefaults.fromGoals(goals).toJson()` con `setItem(SettingKey.dashboardLayout, ..., updateGlobalState: true)`
- Spec: `dashboard-layout` § Defaults (Scenario goal único `save_usd`); proposal.md Success Criteria #1
- Estimación: S
- Dependencias: 2.3.1

### Phase 2.4: Edit mode

#### 2.4.1 Toggle local `_editing` + botón lápiz/check en header

- [x] Archivo: `lib/app/home/dashboard.page.dart` (Modify)
- Spec: `dashboard-edit-mode` § Toggle de edit mode (Scenarios entrar/salir, botón retroceso)
- Estimación: S
- Dependencias: 2.2.1

#### 2.4.2 Crear `EditableWidgetFrame` (X + drag handle + borde distintivo)

- [x] Archivo: `lib/app/home/dashboard_widgets/edit/editable_widget_frame.dart` (Create)
- Absorbe gestos internos del widget durante edición
- Spec: `dashboard-edit-mode` § Edit frame (Scenario tap en contenido durante edición)
- Estimación: S
- Dependencias: 1.9

#### 2.4.3 Renderizar `WallexReorderableList` con todos los widgets en `fullWidth` cuando `_editing`

- [x] Archivo: `lib/app/home/dashboard.page.dart` (Modify)
- `onReorder` invoca `DashboardLayoutService.reorder(from, to)` (debounce 300 ms)
- `Key(ValueKey(instanceId))` por item
- Spec: `dashboard-edit-mode` § Drag-and-drop (Scenario reordenar tres widgets)
- Estimación: M
- Dependencias: 2.4.1, 2.4.2, 1.8

#### 2.4.4 Diálogo de confirmación al tocar X + remove + persist

- [x] Archivo: `lib/app/home/dashboard.page.dart` (Modify) + uso de `EditableWidgetFrame`
- Spec: `dashboard-edit-mode` § Eliminación con confirmación (Scenarios eliminar widget, eliminar quickUse)
- Estimación: S
- Dependencias: 2.4.2, 1.8

#### 2.4.5 Crear `_AddWidgetSheet` con secciones "Recomendados" / "Todos los widgets"

- [x] Archivo: `lib/app/home/dashboard_widgets/edit/add_widget_sheet.dart` (Create)
- Lee `onboardingGoals` desde `appStateSettings`. Marca recomendados con badge. Tap añade nuevo `WidgetDescriptor` con `instanceId` v4 y `defaultConfig` del spec
- Spec: `dashboard-edit-mode` § Bottom sheet (Scenarios goals=save_usd, múltiples instancias)
- Estimación: M
- Dependencias: 1.8, 1.9

#### 2.4.6 Botón "+ Agregar widget" visible solo en edit mode al final de la lista

- [x] Archivo: `lib/app/home/dashboard.page.dart` (Modify)
- Estimación: XS
- Dependencias: 2.4.3, 2.4.5

#### 2.4.7 `flush()` en salida de edit mode, `dispose` y `AppLifecycleState.paused`

- [x] Archivo: `lib/app/home/dashboard.page.dart` (Modify)
- Spec: `dashboard-edit-mode` § Persistencia con debounce (Scenario backgrounded durante edición)
- Estimación: S
- Dependencias: 2.4.1, 1.8

### Phase 2.5: Widget `quickUse` + configEditor

#### 2.5.1 Crear `QuickActionId` callbacks y `QuickActionRegistry`

- [x] Archivo: `lib/app/home/dashboard_widgets/widgets/quick_action_registry.dart` (Create)
- Toggles, navegación, quick transactions. `run(id, ctx)` con warning si no registrado
- Spec: `dashboard-quick-use` § Mapping action→callback (Scenarios toggleHiddenMode, togglePreferredCurrency, addExpense, huérfano)
- Estimación: M
- Dependencias: 1.1

#### 2.5.2 Crear `QuickUseWidget` que renderiza chips desde `descriptor.config['chips']`

- [x] Archivo: `lib/app/home/dashboard_widgets/widgets/quick_use_widget.dart` (Create)
- Suscribirse a `PrivateModeService.stream` y stream de `preferredCurrency` para labels reactivos
- Empty state cuando `chips=[]` con CTA "Configurar atajos"
- Registrar spec en bootstrap con `defaultConfig.chips = ['toggleHiddenMode','addExpense','addIncome','openTransactions','openExchangeRates']`
- Spec: `dashboard-widgets` § `quickUse` (Scenario sin chips); `dashboard-quick-use` § Defaults; § Multi-currency (Scenario label reactivo)
- Estimación: M
- Dependencias: 2.5.1, 1.9, 1.10

#### 2.5.3 Crear `QuickUseConfigSheet` con dos pestañas (Atajos / Orden)

- [x] Archivo: `lib/app/home/dashboard_widgets/edit/quick_use_config_sheet.dart` (Create)
- Pestaña 1: chips por categoría (toggle / navigation / quickTx) con check visual
- Pestaña 2: `WallexReorderableList` de chips seleccionados
- Cierre por botón "Listo" o swipe-down → persist `config.chips` vía `DashboardLayoutService.updateConfig`
- Spec: `dashboard-quick-use` § configEditor (Scenarios selección y reorden, swipe-down, sin chips)
- Estimación: M
- Dependencias: 2.5.1, 1.8

#### 2.5.4 Conectar `configEditor` del spec de `quickUse` al `QuickUseConfigSheet`

- [x] Archivo: `lib/app/home/dashboard_widgets/widgets/quick_use_widget.dart` (Modify) o bootstrap
- Spec: `dashboard-widgets` § `quickUse` (`configEditor` no `null`)
- Estimación: XS
- Dependencias: 2.5.2, 2.5.3

---

## Phase 3: Testing

### 3.1 Unit test: round-trip JSON `DashboardLayout` (todos los `WidgetType`)

- [x] Archivo: `test/dashboard_widgets/serialization_test.dart` (Create)
- Spec: `dashboard-layout` § Modelo `DashboardLayout` (Scenario round-trip)
- Estimación: S
- Dependencias: 1.3

### 3.2 Unit test: `DashboardLayoutMigrator` (v1, futuro, type/size desconocido descartado, instanceId duplicado regenerado)

- [x] Archivo: `test/dashboard_widgets/migrator_test.dart` (Create)
- Spec: `dashboard-layout` § Versionado y migrador; § Modelo `WidgetDescriptor` Scenario instanceId duplicado
- Estimación: S
- Dependencias: 1.4

### 3.3 Unit test: `DashboardLayoutDefaults.fromGoals` (combinaciones canónicas, dedup, cap 8, fallback)

- [x] Archivo: `test/dashboard_widgets/defaults_test.dart` (Create)
- Casos: `{}`, `{save_usd}`, `{track_expenses, budget}`, `{save_usd, reduce_debt, analyze, track_expenses, budget}`
- Spec: `dashboard-layout` § Defaults; § Fallback
- Estimación: S
- Dependencias: 2.3.1

### 3.4 Unit test: `DashboardWidgetRegistry` cubre todos los `WidgetType.values`

- [x] Archivo: `test/dashboard_widgets/registry_test.dart` (Create)
- Spec: `dashboard-widgets` § `DashboardWidgetRegistry` (Scenarios registro doble, build con type ausente)
- Estimación: XS
- Dependencias: 1.9, 1.10 + todos los 2.1.x

### 3.5 Unit test: `DashboardLayoutService` debouncer (5 saves → 1 escritura, flush fuerza inmediato)

- [x] Archivo: `test/dashboard_widgets/dashboard_layout_service_test.dart` (Create)
- Usa `package:fake_async`
- Spec: `dashboard-layout` § Persistencia (Scenarios múltiples ediciones, salida edit mode)
- Estimación: S
- Dependencias: 1.7

### 3.6 Widget test: `DashboardPage` renderiza N items según layout dado (mock service)

- [x] Archivo: `test/dashboard_widgets/dashboard_render_test.dart` (Create)
- Spec: `dashboard-widgets` § Estabilidad por `instanceId`
- Estimación: M
- Dependencias: 2.2.1

### 3.6b Widget test: layout vacío + introSeen='1' aplica fallback() (Wave 3B add)

- [x] Archivo: `test/dashboard_widgets/dashboard_fallback_test.dart` (Create)
- Spec: `dashboard-layout` § Fallback (Scenario "returning user sin layout en Firebase")
- Estimación: S
- Dependencias: 2.2.2, 2.3.1

### 3.7 Widget test: edit mode toggle envuelve cada item en `EditableWidgetFrame`

- [x] Archivo: `test/dashboard_widgets/edit_mode_test.dart` (Create)
- Spec: `dashboard-edit-mode` § Toggle, § Edit frame
- Estimación: S
- Dependencias: 2.4.1, 2.4.2, 2.4.3

### 3.8 Widget test: drag reorder persiste el nuevo orden

- [x] Archivo: `test/dashboard_widgets/edit_reorder_test.dart` (Create)
- `WidgetTester.drag` sobre `WallexReorderableList`
- Spec: `dashboard-edit-mode` § Drag-and-drop (Scenario reordenar tres widgets)
- Estimación: M
- Dependencias: 2.4.3

### 3.9 Widget test: `_AddWidgetSheet` muestra recomendados según goals y permite múltiples instancias

- [x] Archivo: `test/dashboard_widgets/add_widget_sheet_test.dart` (Create)
- Spec: `dashboard-edit-mode` § Bottom sheet (Scenarios goals=save_usd, múltiples instancias)
- Estimación: S
- Dependencias: 2.4.5

### 3.10 Widget test: `QuickUseConfigSheet` selección + reorden persiste `config.chips`

- [skipped] Archivo: `test/dashboard_widgets/quick_use_config_test.dart` (Create)
- **Wave 3B note**: el prompt explícito de Wave 3B sustituyó este slot por
  el fallback test (`dashboard_fallback_test.dart`, marcado como 3.6b). La
  cobertura de `quickUse` config queda en el manual checklist (Success
  Criterion #6 en `verify-checklist.md`).
- Spec: `dashboard-quick-use` § configEditor (Scenarios selección y reorden, swipe-down, sin chips)
- Estimación: M
- Dependencias: 2.5.3

### 3.11 Manual E2E checklist (proposal.md Success Criteria)

- [x] Archivo: `openspec/changes/dynamic-dashboard/verify-checklist.md` (Create)
- Checklist con todos los Success Criteria de `proposal.md`. Verificar en POCO arm64-v8a release sin obfuscate ni split-debug-info (recipe oficial wallex)
- Estimación: M
- Dependencias: todas las anteriores de Phase 2

---

## Phase 4: Polish

### 4.1 i18n de `displayName` y descripciones de los 7 widgets

- [x] Archivo: `lib/i18n/json/en.json` + `lib/i18n/json/es.json` (Modify)
- [x] Reemplazo de string literales por `Translations.of(ctx).home.dashboard_widgets.{type}.name/description` en los 7 register{...}Widget()
- [x] `dart run slang` regenera `lib/i18n/generated/translations*.g.dart`
- Claves: `dashboard.widgets.{type}.name`, `dashboard.widgets.{type}.description`
- Ejecutar `dart run slang` tras editar JSON
- Spec: `dashboard-widgets` § `DashboardWidgetSpec` (`displayName` i18n via slang)
- Estimación: S
- Dependencias: 2.1.1–2.1.6, 2.5.2

### 4.2 i18n de `QuickActionId.displayName` (chips del quickUse)

- [x] Archivo: `lib/i18n/json/en.json` + `lib/i18n/json/es.json` (Modify)
- [x] Reemplazo de string literales por `Translations.of(ctx).home.quick_actions.{id}` en `quick_action_dispatcher.dart::kQuickActions`. `togglePreferredCurrency` mantiene su label dinámico (USD/VES/DUAL) deliberadamente.
- Spec: `dashboard-quick-use` § Enum `QuickActionId`
- Estimación: S
- Dependencias: 2.5.1

### 4.3 Botón "Restablecer según mis objetivos" en overflow menu del header

- [x] Archivo: `lib/app/home/dashboard.page.dart` (Modify) — `PopupMenuButton` con `reset_to_goals_action` que en modo view abre `AlertDialog` y, al confirmar, llama `DashboardLayoutDefaults.fromGoals(currentGoals)` + `service.resetToFallback(layout)` + `flush()`.
- Confirmación + `DashboardLayoutService.resetToFallback()` (variante que reaplica `fromGoals(currentGoals)`)
- Estimación: S
- Dependencias: 1.8, 2.3.1

### 4.4 Animaciones de entrada/salida en edit mode (default Flutter, sin animaciones custom)

- [x] Archivo: `lib/app/home/dashboard_widgets/edit/editable_widget_frame.dart` (Modify — `TweenAnimationBuilder` 250 ms, scale 0.98→1.0 + fade)
- [x] Archivo: `lib/app/home/dashboard.page.dart` (Modify — `AnimatedSwitcher(300 ms, FadeTransition)` envolviendo el body view↔edit; banner usa `AnimatedSwitcher` 250 ms)
- `AnimatedSwitcher` o `AnimatedSize` para transición view ↔ edit
- Estimación: S
- Dependencias: 2.4.2, 2.4.3
