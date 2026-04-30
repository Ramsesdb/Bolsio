# Design: Dashboard de widgets dinámicos

## Technical Approach

El dashboard actual ([`lib/app/home/dashboard.page.dart`](../../../lib/app/home/dashboard.page.dart), 1040 LOC) compone manualmente header + carrusel + tasas + 4 cards fijos. Esta solución lo convierte en un **renderer iterativo** sobre un layout serializable persistido en `SettingKey.dashboardLayout` (JSON-string en `userSettings`).

La estrategia se apoya en patrones ya existentes en bolsio y evita introducir tecnología nueva:

1. **Modelo de datos** plain Dart (sin `freezed`) con `toJson` / `fromJson` manuales — `WidgetDescriptor`, `DashboardLayout`, `Migrator`. Coherente con `onboardingGoals`, `preferredCurrency` y demás `SettingKey` del proyecto.
2. **Servicio singleton** `DashboardLayoutService.instance` con `BehaviorSubject<DashboardLayout>`, debouncer 300 ms (`Timer`) y `flush()` síncrono (al salir de edit mode, al cerrar sheets). Mismo patrón que `HiddenModeService`, `PrivateModeService`, `ExchangeRateService`.
3. **Registry estático** (`DashboardWidgetRegistry`) inicializado desde `main.dart` vía `registerDashboardWidgets()` antes de `runApp` — paralelo a otros bootstraps (slang, Drift, services init).
4. **Defaults derivados de `onboardingGoals`** (`DashboardLayoutDefaults.fromGoals`) escritos dentro de `_applyChoices()` del onboarding (un solo call site, evita la divergencia s09 Android / s05 iOS).
5. **Edit mode** local al `_DashboardPageState` (`bool _editing`), apoyado en el `BolsioReorderableList` ya existente con todo el contenido forzado a `fullWidth` durante el drag. Add via bottom sheet `_AddWidgetSheet`. Quick-use config via sheet de dos pestañas.
6. **Sync Firebase gratis**: el blob `users/{uid}/userSettings/all` de `pushUserSettings()` ya cubre toda settingKey no-excluida; `dashboardLayout` viaja sin código nuevo (estimado < 4 KB, dentro del 1 MiB de Firestore).

Este diseño materializa los specs (`dashboard-dynamic`, `dashboard-onboarding-defaults`, `dashboard-quick-use`) y refleja el Approach A consolidado en la exploración y la propuesta.

## Capas y estructura de carpetas

```
lib/app/home/dashboard_widgets/
├── models/
│   ├── widget_descriptor.dart        // WidgetDescriptor, WidgetSize, WidgetType, QuickActionId
│   ├── dashboard_layout.dart         // DashboardLayout (schemaVersion + items)
│   └── migrator.dart                 // DashboardLayoutMigrator (v1 -> vN)
├── services/
│   └── dashboard_layout_service.dart // singleton, BehaviorSubject, debouncer 300 ms
├── widgets/
│   ├── total_balance_summary_widget.dart
│   ├── account_carousel_widget.dart
│   ├── income_expense_period_widget.dart
│   ├── recent_transactions_widget.dart
│   ├── exchange_rate_card_widget.dart
│   ├── quick_use_widget.dart
│   └── pending_imports_alert_widget.dart
├── edit/
│   ├── editable_widget_frame.dart    // marco con X + drag handle en edit mode
│   ├── add_widget_sheet.dart         // bottom sheet con catálogo + recomendados
│   └── quick_use_config_sheet.dart   // editor de chips (2 pestañas)
├── registry.dart                     // DashboardWidgetRegistry + DashboardWidgetSpec
├── registry_bootstrap.dart           // registerDashboardWidgets()
└── defaults.dart                     // DashboardLayoutDefaults.fromGoals / fallback
```

Cada `widgets/{type}_widget.dart` es un `StatelessWidget` que recibe `(WidgetDescriptor descriptor, bool isEditing)` y delega en componentes pre-existentes (`HorizontalScrollableAccountList`, `IncomeOrExpenseCard`, `_buildRatesCard` extraído, etc.). El widget original NO se duplica: se envuelve.

## Architecture Decisions

### ADR-1: Persistencia JSON en `SettingKey` vs tabla Drift dedicada

