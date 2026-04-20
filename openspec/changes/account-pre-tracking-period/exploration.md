## Exploration: account-pre-tracking-period

### Contexto

Ramses está empezando a usar Wallex desde cero. Quiere registrar el saldo inicial de sus cuentas (BDV) y simultáneamente importar movimientos históricos (semanas/meses atrás) que **no deben afectar el balance actual**. Si hoy mete un saldo inicial + movimientos viejos, el balance queda descuadrado.

Solución acordada: añadir `trackedSince: DateTime?` a la tabla `accounts`. Transacciones con `date < trackedSince` aparecen en feeds/listados pero no alteran el balance actual. `trackedSince == NULL` = comportamiento actual (retrocompatible). Equivalente funcional a "Fresh Start" de YNAB.

---

### Current State

**Modelo `accounts`** (`lib/core/database/sql/initial/tables.drift:52-83`):
- Columnas actuales: `id, name, iniValue, date (opening), description, type, iconId, displayOrder, color, closingDate, currencyId, iban, swift`
- `date` es fecha de apertura — hay validación en `account_form.dart:86` que impide transacciones previas. **No reutilizable** para el caso "pre-tracking" porque es inmutable semánticamente.
- `closingDate` (nullable) ya establece el patrón "frontera temporal a nivel cuenta".

**Clase Dart Account** (`lib/core/models/account/account.dart:52-128`): extiende `AccountInDB` generado por Drift.

**Cálculo de balance — núcleo único**:
- `AccountService.getAccountsMoney()` (`lib/core/database/services/account/account_service.dart:135-212`): fórmula `iniValue (si date <= useDate else 0) + SUM(transactions.value WHERE date <= useDate)`.
- Combina `initialBalance` + `TransactionService.getTransactionsValueBalance()` con `maxDate`.
- Query Drift subyacente: `countTransactions` (`lib/core/database/sql/queries/select-full-data.drift:112-173`) — recibe `$predicate` dinámico desde `TransactionFilterSet`.
- Todas las demás llamadas (al menos 10 consumidores: header de account details, all_accounts_balance, balance_bar_chart, income_expense_comparason, transaction_list_date_separator, debt_service, income_or_expense_card, home dashboard, stats widgets) pasan por estos dos servicios → **cambio puntual en el núcleo propaga automáticamente**.

**Migraciones**:
- Carpeta `assets/sql/migrations/` con `v1.sql` … `v23.sql`.
- Ejecución en `lib/core/database/app_db.dart:85-98` (`rootBundle.loadString` + `customStatement`).
- `schemaVersion = 23` hoy → la nueva sería `v24.sql`.

**Sin caché de balance**: Drift usa `watch()` streams. Cualquier cambio en `accounts`/`transactions` re-emite. No hay invalidación manual necesaria.

**Sin openspec specs previos para `account/`**: es un cambio greenfield en el modelo (verificable tras este explore).

---

### Affected Areas

#### Base de datos / modelo
- `lib/core/database/sql/initial/tables.drift:52-83` — añadir columna `trackedSince DATETIME` (nullable) a tabla `accounts`.
- `assets/sql/migrations/v24.sql` — archivo nuevo: `ALTER TABLE accounts ADD COLUMN trackedSince DATETIME;`.
- `lib/core/database/app_db.dart:115` — bump `schemaVersion` a 24.
- `lib/core/models/account/account.dart:52-128` — exponer `trackedSince` en el modelo Dart + posible helper `isTrackingFromStart`.

#### Lógica de balance (cambio central)
- `lib/core/database/services/account/account_service.dart:135-212` — `getAccountsMoney()`: añadir filtro en la query de transactions `WHERE account.trackedSince IS NULL OR transactions.date >= account.trackedSince`. Es el único punto que requiere reescritura de la fórmula.
- `lib/core/database/services/account/account_service.dart:248` — `getAccountsMoneyVariation()`: hereda automáticamente.
- `lib/core/database/services/transaction/transaction_service.dart:200-226, 228-348` — `getTransactionsValueBalance()` y `_countTransactions()`: revisar si conviene un flag `respectTrackedSince` para que stats puedan incluir/excluir pre-tracking en estadísticas.
- `lib/core/database/sql/queries/select-full-data.drift:112-173` — `countTransactions`: puede necesitar un parámetro extra o un JOIN con accounts para aplicar el filtro `trackedSince` sin romper otras llamadas (stats quieren ver pre-tracking).

#### Transferencias (riesgo de asimetría)
- `lib/core/database/services/transaction/transaction_service.dart:228-348` — `_countTransactions()` procesa transfers en 3 queries (income/expenses, origen de transfers, destino de transfers). Si la fecha de transfer < `trackedSince` **de una sola pata**, aparece desbalance. Requiere lógica simétrica: si una pata es pre-tracking, la otra también debe ignorarse **para ese cálculo de balance**.

