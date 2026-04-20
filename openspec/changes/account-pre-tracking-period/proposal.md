# Proposal: account-pre-tracking-period

## Why

Una cuenta en Wallex no puede hoy tener saldo inicial correcto + historial de movimientos pasados a la vez: los movimientos históricos recalculan el balance y lo descuadran. Esto bloquea a un usuario que empieza a usar la app de cero y quiere meter su archivo de transacciones viejas sin perder la cifra real de saldo.

## What Changes

- [ ] Añadir columna nullable `trackedSince DATETIME` a tabla `accounts` (Drift migration `v24.sql`, schemaVersion 23 → 24).
- [ ] Exponer `trackedSince` en modelo dart `Account`.
- [ ] Modificar `AccountService.getAccountsMoney()` para excluir del balance transacciones con `date < account.trackedSince`.
- [ ] Parametrizar query Drift `countTransactions` con flag `respectTrackedSince` (balance = true, stats = false).
- [ ] Aplicar simetría en transfers: si una transfer cruza `trackedSince` de una cuenta, ignorar ambas patas del cálculo de balance.
- [ ] `DateTimeFormField` opcional en `account_form.dart` (firstDate = openingDate, lastDate = now).
- [ ] Diálogo de confirmación en form al cambiar `trackedSince` en cuenta ya usada (preview balance antes/después).
- [ ] Badge `Icons.history` (size 12, color disabled) en `transaction_list_tile.dart` cuando `tx.date < account.trackedSince`.
- [ ] Claves i18n en `es.json` + `en.json`: `ACCOUNT.FORM.tracked-since{,.hint,.info}`, `ACCOUNT.BADGE.pre-tracking{,.tooltip}`.

## Impact

**Drift migration**: sí (v24). `ALTER TABLE accounts ADD COLUMN trackedSince DATETIME`. Retrocompatible: `NULL` = comportamiento actual.

**Módulos afectados**:

| Área | Tipo | Archivos clave |
|------|------|----------------|
| DB schema | Nuevo + migración | `tables.drift:52-83`, `assets/sql/migrations/v24.sql`, `app_db.dart:115` |
| Domain model | Modificado | `core/models/account/account.dart:52-128` |
| Balance core | Modificado | `core/database/services/account/account_service.dart:135-212`, `sql/queries/select-full-data.drift:112-173` |
| Transactions service | Modificado | `core/database/services/transaction/transaction_service.dart:200-348` |
| UI form | Modificado | `app/accounts/account_form.dart:38-493` |
| UI row badge | Modificado | `app/transactions/widgets/transaction_list_tile.dart:154-215` |
| i18n | Modificado | `lib/i18n/json/es.json`, `en.json` + regeneración slang |

**Breaking changes**: ninguno. Cuentas existentes quedan con `trackedSince = NULL` → balance idéntico al actual.

## Out of Scope

- Toggle en stats/dashboards para excluir pre-tracking (stats incluyen por defecto).
- Integración con `bulk-statement-ocr` (change siguiente).
- Migración automática de cuentas existentes a `DateTime.now()`.
- Budgets (forward-looking, no aplican).
- CSV export marcando pre-tracking.
- Sync Firebase del campo (posponer hasta validar en local).

## Rollback Plan

1. Revertir migración con `v25.sql`: `ALTER TABLE accounts DROP COLUMN trackedSince` (SQLite 3.35+) o recrear tabla vía swap.
2. Revertir commits de `AccountService`, `account_form`, `transaction_list_tile`, i18n.
3. Restaurar `schemaVersion = 23`.
4. Dado que `trackedSince = NULL` ya significa "todo cuenta", desplegar sólo la reversión de UI mantiene datos intactos — la columna puede quedar huérfana sin impacto funcional.

## Open Questions

1. **Default en cuentas nuevas**: ¿el form sugiere `trackedSince = DateTime.now()` pre-rellenado (opt-out), o deja `NULL` por defecto (opt-in)? Impacta friction de onboarding.
2. **Edición retroactiva**: ¿bloquear edición de `trackedSince` si hay transacciones que cruzarían y pondría balance negativo, o solo advertir?
3. **Naming i18n**: ¿"Período de seguimiento" / "Comenzar a rastrear desde" / "Tracking inicial"? Decidir en spec.
