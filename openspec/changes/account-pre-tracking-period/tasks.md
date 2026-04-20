# Tasks: account-pre-tracking-period

## Fase 1 — Infrastructure (DB + modelo)

- [x] 1.1 Crear `assets/sql/migrations/v24.sql` con `ALTER TABLE accounts ADD COLUMN trackedSince DATETIME;`
- [x] 1.2 Añadir columna `trackedSince DATETIME` a la definición de `accounts` en `lib/core/database/sql/initial/tables.drift:52-83`
- [x] 1.3 Bumpear `schemaVersion => 24` en `lib/core/database/app_db.dart:115`
- [x] 1.4 Registrar v24 en el loop de migraciones de `app_db.dart` (verificar patrón `v$i.sql` existente)
- [x] 1.5 Ejecutar `dart run build_runner build --delete-conflicting-outputs` (requiere 1.2)
- [x] 1.6 Exponer `trackedSince` en `lib/core/models/account/account.dart:52-128` (constructor + copyWith + fromDB/toDB)
- [x] 1.7 Añadir helper `bool isTrackingHistorical(DateTime txDate)` al modelo `Account`

## Fase 2 — Core logic (balance + filtros)

- [x] 2.1 Añadir flag `bool respectTrackedSince = false` a `TransactionFilterSet` en `lib/core/presentation/widgets/transaction_filter/transaction_filter_set.dart` (incluir en `copyWith`)
- [x] 2.2 Modificar builder de predicado en `lib/core/database/services/transaction/transaction_service.dart` para añadir, cuando flag=true, los dos predicados SQL del design (`a.trackedSince IS NULL OR t.date >= a.trackedSince` y simétrico para `ra`)
- [x] 2.3 En `lib/core/database/services/account/account_service.dart:135-212`, pasar `respectTrackedSince: true` al `trFilters.copyWith(...)` dentro de `getAccountsMoney`
- [x] 2.4 Crear `getAccountsMoneyPreview({required String accountId, required DateTime? simulatedTrackedSince})` en `account_service.dart` — usa el mismo pipeline con override en memoria, sin persistir
- [x] 2.5 Verificar que `getAccountsMoneyVariation`, `debt_service`, stats widgets **no** pasan `respectTrackedSince=true` (default false preserva comportamiento)

## Fase 3 — UI formulario de cuenta

- [x] 3.1 Añadir estado `DateTime? _trackedSinceDate` a `_AccountFormPageState` en `lib/app/accounts/account_form.dart`
- [x] 3.2 Añadir `DateTimeFormField` bajo la sección "Show More" con `firstDate = _openingDate`, `lastDate = DateTime.now()`, label i18n
- [x] 3.3 Añadir validación: bloquear submit si `_trackedSinceDate != null && closingDate != null && _trackedSinceDate > closingDate`, mostrando snackbar con clave i18n
- [x] 3.4 En `submitForm()`, si editando cuenta existente con transacciones y `_trackedSinceDate` cambió: calcular `balanceActual` (getAccountsMoney) y `balanceNuevo` (getAccountsMoneyPreview)
- [x] 3.5 Si cuenta sin transacciones o sin cambio en `trackedSince` → persistir directo, saltar diálogo
- [x] 3.6 Implementar widget `RetroactivePreviewDialog` (simple): muestra X → Y, botones Aceptar/Cancelar
- [x] 3.7 Implementar widget `RetroactiveStrongConfirmDialog`: preview + TextField "CONFIRMAR", disparado si `Y < 0 || |X-Y| > 0.5 * |X|`
- [x] 3.8 Cablear ambos diálogos al flujo de submit; cancel descarta cambio

## Fase 4 — UI badge histórico

- [x] 4.1 En `lib/app/transactions/widgets/transaction_list_tile.dart:173-192`, leer `transaction.account.trackedSince` y calcular `isHistorical = account.isTrackingHistorical(transaction.date)`
- [x] 4.2 Añadir `Icon(Icons.history, size: 12, color: Theme.of(context).disabledColor)` envuelto en `Tooltip` junto a los badges existentes cuando `isHistorical`
- [x] 4.3 Verificar que `transaction.account` está siempre populado en el modelo (no solo `accountId`); ajustar query si no — confirmado: `getTransactionsWithFullData` selecciona `a.** as account` (select-full-data.drift:37); `MoneyTransaction.account` es `Account` (domain model) via `Account.fromDB(account, accountCurrency)` en el constructor (transaction.dart:60)

## Fase 5 — i18n

- [x] 5.1 Añadir a `lib/i18n/json/es.json` bajo `ACCOUNT.FORM`: `tracked-since`, `tracked-since.hint`, `tracked-since.info`, `tracked-since.validation-after-closing`
- [x] 5.2 Añadir a `es.json` bajo `ACCOUNT.BADGE`: `pre-tracking`, `pre-tracking.tooltip`
- [x] 5.3 Añadir a `es.json` bajo `ACCOUNT.RETROACTIVE`: `preview-title`, `preview-message`, `strong-confirm-hint`, `strong-confirm-mismatch`, `accept`, `cancel`
- [x] 5.4 Replicar todas las claves en `lib/i18n/json/en.json`
- [x] 5.5 Ejecutar `dart run slang` para regenerar `translations.g.dart`

## Fase 6 — Verificación estática y smoke test manual

- [ ] 6.1 Ejecutar `flutter analyze` y resolver warnings (sin `flutter test`, por preferencia del usuario)
- [ ] 6.2 `flutter run` en device MIUI (toggle notification listener si aplica)
- [ ] 6.3 Smoke: crear cuenta nueva sin `trackedSince` → balance idéntico al comportamiento previo
- [ ] 6.4 Smoke: crear cuenta con `trackedSince`, añadir tx anterior → badge visible, balance excluye
- [ ] 6.5 Smoke: transfer entre cuenta-con-tracking y cuenta-sin-tracking con fecha anterior → balance correcto en ambas
- [ ] 6.6 Smoke: editar `trackedSince` retroactivo con diff <50% → diálogo simple
- [ ] 6.7 Smoke: editar forzando balance nuevo negativo → diálogo CONFIRMAR; texto incorrecto cancela
- [ ] 6.8 Smoke: intentar `trackedSince > closingDate` → validación bloquea
- [ ] 6.9 Smoke: reiniciar app → verificar migración v24 no rompe cuentas existentes

---

## Notas de implementación

### Qué NO hacer (out of scope)

- No añadir `trackedSince` a `firebase_sync_service.dart` (sync pospuesto hasta validar feature en local).
- No tocar stats widgets (`balance_bar_chart`, `income_expense_comparason`, `fund_evolution`, `income_by_source`). Deben seguir pasando `respectTrackedSince=false` → comportamiento actual preservado.
- No añadir columna `pre_tracking` al CSV export.
- No migrar cuentas existentes a `trackedSince = DateTime.now()` — quedan NULL.
- No tocar budgets (forward-looking, irrelevante).

### Preguntas abiertas a resolver durante apply

- Umbral 50% para confirmación extra: hardcoded como constante en `account_form.dart`. Revisar tras feedback real.
- `closingDate < trackedSince` se resuelve como **bloqueo** con mensaje de validación (decisión definitiva).

### Dependencias críticas

- Fase 2 requiere Fase 1 completa (modelo Account con `trackedSince`).
- Fase 3 requiere 2.4 (método preview) completo.
- Fase 4 requiere 1.7 (helper `isTrackingHistorical`) completo.
- Fase 5 puede correr en paralelo con Fase 3/4 (tarea textual independiente).
