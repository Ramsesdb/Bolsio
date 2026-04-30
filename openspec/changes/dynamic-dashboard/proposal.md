# Proposal: Dashboard de widgets dinámicos

## Intent

El dashboard actual de bolsio ([`lib/app/home/dashboard.page.dart`](../../../lib/app/home/dashboard.page.dart), 1040 líneas) es estático: header + carrusel de cuentas + tasas + 4 cards fijos. El usuario no puede añadir, quitar ni reordenar bloques, y los `onboardingGoals` capturados (`track_expenses`, `save_usd`, `reduce_debt`, `budget`, `analyze`) no influyen en lo que ve al terminar el onboarding.

Esta propuesta convierte el dashboard en un sistema de widgets dinámicos: catálogo registrable, defaults derivados de los goals, modo edición (quitar / poner / reordenar) y un widget `quickUse` con atajos configurables. Hace que el onboarding deje de ser cosmético y entrega control real sobre la pantalla principal.

## Scope

### In Scope

- Modelo de datos (`WidgetDescriptor`, `WidgetSize`, `DashboardLayout`) con `schemaVersion` y `instanceId` (uuid v4).
- Persistencia JSON en `SettingKey.dashboardLayout` (sin tabla nueva en Drift) + `DashboardLayoutService` singleton (`load` / `save` con debouncer 300 ms / `flush`).
- `DashboardWidgetRegistry` + `registry_bootstrap.dart` invocado desde `main.dart`.
- **Catálogo MVP de 7 widgets**: `totalBalanceSummary`, `accountCarousel`, `incomeExpensePeriod`, `recentTransactions`, `exchangeRateCard`, `quickUse`, `pendingImportsAlert`.
- **Tamaños fijos** por widget: `medium` (≈50 %) o `fullWidth`. El usuario no resize.
- **Defaults por onboarding goals**: `DashboardLayoutDefaults.fromGoals(Set<String>)` aplicado dentro de `_applyChoices()`.
- **Modo edición**: toggle local `_editing` en `_DashboardPageState`, `ReorderableListView` (todo `fullWidth` mientras se edita), botón `X` por widget, `_AddWidgetSheet` con marcado de recomendados.
- **Widget `quickUse`**: chips configurables (toggles, atajos a páginas, quick actions tx) editables desde `configEditor` (bottom sheet de dos pestañas).
- Seed inicial de `dashboardLayout` en [`lib/core/database/sql/initial/seed.dart`](../../../lib/core/database/sql/initial/seed.dart) con `'[]'` (fallback aplicado en `initState` cuando se detecte vacío e `introSeen='1'`).

### Out of Scope (oleadas posteriores)

- Tabla Drift dedicada `dashboard_widgets` (Approach B descartado).
- Multi-dashboard (varias páginas tipo home/budgets/analytics).
- Resize de widgets por el usuario más allá de los dos tamaños fijos.
- Widgets adicionales: AI tip widget, sparkline 30d, debts summary, goals progress, budget burn-down, savings rate, category breakdown extendido.
- Migración de usuarios existentes (la app aún no se ha publicado; no hay legacy a preservar).
- Drag-and-drop multi-columna en edit mode (`reorderable_grid_view` queda para fase 2).
- Botón "Restablecer según mis objetivos" en el header (polish posterior).
- Animaciones de entrada/salida custom de los widgets (default Flutter es suficiente para MVP).

## Approach

**Approach A** de la exploración: el layout se persiste como JSON en `SettingKey.dashboardLayout` (string), `DashboardLayoutService` lo expone vía `BehaviorSubject<DashboardLayout>` aplicando migraciones por `schemaVersion`, y el dashboard suscribe el stream y reconstruye solo el cuerpo. Cada widget se construye desde el `DashboardWidgetRegistry` (mapa `WidgetType → DashboardWidgetSpec`).

Justificación (de la exploración):