**Choice**: JSON-encoded string en `SettingKey.dashboardLayout` (existente patrón).
**Alternatives considered**: Tabla Drift `dashboard_widgets` (cols `instanceId`, `type`, `position`, `size`, `config`).
**Rationale**: La feature está en MVP. La tabla obliga a bumpear schema Drift, regenerar via `build_runner`, y escribir `pushDashboardWidgets`/`pullDashboardWidgets` en `firebase_sync_service.dart` (la sync actual es por blob `userSettings/all`, no cubre tablas adicionales). El layout estimado < 4 KB cabe sobradamente en una `String` (Drift no tiene límite práctico) y en el 1 MiB/doc de Firestore. Queries parciales no son requisito (cargamos el layout entero al boot).
**Consequences**: La evolución del schema vive en `Migrator` (no en `lib/core/database/sql/migrations/`). Cambiar a tabla más adelante requeriría una migración explícita (no es bloqueante: la feature aún no se publica).

### ADR-2: Plain Dart con `toJson` manual vs `freezed`

**Choice**: Plain Dart con `toJson()` / `fromJson()` y `copyWith()` manuales.
**Alternatives considered**: `@freezed` con `json_serializable`.
**Rationale**: Tres factores: (a) los modelos son pequeños (4 clases), (b) introducir `freezed` exige `dart run build_runner build` cada vez que cambia el modelo (ya el proyecto tiene fricción de build_runner por Drift y slang), (c) la firma `WidgetDescriptor.config: Map<String, dynamic>` no se traduce limpiamente a `freezed` sin perder ergonomía.
**Consequences**: Tests unitarios deben cubrir explícitamente serialización ida-vuelta y `copyWith` para todas las propiedades. La inmutabilidad se mantiene por convención (`final` en todos los campos).

### ADR-3: Debouncer 300 ms vs flush inmediato

**Choice**: Debounce 300 ms por defecto en `save()`, con `flush()` explícito al salir de edit mode, cerrar sheets, y `dispose()`.
**Alternatives considered**: Flush en cada cambio (escritura síncrona).
**Rationale**: Reorder via `ReorderableListView.onReorder` puede disparar varias re-emisiones consecutivas mientras el usuario arrastra; `setItem(SettingKey.dashboardLayout, ...)` golpea Drift + `appStateSettings` + `pushUserSettings()` (eventualmente Firebase). Coalescer evita escritura redundante. 300 ms es el valor que ya usa `private_mode_service` cuando agrupa toggles.
**Consequences**: Hay una ventana de 300 ms en la que un crash perdería la última edición. Mitigado por `flush()` en `setState(() => _editing = false)` y en cierre de sheets. Cobertura: test unitario que verifica que dos `save()` consecutivos producen una sola escritura tras 300 ms.

### ADR-4: Tamaños fijos `medium` / `fullWidth` en MVP vs resize libre

**Choice**: Dos tamaños declarativos por widget (`WidgetSize.medium` ≈ 50 % del ancho, `WidgetSize.fullWidth` 100 %). Sin resize por el usuario.
**Alternatives considered**: Grid con `staggered_grid_view` y resize por gesture; `flutter_layout_grid`.
**Rationale**: Resize libre exige UI de handles, snapping, y manejo de overflow en widgets que no soportan altura variable (charts de fl_chart). El MVP necesita "qué bloques veo y en qué orden", no "qué tamaño les doy". Cada `DashboardWidgetSpec` declara su `defaultSize` y los `supportedSizes` (algunos como `accountCarousel` solo soportan `fullWidth`).
**Consequences**: El usuario no puede tener un `incomeExpense` ocupando 75 %. Si surge la necesidad, se añade un `WidgetSize.large` sin romper el JSON (campo string con migrador best-effort).

### ADR-5: Edit mode forzado a 1 columna vs grid 2-col reorderable