#### Listados de transacciones — badge "histórico"
- `lib/app/transactions/widgets/transaction_list_tile.dart:154-347` — widget de fila reutilizado en toda la app. Añadir `Icon(Icons.history, size: 12, color: Theme.disabledColor)` en la sección de badges (línea 173-192 tiene el patrón existente: status, reversed, recurrent). **Un solo cambio aquí cubre todos los feeds.**
- `lib/app/accounts/details/account_details.dart:197-200` — feed de cuenta detalle.
- `lib/app/transactions/transactions.page.dart` — feed global.
- `lib/app/home/dashboard.page.dart` — widget "últimas transacciones" (usa el mismo tile).

#### Formulario de cuenta
- `lib/app/accounts/account_form.dart:38-493` — añadir `DateTimeFormField` para `_trackedSinceDate` cerca de la sección "Show More" (líneas 413-483). `firstDate = _openingDate`, `lastDate = DateTime.now()`. Patrón ya existente en el mismo archivo para `openingDate`.
- Edición: la fórmula de ajuste de `iniValue` al cambiar balance (líneas 92-95) no se afecta; pero hay que mostrar al usuario qué balance verá según el `trackedSince` elegido (preview opcional).

#### Estadísticas / dashboards (decisión de producto)
- `lib/app/stats/widgets/balance_bar_chart.dart:59-200` — balance por periodos.
- `lib/app/stats/widgets/income_expense_comparason.dart` — ingresos vs gastos.
- `lib/app/stats/widgets/fund_evolution_info.dart` — evolución de fondo.
- `lib/app/stats/widgets/income_by_source/` — ingresos por fuente (tú pediste este dashboard).
- **Decisión recomendada**: estadísticas **incluyen** transacciones pre-tracking por defecto (son datos históricos reales útiles). El balance actual es el único que las **excluye**. Opcional: toggle "Ocultar pre-tracking" en filtros de stats.

#### Presupuestos y recurrentes
- `lib/core/models/mixins/financial_target_mixin.dart` — `getValueOnDate()`: revisar si respeta `trackedSince` o ignora (budgets usualmente son forward-looking, el riesgo es bajo).
- `lib/core/database/services/transaction/transaction_service.dart:92-104` — `setTransactionNextPayment()`: si una recurrente genera una transacción con fecha < trackedSince (caso raro, normalmente genera futuras), aparece como histórico. Comportamiento aceptable.
- `lib/app/budgets/components/budget_evolution_chart.dart:42` — usar filtros del budget tal cual (no mezclar con trackedSince).

#### Sincronización / backup
- `lib/core/services/firebase_sync_service.dart` — serializar `trackedSince` al push/pull de cuentas.
- `lib/core/database/backup/backup_database_service.dart` — backups v24+ no compatibles hacia atrás (aceptable, documentar).
- `lib/app/settings/pages/backup/export_page.dart` — CSV export: opcional añadir columna `pre_tracking`; prioridad baja.

#### i18n
- `lib/i18n/json/es.json:536-559` — claves actuales bajo `ACCOUNT.FORM`. Añadir: `tracked-since`, `tracked-since.hint`, `tracked-since.info`, `BADGE.pre-tracking`, `BADGE.pre-tracking.tooltip`.
- Mismos strings en: `en.json`, `de.json`, `fr.json`, `hu.json`, `it.json`, `tr.json`, `uk.json`, `zh-CN.json`, `zh-TW.json` (10 idiomas). Para la Tanda personal basta con **es + en**; el resto puede quedar en fallback a EN.

---

### Approaches

#### 1. **Filtro SQL-side en `countTransactions`** (RECOMENDADO)
Parametrizar la query Drift `countTransactions` para aceptar un flag `respectTrackedSince`. `AccountService.getAccountsMoney()` lo pasa `true`; `StatsService` lo pasa `false`.

- **Pros**:
  - Un solo punto de cambio en el núcleo.
  - Se propaga automáticamente a los 10+ consumidores.
  - Performance óptima (filtro en DB).
  - Permite el caso "stats incluyen pre-tracking, balance no".
- **Cons**:
  - JOIN extra con `accounts` en cada llamada a `countTransactions` (coste mínimo, ya hay joins por currency).
  - Lógica condicional añadida a una query central.
- **Esfuerzo**: Medio.

#### 2. **Filtro Dart-side post-query**
Traer todas las transactions, filtrar en Dart por `tx.date >= account.trackedSince`.

