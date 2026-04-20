# Proposal: statement-reconciliation

## Why

Wallex no cuadra con el saldo real de las cuentas del usuario (BDV principalmente). Hay decenas de movimientos y comisiones faltantes; registrarlos manualmente es inviable. Este change introduce un importador de estado de cuenta que lee fotos o PDFs vía Nexus AI multimodal, concilia contra las transacciones existentes y permite aprobar por modos combinables lo que falta.

## What Changes

**Fase 1 — Infra DB**
- [ ] Migration `v25.sql`: tabla `statement_import_batches(id, accountId, createdAt, mode, transactionIds TEXT)`. SchemaVersion 24→25.
- [ ] Modelos `ExtractedRow`, `MatchingResult`, `ImportBatch`.

**Fase 2 — Core**
- [ ] `StatementExtractorService`: adapta prompt Nexus AI para recibir array `{transactions: [...]}`.
- [ ] `MatchingEngine`: scoring fecha+monto+signo, flags `existsInApp`/`isPreFresh`/`kind`, consume-IDs contra doble match.
- [ ] `PdfToImageService`: rasteriza página 1 a imagen.
- [ ] Fecha pivote: `exif` package + fallback editable.

**Fase 3 — UI Screens 1-2**
- [ ] `statement_import_flow.dart` navegador.
- [ ] Screen 1 Captura (hero doc + dos CTAs foto/PDF).
- [ ] Screen 2 Procesando (scan line, contador, skeleton).

**Fase 4 — UI Screens 3-4-5**
- [ ] Screen 3 Revisar con `ModeChips` (5 modos AND), `Counter`, `RowTile` con tags, banner warning si `informative + post-trackedSince`, botón Todos/Ninguno.
- [ ] Screen 4 Confirmar (desglose Ingresos/Gastos/Comisiones, chip "Historial · no afecta balance").
- [ ] Screen 5 Éxito (animación ring+check, CTAs Ver historial / Listo).

**Fase 5 — i18n + entry + undo**
- [ ] Rama `STATEMENT_IMPORT.*` en `es.json` + `en.json`. `dart run slang`.
- [ ] Entry point botón "Importar estado de cuenta" en `account_details.dart`.
- [ ] Undo 7 días: cron local purga batches, botón desde historial de la cuenta.

**Fase 6 — Smoke test MIUI**
- [ ] Probar con screenshots reales BDV + matching + 5 modos + undo.

## Impact

| Área | Tipo | Nota |
|---|---|---|
| Drift schema | **Migration v25** | tabla nueva, no muta existentes |
| `pubspec.yaml` | Packages | `exif` + PDF rasterizer (elegir en design) |
| `NexusAiService` | Reutilizado | cero cambios |
| `ReceiptImageService` | Reutilizado | cero cambios |
| `Account.trackedSince` | Reutilizado | modo informativas lo aprovecha |
| Backend Nexus (AI_infi) | Cero | agnóstico al schema |
| Breaking changes | Ninguno | feature nueva aislada |

## Out of Scope

Multi-imagen batch · multi-página PDF · fuzzy matching descripción · auto-categoría comisiones (change `bank-fees-autocategorization` separado) · campo `bankRef` en transactions · bancos fuera de VE.

## Open Questions

1. Copy sustituto de "OCR EN DISPOSITIVO" → propuesta: **"IA privada · tu infraestructura"**.
2. Ubicación exacta del botón en `account_details.dart`.
3. Modo informativas sin `trackedSince` configurado: diálogo obligatorio "Configura Fresh Start primero" con CTA al form.
4. Package PDF: `printing` vs `native_pdf_renderer` vs `syncfusion_flutter_pdf`. Decidir en `sdd-design`.

## Rollback Plan

Feature aislada en carpetas nuevas. Rollback limpio:
1. Revertir migration v25 (DROP TABLE `statement_import_batches`) vía `v26.sql` o dejar huérfana (no referenciada).
2. Revertir `schemaVersion` a 24.
3. Eliminar código nuevo en `lib/app/accounts/statement_import/` + `lib/core/services/statement_import/`.
4. Quitar botón entry point de `account_details.dart`.
5. Revertir claves i18n + slang regen.
6. Ninguna tx existente se altera.

## Success Criteria

- [ ] Ramses cuadra una cuenta BDV real con un único import end-to-end.
- [ ] `flutter analyze` limpio tras cada tanda.
- [ ] Los 5 modos combinables funcionan con AND en device MIUI.
- [ ] Undo desde historial borra el batch dentro de 7 días.
- [ ] Modo informativas inserta con fecha < `trackedSince` → balance no cambia.

## Dependencies

- `account-pre-tracking-period` ya implementado (solo pendiente smoke test) — el modo informativas depende de `Account.trackedSince`.
- Nexus AI Gateway activo en `api.ramsesdb.tech` con presupuesto multimodal.