**Choice**: En edit mode todo se rinde como `fullWidth` dentro de `BolsioReorderableList`. Al salir, se restaura el grid 2-col.
**Alternatives considered**: `reorderable_grid_view` (paquete externo) con drag multi-columna.
**Rationale**: `ReorderableListView` de Flutter sólo soporta lista lineal — un grid reorderable requiere una nueva dependencia que NO está en `pubspec.yaml`, con su propia API y bugs. La transición visual (grid → lista de tarjetas anchas → grid) es predecible y el usuario entiende "estoy editando". Patrón ya establecido por `BolsioReorderableList` en otras pantallas (categorías, presupuestos).
**Consequences**: En edit mode el layout no es WYSIWYG perfecto. Documentado en spec. Si UX feedback lo exige, fase 2 puede introducir `reorderable_grid_view`.

### ADR-6: Streams compartidos via `HiddenModeService.shareValue()` vs `DashboardStreamScope` (`InheritedWidget`)

**Choice**: Confiar en `HiddenModeService.visibleAccountIdsStream` (ya hace `shareValue()` lazy en l. 95) y demás streams del proyecto. **No** introducir `DashboardStreamScope` en MVP.
**Alternatives considered**: `InheritedWidget` que expone `Stream<List<Account>>`, `Stream<double>` totalBalance, `Stream<TransactionList>` recientes — los hijos lo consumen vía `DashboardStreamScope.of(context)`.
**Rationale**: La exploración midió que la única fuente real de cascade es la combinación `accounts + isLocked` (combinación `Rx.combineLatest2` con coste cero gracias a `shareValue`). Los demás streams (`getAccounts()`, `getTransactionsBalance()`) son baratos individualmente. Un `InheritedWidget` añade ceremonia sin beneficio medible. Si DevTools muestra problema en flag de >100 ms re-suscriptions, se introduce en fase 2 (Approach C de la exploración).
**Consequences**: Cada widget hace su propia suscripción a streams atómicos, pero todos comparten la cola común vía `shareValue()`. Si un widget olvida usar `visibleAccountIdsStream` se documenta el riesgo de leak en hidden mode (ver sección Seguridad).

### ADR-7: Registro estático con `register()` por widget vs auto-discovery por annotation

**Choice**: Función imperativa `registerDashboardWidgets()` en `registry_bootstrap.dart`, invocada desde `main.dart` antes de `runApp`. Cada widget tiene su `register()` explícito.
**Alternatives considered**: Annotation `@DashboardWidget('totalBalanceSummary')` + codegen vía `build_runner`.
**Rationale**: Codegen agrega un step al build que ya tiene `drift_dev`, `freezed`, `slang`, `json_serializable`. Beneficio: "no hay que tocar dos archivos". Coste: bootstrap por reflection-style imposible en Flutter sin codegen, complejidad de debug. Con 7 widgets en MVP, el archivo `registry_bootstrap.dart` cabe en pantalla y es trivial leer qué se registra. Patrón equivalente al `routes_bootstrap` ya existente.
**Consequences**: Olvidar registrar un widget ⇒ excepción al deserializar layout (`UnknownWidgetType`). Mitigación: spec exige test de "todos los `WidgetType.values` están registrados".

### ADR-8: Aplicar defaults en `_applyChoices` vs lazy en `dashboard.page.dart::initState`

**Choice**: Escritura del layout en `_applyChoices()` del onboarding (path principal). Lazy fallback en `_DashboardPageState.initState` solo cuando se detecta `dashboardLayout` vacío Y `appStateSettings[AppDataKey.introSeen] == '1'`.
**Alternatives considered**: Lazy puro en `initState` (no escribir nunca durante onboarding).
**Rationale**: `_applyChoices` ya es el único lugar donde se persiste `onboardingGoals`, `preferredCurrency`, `preferredRateSource` — agrupar la escritura mantiene coherencia transaccional ("al confirmar onboarding, todos los settings derivados se escriben juntos"). El fallback en `initState` cubre dos casos: (a) returning user que no tiene `dashboardLayout` en Firebase, (b) seed de DB en estado `'[]'` con onboarding ya completado en otra sesión. Sin lazy fallback, la UI quedaría vacía con un mensaje "agrega tu primer widget" — peor onboarding UX.
**Consequences**: Dos puntos de escritura, pero claramente diferenciados (path normal vs degradado). Test debe cubrir ambos.

### ADR-9: Sync Firebase: blob compartido `userSettings/all` vs entry separada