1. La feature está en MVP — añadir tabla Drift bloquea velocidad sin valor inmediato.
2. `HiddenModeService.visibleAccountIdsStream` ya hace `shareValue()`; los demás streams son baratos. Cascade de re-suscripciones es bajo riesgo.
3. Sync Firebase: `dashboardLayout` viaja gratis en el blob `users/{uid}/userSettings/all` (JSON estimado < 4 KB, dentro del 1 MiB de Firestore).
4. `schemaVersion` interno permite evolucionar sin tocar Drift ni `build_runner` para los modelos.

`DashboardStreamScope` (`InheritedWidget`) queda como mejora futura si DevTools muestra re-suscripciones costosas — no se incluye en MVP.

Configuración del `quickUse` (chips visibles + orden) se persiste **dentro** del `config` del descriptor del propio widget — coherente con el contrato de cada spec y serializable junto al layout.

## Affected Areas

| Área | Impacto | Descripción |
|------|--------|-------------|
| `lib/app/home/dashboard_widgets/` | Nuevo | Carpeta entera: `models/`, `services/`, `widgets/`, `edit/`, `registry.dart`, `defaults.dart`, `registry_bootstrap.dart`. |
| `lib/app/home/dashboard.page.dart` | Modified | Cuerpo scrolleable se vuelve dinámico; header fijo. Toggle `_editing`. `initState` aplica fallback si layout vacío. |
| `lib/app/home/widgets/dashboard_cards.dart` | Modified | Cada card extraída como widget independiente registrable. |
| `lib/app/home/widgets/horizontal_scrollable_account_list.dart`, `income_or_expense_card.dart`, `balance_delta_pill.dart` | Modified | Wrappers expuestos como `DashboardWidgetSpec`. |
| `lib/core/database/services/user-setting/user_setting_service.dart` | Modified | Añadir `SettingKey.dashboardLayout` y `SettingKey.dashboardQuickUseChips` (no-op si se prefiere todo en `config` — confirmar en spec). |
| `lib/core/database/sql/initial/seed.dart` | Modified | Seed con `'[]'` o layout default mínimo. |
| `lib/app/onboarding/onboarding.dart` | Modified | `_applyChoices()` añade `setItem(SettingKey.dashboardLayout, jsonEncode(layout.toJson()), updateGlobalState: true)` tras persistir `onboardingGoals`. |
| `lib/core/services/firebase_sync_service.dart` | Verificación | Confirmar que `dashboardLayout` NO esté en `_userSettingsSyncExclusions` (l. 312). |
| `main.dart` | Modified | Invocar `registerDashboardWidgets()` antes de `runApp`. |

**Drift schema migrations**: NINGUNA. No se introduce tabla nueva; solo una `SettingKey` adicional que reutiliza el patrón existente (`onboardingGoals`, `preferredCurrency`).

## Risks

| Riesgo | Probabilidad | Mitigación |
|------|------------|------------|
| `_userSettingsSyncExclusions` excluye `dashboardLayout` y rompe sync entre dispositivos. | Baja | Verificación explícita en spec antes de tocar código de sync. |
| Cascade de re-suscripciones a streams en edit mode al reordenar widgets. | Media | `Key(instanceId)` estable + reutilizar `HiddenModeService.visibleAccountIdsStream` (ya `shareValue()`). Si DevTools muestra problema → introducir `DashboardStreamScope` (Approach C). |
| Seed escribe `'[]'` y dashboard arranca vacío para usuarios fresh-install que aún no terminaron onboarding. | Baja | `initState` detecta layout vacío Y `introSeen='1'` → aplica `DashboardLayoutDefaults.fallback()`. Camino normal: `_applyChoices()` ya escribió layout antes de navegar. |
| Returning user con `dashboardLayout` ya en Firebase — `pullAllData` debe correr antes del primer render. | Baja | Confirmado en `returning_user_flow.dart`: el sync se invoca antes de la navegación al dashboard. Spec lo cubrirá explícitamente. |
| Slide del onboarding distinto entre Android (s9) e iOS (s5) ⇒ riesgo de duplicar la escritura. | Baja | La escritura se hace **dentro** de `_applyChoices()` (un solo lugar), no en los call sites. Patrón existente para `onboardingGoals`. |
| Volumen del JSON (Firestore 1 MiB/doc, blob compartido). | Muy baja | Estimado < 4 KB; cap a 8 widgets en `DashboardLayoutDefaults`. |
| `ReorderableListView` no soporta multi-columna ⇒ UX inconsistente entre view (grid) y edit (lista). | Aceptado | En edit mode todo pasa a `fullWidth` temporalmente; grid 2-col vuelve al salir. Documentado en spec. |