- **Pros**:
  - No toca `.drift` queries.
- **Cons**:
  - Rompe el patrón actual (cálculos en SQL).
  - Performance: trae más datos de los necesarios.
  - Los streams tendrían que combinar accounts + transactions manualmente.
- **Esfuerzo**: Bajo en código, alto en consistencia.

#### 3. **Flag booleano por transacción (`excludeFromBalance`)** (REVISAR, se descartó en conversación pero lo dejamos documentado)
Añadir columna `excludeFromBalance` a `transactions`.

- **Pros**:
  - Granularidad máxima (marcar individualmente).
  - No requiere cambio a `accounts`.
- **Cons**:
  - No resuelve el caso de uso real (el usuario quiere "desde tal fecha", no fila por fila).
  - Fricción al importar N movimientos históricos (hay que marcar cada uno).
  - Ya descartado por el usuario.
- **Esfuerzo**: Bajo técnicamente, alto en UX.

---

### Recommendation

**Approach 1 (Filtro SQL-side en `countTransactions` con flag `respectTrackedSince`).**

Motivos:
1. El núcleo del cálculo vive en dos métodos (`getAccountsMoney` + `getTransactionsValueBalance`). Cambio quirúrgico.
2. Permite la decisión de producto clave: balance **excluye** pre-tracking, stats **incluyen** pre-tracking.
3. Drift ya tiene el patrón `$predicate` para predicados dinámicos — encaja.
4. El badge visual en `transaction_list_tile.dart` es un único cambio que cubre todos los feeds gracias a que el tile es reutilizado.
5. Retrocompatibilidad total: `trackedSince IS NULL` → comportamiento actual sin cambios.

Default para cuentas existentes al migrar: `NULL` (no romper nada). Default para cuentas **nuevas** creadas desde el form: también `NULL`, pero el formulario ofrece el toggle explícito "Empezar seguimiento desde [hoy]" que deja el usuario decidir.

---

### Risks

1. **Transferencias asimétricas cruzando `trackedSince`**: si cuenta A tiene `trackedSince = 2024-06-01` y cuenta B tiene `trackedSince = NULL`, una transfer A→B con fecha `2024-01-15` genera desbalance (no resta de A, sí suma a B). **Mitigación**: en el cálculo de balance, si la fecha de la transfer es anterior al `trackedSince` de **cualquiera** de las dos cuentas involucradas, ignorar ambas patas. Documentar y testear.

2. **Edición de `trackedSince` en cuenta ya usada**: si el usuario mueve `trackedSince` hacia adelante, transacciones reales pasan a ser "histórico" y el balance cambia súbitamente. **Mitigación**: diálogo de confirmación en el form mostrando el balance nuevo vs actual antes de guardar.

3. **Budgets que solapan la frontera**: un budget mensual que cubre un rango cruzando `trackedSince` puede dar cifras contraintuitivas. **Mitigación**: documentar que budgets **no** filtran por `trackedSince` (son forward-looking); si el usuario entra a pre-tracking es responsabilidad suya.

4. **Migración de datos**: `ALTER TABLE ADD COLUMN` en SQLite es seguro en v3.35+, pero conviene validar que la versión empaquetada por `sqlite3` flutter package lo soporte (casi seguro sí).

5. **Firebase sync retrocompatible**: push de una cuenta con `trackedSince` a un device en versión vieja puede fallar o ignorar el campo. **Mitigación**: bump de minimum app version tras el release.

6. **Performance del JOIN**: cada `countTransactions` hará JOIN adicional con `accounts` para leer `trackedSince`. En cuentas con >10k transacciones puede notarse. **Mitigación**: índice en `transactions.accountID` ya debería existir; verificar.

7. **`TrackedSince` antes de `account.date` (apertura)**: valor inválido. **Mitigación**: validar en form (`firstDate = openingDate`).

---

### Ready for Proposal

**Sí.** El siguiente paso es `sdd-propose` con alcance acotado a:
- Columna nueva `trackedSince` en `accounts` (migration v24).
- Modificación de `AccountService.getAccountsMoney()` + query Drift `countTransactions` con flag `respectTrackedSince`.
- Lógica simétrica para transfers cruzando la frontera.
- UI: DatePicker opcional en `account_form.dart` + badge "histórico" en `transaction_list_tile.dart`.
- i18n: claves en `es.json` + `en.json` (resto idiomas fallback EN).
- Sin cambios a estadísticas (incluyen pre-tracking por defecto).
- Sin cambios a budgets (forward-looking, irrelevante).

Out of scope (siguiente iteración o changes separados): toggle en stats para excluir pre-tracking, migración automática de cuentas existentes, integración con bulk-statement-ocr (change separado).