**Choice**: Mantener `dashboardLayout` dentro del blob `users/{uid}/userSettings/all` (existente). NO añadir colección dedicada `users/{uid}/dashboardLayout`.
**Alternatives considered**: Documento independiente `users/{uid}/dashboardLayout/current` con `pushDashboardLayout()` / `pullDashboardLayout()` en `firebase_sync_service.dart`.
**Rationale**: El blob `userSettings/all` ya transporta todas las settingKeys no excluidas (l. 326–356 `pushUserSettings`, l. 362–407 `_pullUserSettings`). Tamaño del JSON de layout estimado < 4 KB; el blob completo de un usuario típico cabe sobradamente en el 1 MiB/doc. Documento separado obligaría a duplicar lógica push/pull, manejar conflictos updatedAt independientes, y añadir nuevas reglas de Firestore Security.
**Consequences**: Last-write-wins por `updatedAt` del blob completo aplica también a `dashboardLayout`. Si en el futuro la frecuencia de escritura del layout se desacopla de la del resto de settings (improbable), valdría la pena separar. Verificación: confirmar que `dashboardLayout` NO está en `_userSettingsSyncExclusions` (l. 312) ni dispara `_isSensitiveSettingKey` (no contiene "apikey/secret/token/password").

## Data Flow

### Flow 1: Onboarding → primer render del dashboard

```
[Slide 9 Android / Slide 5 iOS]
       │
       ▼
_applyChoicesAndAdvance() / iOS finish
       │
       ▼
 _applyChoices()                         (l.165–178 onboarding.dart)
       │ persiste secuencialmente:
       │   onboardingGoals (List<String> JSON)
       │   preferredCurrency
       │   preferredRateSource
       │   ┌─────────── NUEVO ────────────┐
       │   │ DashboardLayoutDefaults       │
       │   │   .fromGoals(goals)           │
       │   │   .toJson()                   │
       │   │ → setItem(                    │
       │   │     SettingKey.dashboardLayout,│
       │   │     jsonEncode(layout),        │
       │   │     updateGlobalState: true)   │
       │   └───────────────────────────────┘
       ▼
 _completeOnboarding()
       │  setItem(AppDataKey.introSeen, '1', updateGlobalState:true)
       ▼
 RouterRefresh → DashboardPage()
       │
       ▼
 _DashboardPageState.initState()
       │  DashboardLayoutService.instance.load()
       │    └─ lee SettingKey.dashboardLayout, parsea, emite en BehaviorSubject
       ▼
 build()  StreamBuilder<DashboardLayout> → ListView/Wrap de WidgetSpec.builder()
```

### Flow 2: Edit mode → reorder → exit

```
Tap lápiz                                  Drag widget i → posición j
   │                                            │
   ▼                                            ▼
setState(() => _editing = true)        BolsioReorderableList.onReorder(i,j)
   │                                            │
   ▼                                            ▼
build() rinde TODOS los widgets               DashboardLayoutService
        como fullWidth dentro de              .reorder(from:i, to:j)
        BolsioReorderableList                       │
        envueltos en EditableWidgetFrame            │ debounce 300 ms
                                                    ▼
                                              save()
                                                    │
                                                    ▼
                                              UserSettingService.setItem(
                                                 SettingKey.dashboardLayout,
                                                 jsonEncode(layout),
                                                 updateGlobalState: true)
                                                    │
                                                    ▼
                                              Drift write + appStateSettings
                                                    │
                                                    ▼
                                              FirebaseSyncService.pushUserSettings()

[Tap "Listo"]
   │
   ▼
DashboardLayoutService.flush()  (síncrono — no espera 300 ms)
   │
   ▼
setState(() => _editing = false)
   │
   ▼
build() restaura grid 2-col según WidgetSize de cada item
```

### Flow 3: Add widget desde bottom sheet