## Rollback Plan

La feature es **aditiva** y no destructiva: no migra datos existentes, no toca esquema Drift, no modifica documentos Firestore.

Pasos de rollback si algo sale mal en producción:

1. **Feature flag de fallback** (incluido en MVP): `DashboardLayoutService.load()` ya soporta retornar `null` ⇒ `dashboard.page.dart` puede tener un branch que renderice el layout estático original (`DashboardCards` + componentes legacy) si la flag está activa. Activable via `appStateSettings['dashboardDynamicEnabled']`.
2. **Limpieza de datos**: `dashboardLayout` y `dashboardQuickUseChips` (si se usa) se borran con `UserSettingService.instance.removeItem(...)` — no afecta otras settings ni cuentas/transacciones.
3. **Sync Firebase**: el blob `userSettings/all` mantiene compatibilidad — claves desconocidas se ignoran en `pullAllData`. No hay riesgo de corromper documentos existentes.
4. **Reversión de código**: como toda la lógica vive en `lib/app/home/dashboard_widgets/` (carpeta nueva) más cambios localizados en `dashboard.page.dart`, `onboarding.dart` y `seed.dart`, un `git revert` del merge basta. Los wrappers de los componentes existentes (`DashboardCards`, `HorizontalScrollableAccountList`, `IncomeOrExpenseCard`) se mantienen funcionales fuera del registry.

No hay datos de usuarios reales en juego (la app no se ha publicado) — el coste de rollback es solo de ingeniería.

## Dependencies

- Onboarding ya persiste `onboardingGoals` (existente en `_applyChoices()`).
- `UserSettingService` con patrón JSON-encoded en string (existente).
- `firebase_sync_service.pushUserSettings` / `pullAllData` (existente; no requiere modificación si la verificación pasa).
- `bolsio_reorderable_list.dart` (existente — base del edit mode).
- `BolsioQuickActionsButton` (existente — base UI del `quickUse`).
- Sin nuevas dependencias en `pubspec.yaml`. **No requiere bump de versión** (regla del usuario: no tocar `pubspec.yaml` version/+buildNumber salvo orden directa).

## Success Criteria

- [ ] Usuario fresh-install que selecciona `save_usd` ve un dashboard con `quickUse`, `totalBalanceSummary` (USD), `exchangeRateCard`, `accountCarousel` al terminar onboarding.
- [ ] Usuario multi-goal (`track_expenses` + `budget` + `analyze`) ve los widgets combinados con dedup por type, cap a 8, `quickUse` siempre presente, respetando el orden de selección.
- [ ] Tap en lápiz del header entra a edit mode; drag para reordenar persiste el nuevo orden tras salir.
- [ ] Tap `X` en un widget lo borra (con confirmación) y persiste; reabrir app mantiene el cambio.
- [ ] Tap "Agregar widget" abre bottom sheet con marcado visual de recomendados según `onboardingGoals`.
- [ ] Widget `quickUse` ejecuta correctamente cada `QuickActionId` (toggles, navegación, quick tx). Editor de chips persiste cambios al cerrar.
- [ ] Returning user con cuenta que tenga `dashboardLayout` en Firebase ve su layout tras login. Si no tiene, ve `fallback()` sin crashear.
- [ ] `flutter analyze` pasa limpio. Tests de serialización JSON ida/vuelta del `DashboardLayout` y del `Migrator` pasan.
- [ ] Primer frame del dashboard con 8 widgets activos < 500 ms en POCO arm64-v8a (recipe de build oficial del usuario, sin obfuscate ni split-debug-info).
- [ ] `firebase_sync_service._userSettingsSyncExclusions` confirmado: `dashboardLayout` NO excluido.
- [ ] Hidden mode oculta los IDs filtrados en todos los widgets que dependen de `visibleAccountIdsStream`.