```
Tap "Agregar widget"
   │
   ▼
showModalBottomSheet → _AddWidgetSheet
   │
   │ lee onboardingGoals desde appStateSettings
   │ lee tipos ya presentes en layout actual
   │ marca chips "recomendado" según defaults.fromGoals(goals)
   │ deshabilita tipos ya presentes (uniqueness rule)
   ▼
Tap card "Recientes"
   │
   ▼
DashboardLayoutService.add(
  WidgetDescriptor(
    instanceId: uuid.v4(),
    type: WidgetType.recentTransactions,
    size: spec.defaultSize,
    config: spec.defaultConfig,
  ))
   │ debounce 300 ms → save()
   │
   ▼
BehaviorSubject emite nuevo DashboardLayout
   │
   ▼
StreamBuilder en dashboard.page.dart re-construye
   │
   ▼
Bottom sheet cierra (Navigator.pop)
   │
   ▼
DashboardLayoutService.flush()
```

### Flow 4: Quick-use chip → toggle privateMode

```
Tap chip "Modo privado" en QuickUseWidget
   │
   ▼
QuickActionDispatcher.dispatch(QuickActionId.togglePrivateMode)
   │
   ▼
PrivateModeService.instance.toggle()
   │
   ▼
BehaviorSubject<bool> de PrivateModeService emite valor nuevo
   │
   ├──► appStateSettings[SettingKey.privateMode] = '1'/'0'
   │
   ├──► CurrencyDisplayer (todos los widgets) re-construye con mask
   │
   └──► No toca DashboardLayoutService — la acción es ortogonal al layout
```

## File Changes

| File | Action | Description |
|------|--------|-------------|
| `lib/app/home/dashboard_widgets/models/widget_descriptor.dart` | Create | `WidgetDescriptor`, `WidgetSize`, `WidgetType`, `QuickActionId`. |
| `lib/app/home/dashboard_widgets/models/dashboard_layout.dart` | Create | `DashboardLayout` con `schemaVersion` y `List<WidgetDescriptor> items`. |
| `lib/app/home/dashboard_widgets/models/migrator.dart` | Create | `DashboardLayoutMigrator.fromJson(Map)` con switch por versión. |
| `lib/app/home/dashboard_widgets/services/dashboard_layout_service.dart` | Create | Singleton, `BehaviorSubject<DashboardLayout>`, `load/save/add/remove/reorder/updateConfig/flush`. |
| `lib/app/home/dashboard_widgets/registry.dart` | Create | `DashboardWidgetRegistry` (Map<WidgetType, DashboardWidgetSpec>), `DashboardWidgetSpec` (builder + defaults + supportedSizes). |
| `lib/app/home/dashboard_widgets/registry_bootstrap.dart` | Create | `registerDashboardWidgets()`. |
| `lib/app/home/dashboard_widgets/defaults.dart` | Create | `DashboardLayoutDefaults.fromGoals(Set<String>)`, `.fallback()`. |
| `lib/app/home/dashboard_widgets/widgets/total_balance_summary_widget.dart` | Create | Wrapper que reusa lógica de `_buildTotalBalance` ya en `dashboard.page.dart`. |
| `lib/app/home/dashboard_widgets/widgets/account_carousel_widget.dart` | Create | Wrapper sobre `HorizontalScrollableAccountList`. |
| `lib/app/home/dashboard_widgets/widgets/income_expense_period_widget.dart` | Create | Wrapper sobre `IncomeOrExpenseCard`. |
| `lib/app/home/dashboard_widgets/widgets/recent_transactions_widget.dart` | Create | Lista corta (5) con tap → ruta `/transactions`. |
| `lib/app/home/dashboard_widgets/widgets/exchange_rate_card_widget.dart` | Create | Extracción de `_buildRatesCard` actual. |
| `lib/app/home/dashboard_widgets/widgets/quick_use_widget.dart` | Create | Chips renderizados desde `descriptor.config['chips']`. |
| `lib/app/home/dashboard_widgets/widgets/pending_imports_alert_widget.dart` | Create | Alerta con badge de imports pendientes. |
| `lib/app/home/dashboard_widgets/edit/editable_widget_frame.dart` | Create | Marco con X (top-right) + drag handle. |
| `lib/app/home/dashboard_widgets/edit/add_widget_sheet.dart` | Create | Bottom sheet catálogo con chips "recomendado". |
| `lib/app/home/dashboard_widgets/edit/quick_use_config_sheet.dart` | Create | Editor 2 pestañas (visibles / disponibles). |
| `lib/app/home/dashboard.page.dart` | Modify | Body scrolleable se vuelve `StreamBuilder<DashboardLayout>` + `_editing`. Header se mantiene fijo. `initState` aplica fallback si layout vacío e `introSeen == '1'`. |
| `lib/app/home/widgets/dashboard_cards.dart` | Modify | Cards extraídas como widgets independientes registrables (mover a `dashboard_widgets/widgets/`). |
| `lib/core/database/services/user-setting/user_setting_service.dart` | Modify | Añadir `SettingKey.dashboardLayout` al enum (entrada JSON-encoded string). |
| `lib/core/database/sql/initial/seed.dart` | Modify | Seed inicial de `dashboardLayout` con `'[]'` (fallback aplicado al render si vacío). |
| `lib/app/onboarding/onboarding.dart` | Modify | `_applyChoices()` añade escritura de `dashboardLayout` con `updateGlobalState: true` tras `onboardingGoals`. |
| `lib/core/services/firebase_sync_service.dart` | Verify | Confirmar que `dashboardLayout` NO está en `_userSettingsSyncExclusions` (l. 312). NINGÚN cambio de código. |
| `lib/main.dart` | Modify | Invocar `registerDashboardWidgets()` antes de `runApp`. |
| `test/dashboard_widgets/serialization_test.dart` | Create | Round-trip JSON `DashboardLayout` <-> JSON. |
| `test/dashboard_widgets/migrator_test.dart` | Create | Versions v1, v2 (futuro), unknown type best-effort. |
| `test/dashboard_widgets/defaults_test.dart` | Create | `fromGoals` para combinaciones canónicas + cap a 8 widgets. |
| `test/dashboard_widgets/registry_test.dart` | Create | All `WidgetType.values` están registrados. |

**Drift schema**: NINGÚN cambio. La nueva `SettingKey` reutiliza el patrón existente (Drift `userSettings` table mapea enum → string).

## Interfaces / Contracts

```dart
// models/widget_descriptor.dart
enum WidgetSize { medium, fullWidth }

enum WidgetType {
  totalBalanceSummary,
  accountCarousel,
  incomeExpensePeriod,
  recentTransactions,
  exchangeRateCard,
  quickUse,
  pendingImportsAlert,
}

enum QuickActionId {
  togglePrivateMode,
  toggleHiddenMode,
  goToSettings,
  newExpenseTransaction,
  newIncomeTransaction,
  newTransferTransaction,
  goToBudgets,
  goToReports,
}

class WidgetDescriptor {
  final String instanceId;       // uuid v4
  final WidgetType type;
  final WidgetSize size;
  final Map<String, dynamic> config; // shape declarado por DashboardWidgetSpec

  Map<String, dynamic> toJson();
  factory WidgetDescriptor.fromJson(Map<String, dynamic> j);
  WidgetDescriptor copyWith({...});
}

// models/dashboard_layout.dart
class DashboardLayout {
  static const int currentSchemaVersion = 1;
  final int schemaVersion;
  final List<WidgetDescriptor> items;

  Map<String, dynamic> toJson();
  factory DashboardLayout.fromJson(Map<String, dynamic> j);
  DashboardLayout copyWith({List<WidgetDescriptor>? items});
}

// services/dashboard_layout_service.dart
class DashboardLayoutService {
  static final instance = DashboardLayoutService._();

  Stream<DashboardLayout> get stream;       // BehaviorSubject.stream
  DashboardLayout get current;              // BehaviorSubject.value

  Future<void> load();                      // lee SettingKey + migra
  Future<void> save();                      // debounced 300 ms
  Future<void> flush();                     // síncrono

  Future<void> add(WidgetDescriptor d);
  Future<void> removeByInstanceId(String id);
  Future<void> reorder(int from, int to);
  Future<void> updateConfig(String instanceId, Map<String, dynamic> config);
  Future<void> resetToFallback();
}

// registry.dart
class DashboardWidgetSpec {
  final WidgetType type;
  final String displayNameKey;              // i18n via slang
  final IconData icon;
  final WidgetSize defaultSize;
  final Set<WidgetSize> supportedSizes;
  final Map<String, dynamic> defaultConfig;
  final Widget Function(BuildContext, WidgetDescriptor, {required bool isEditing}) builder;
  final Widget Function(BuildContext, WidgetDescriptor)? configEditor;
  final bool unique;                        // true → solo 1 instancia permitida
}
```

## Edge cases

| Caso | Comportamiento |
|------|----------------|
| `appStateSettings[SettingKey.dashboardLayout]` corrupto (JSON inválido) | `DashboardLayoutService.load()` captura `FormatException`, loguea, y emite `DashboardLayoutDefaults.fallback()`. NO escribe (preserva datos del usuario para inspección). |
| `schemaVersion` futuro (mayor que `currentSchemaVersion`) | Migrator hace best-effort: descarta items con `WidgetType` desconocido (no crashea); preserva los reconocidos; emite con `schemaVersion = currentSchemaVersion`. Loguea via `Logger.printDebug`. |
| Hidden mode + balances visibles | Cada widget que muestre cuentas/balances DEBE suscribirse a `HiddenModeService.instance.visibleAccountIdsStream` y filtrar por `visibleSet.contains(account.id)`. Patrón ya en `_visibleAccountsStream` de `dashboard.page.dart` l. 86–99. |
| Multi-currency (USD/VES) | Widgets que muestren totales tienen `descriptor.config['displayCurrency']` opcional. Si null, fallback a `appStateSettings[SettingKey.preferredCurrency]`. `exchangeRateCard` siempre muestra USD↔VES según `preferredRateSource`. |
| Returning user con layout en Firebase | `pullAllData` corre antes de `DashboardPage` (confirmado en `returning_user_flow.dart`). `DashboardLayoutService.load()` lee el valor ya sincronizado. |
| Cap de 8 widgets en defaults | `DashboardLayoutDefaults.fromGoals` aplica `.take(8)` después de dedupe por `WidgetType`. `quickUse` siempre incluido (no cuenta hacia el cap si lo elevamos en fase 2). |
| Widget type marcado `unique` | `_AddWidgetSheet` deshabilita la card si ya existe instancia en layout actual. `add()` valida y rechaza con `StateError` defensivo. |

## Performance

**Caso peor**: 8 widgets, cada uno con su propio `StreamBuilder`. Suscripciones por widget:

| Widget | Streams suscritos |
|--------|-------------------|
| totalBalanceSummary | `visibleAccountIdsStream` (compartido), `getTotalBalance(visibleIds, currency)` |
| accountCarousel | `getAccounts(predicate)`, `visibleAccountIdsStream` (compartido) |
| incomeExpensePeriod | `getTransactionsBalance(period, visibleIds)` |
| recentTransactions | `getTransactions(limit:5, visibleIds)` |
| exchangeRateCard | `ExchangeRateService.getRate(source)` |
| quickUse | `PrivateModeService.stream`, `HiddenModeService.isLockedStream` |
| pendingImportsAlert | `AutoImportService.pendingCountStream` |

**Cuello de botella mitigado**: `visibleAccountIdsStream` ya hace `shareValue()` (l. 95 de `hidden_mode_service.dart`); cuatro consumers comparten una sola pipeline. Las demás suscripciones golpean Drift; el coste por suscripción es <5 ms en POCO arm64-v8a.

**Memoización**: `DashboardWidgetSpec.builder` recibe `WidgetDescriptor` ya construido. Los widgets internos usan `late final` para inicializar streams una sola vez en `initState()` (patrón ya en `dashboard.page.dart` l. 70–73 con `_balanceVariationStream`, `_totalBalanceStream`).

**Edit mode rebuild**: cada widget se envuelve en `KeyedSubtree(key: ValueKey(descriptor.instanceId))` para que `ReorderableListView` preserve el `State` interno (incluyendo `StreamBuilder` ya suscrito). Sin `Key`, Flutter destruye y recrea el subtree en cada reorder ⇒ cascade de re-suscripciones.

**Primer frame**: criterio de éxito `< 500 ms` con 8 widgets en POCO arm64-v8a (release sin obfuscate, sin split-debug-info — recipe oficial bolsio).

## Seguridad / Privacidad

- `dashboardLayout` no contiene datos sensibles: solo IDs (uuid), `WidgetType` enum (string), `WidgetSize` enum (string), y `config` con flags de presentación / IDs de quick action. **Confirmar** que NO se debe agregar a `_userSettingsSyncExclusions` (l. 312). El nombre `dashboardLayout` no dispara `_isSensitiveSettingKey` (no contiene `apikey`, `secret`, `token`, `password`).
- Hidden mode: TODO widget que muestre balances o transacciones DEBE suscribirse a `HiddenModeService.instance.visibleAccountIdsStream` y filtrar. Documentado en spec; revisión obligatoria en code review.
- Backup/restore: el layout viaja en el dump Drift y en el blob Firebase. Sin información sensible, no hay riesgo de leak post-restore.
- Quick actions: `togglePrivateMode` y `toggleHiddenMode` no exponen el PIN. `goToSettings` solo navega — los flujos sensibles dentro de Settings tienen sus propias guards.

## Testing Strategy

| Layer | What | Approach |
|-------|------|----------|
| Unit | `DashboardLayout.toJson` / `fromJson` ida-vuelta para todos los `WidgetType`. | `flutter_test`, fixtures inline. |
| Unit | `DashboardLayoutMigrator` v1 → v1 (no-op), v0 inexistente, schemaVersion futura, tipo desconocido descartado. | `flutter_test`. |
| Unit | `DashboardLayoutDefaults.fromGoals` para `{}`, `{save_usd}`, `{track_expenses, budget}`, `{save_usd, reduce_debt, analyze, track_expenses, budget}` (cap a 8). | `flutter_test`, asserts sobre `WidgetType` set y orden. |
| Unit | `DashboardWidgetRegistry` cubre todos los `WidgetType.values` (test fail-fast si se añade enum sin `register()`). | `flutter_test`. |
| Unit | `DashboardLayoutService` debouncer: 5 `save()` consecutivos → 1 escritura tras 300 ms. `flush()` fuerza inmediato. | `fakeAsync` de `package:fake_async`. |
| Widget | `DashboardPage` rinde N items según layout dado (mock `DashboardLayoutService`). | `pumpWidget`, mock service. |
| Widget | Edit mode toggle: tap lápiz → todos los items renderizan `EditableWidgetFrame`. | `pumpWidget` + `tap(find.byIcon(Icons.edit))`. |
| Widget | Drag reorder: from index 0 to index 2 → layout persiste orden nuevo. | `WidgetTester.drag` sobre `BolsioReorderableList`. |
| Widget | `_AddWidgetSheet`: muestra chips "recomendado" para los goals dados; deshabilita tipos ya presentes. | `pumpWidget` + verificación de `Chip.label` y `enabled`. |
| Manual E2E | Ver `proposal.md` Success Criteria. Verificación en POCO arm64-v8a build oficial bolsio. | Lista en `verify-report.md`. |

## Migration / Rollout

No hay datos de usuarios reales (la app no se ha publicado). La feature es aditiva:

1. Seed `dashboardLayout = '[]'` en DB nueva.
2. Onboarding fresh-install escribe layout derivado de goals.
3. Returning user (post-relogin Firebase) recibe `dashboardLayout` desde blob `userSettings/all` si existía en otro dispositivo, o aplica `fallback()` si no.
4. Feature flag de pánico `appStateSettings['dashboardDynamicEnabled']` (string '0' / null = legacy estático, '1' = dinámico). En MVP se escribe `'1'` en seed y onboarding; el branch legacy queda como rollback.

Rollback de emergencia: flip flag a `'0'` o `git revert` del merge — la carpeta `dashboard_widgets/` y la lógica del registry son aditivos; los wrappers no destruyen los componentes originales.

## Open Questions

- [ ] ¿`SettingKey.dashboardQuickUseChips` separado o todo en `descriptor.config['chips']`? Recomendación del proposal: dentro del `config` del descriptor (coherente con el contrato del widget).
- [ ] Cap de 8 widgets en MVP — ¿se cuenta `quickUse` hacia el cap o es siempre extra? Recomendación: cuenta hacia el cap; `defaults.fromGoals` lo coloca primero.
- [ ] ¿Se permite duplicar `incomeExpensePeriod` con períodos distintos? Spec MVP: NO (uniqueness por type). Si la UX lo pide, fase 2 lo habilita marcando `unique=false` en el `Spec`.
