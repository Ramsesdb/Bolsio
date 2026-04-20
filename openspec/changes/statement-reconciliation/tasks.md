# Tasks: statement-reconciliation

## Fase 1 — Infra DB + modelos

- [x] 1.1 Crear `assets/sql/migrations/v25.sql`: `CREATE TABLE statement_import_batches` con columnas `id PK`, `accountId FK accounts ON DELETE CASCADE`, `createdAt`, `mode TEXT`, `transactionIds TEXT`; añadir índices `idx_sib_account` e `idx_sib_created`
- [x] 1.2 Modificar `lib/core/database/sql/initial/tables.drift`: añadir definición de la tabla `statement_import_batches` como mirror de v25
- [x] 1.3 Modificar `lib/core/database/app_db.dart`: elevar `schemaVersion` a 25 y añadir rama de migración 24→25
- [x] 1.4 Ejecutar `dart run build_runner build --delete-conflicting-outputs` y verificar que no hay errores
- [x] 1.5 Crear `lib/core/services/statement_import/models/extracted_row.dart`: Freezed model con campos `id`, `amount`, `kind`, `date`, `description`, `confidence`
- [x] 1.6 Crear `lib/core/services/statement_import/models/matching_result.dart`: Freezed model con campos `row: ExtractedRow`, `existsInApp`, `isPreFresh`, `matchedTransactionId`
- [x] 1.7 Crear `lib/core/services/statement_import/models/import_batch.dart`: Freezed model con campos `id`, `accountId`, `createdAt`, `modes: List<String>`, `transactionIds: List<String>`
- [x] 1.8 Ejecutar `dart run build_runner build --delete-conflicting-outputs` para regenerar archivos `.freezed.dart`

## Fase 2 — Core services

- [x] 2.1 Crear `lib/core/services/statement_import/statement_extractor_service.dart`: orquestar llamada a `NexusAiService.completeMultimodal` con systemPrompt y userPrompt del design; parser tolerante (extraer JSON dentro de markdown o prosa); retry 1x con prompt estricto si falla el parse; lanzar excepción si el segundo intento también falla
- [x] 2.2 Crear `lib/core/services/statement_import/matching_engine.dart`: implementar `Future<List<MatchingResult>> matchRows({required String accountId, required List<ExtractedRow> rows, required DateTime? trackedSince})`; score = 0.4(mismo día) + 0.4(monto diff<0.005) + 0.2(signo); threshold 0.8; consume-IDs set; flag `isPreFresh` con `trackedSince`
- [x] 2.3 Crear `lib/core/services/statement_import/pdf_to_image_service.dart`: usar `pdfx` para rasterizar página 1 a imagen; exponer `pageCount` para detectar PDFs multi-página
- [x] 2.4 Crear `lib/core/services/statement_import/statement_batches_service.dart`: método `commit` (insert N tx + insert batch en una sola Drift transaction atómica), método `undo(batchId)` (delete tx + delete batch), método `purge` (elimina batches con `createdAt < now - 7 días`)

## Fase 3 — UI Screens 1 y 2

- [x] 3.1 Crear `lib/app/accounts/statement_import/statement_import_flow.dart`: Navigator de 5 screens que mantiene estado compartido (`accountId`, `pivotDate`, `extractedRows`, `matchingResults`, `batchId`)
- [x] 3.2 Crear `lib/app/accounts/statement_import/widgets/si_header.dart`: header reutilizable con `AccountTile` compacto que muestra la cuenta destino
- [x] 3.3 Crear `lib/app/accounts/statement_import/screens/capture.page.dart` (Screen 1): hero documento animado, 2 CTAs (Tomar foto / Subir PDF o imagen), lectura EXIF automática, date picker si no hay EXIF, warning si PDF con más de 1 página
- [x] 3.4 Crear `lib/app/accounts/statement_import/screens/processing.page.dart` (Screen 2): animación scan line, contador "{N} encontrados", skeleton rows, botón cancelar que aborta el request en curso

## Fase 4 — UI Screens 3, 4 y 5 + widgets + undo

- [x] 4.1 Crear `lib/app/accounts/statement_import/widgets/mode_chips.dart`: 5 chips combinables con semántica AND (`missing`, `income`, `expense`, `fees`, `informative`); etiqueta "AND · N criterios" si ≥2 activos; botón Limpiar si ≥1 activo
- [x] 4.2 Crear `lib/app/accounts/statement_import/widgets/row_tile.dart`: fila con tags (Ya existe / Comisión / Pre-Fresh), checkbox, monto con color según `kind`
- [x] 4.3 Crear `lib/app/accounts/statement_import/widgets/counter.dart`: contador prominente "N de M filas se importarán"
- [x] 4.4 Crear `lib/app/accounts/statement_import/screens/review.page.dart` (Screen 3): `SiHeader` + `ModeChips` + `Counter` + lista `RowTile` + toggle Todos/Ninguno; banner warning si `informative` activo con filas `date >= trackedSince`; diálogo bloqueante si `informative` activo y `trackedSince == null`; mensaje "No se detectaron movimientos" si array vacío
- [x] 4.5 Crear `lib/app/accounts/statement_import/screens/confirm.page.dart` (Screen 4): contador grande, nombre cuenta, card desglose Ingresos/Gastos/Comisiones por `kind`, chip "Historial · no afecta balance" si modo `informative`, helper undo 7 días, botones Volver/Importar
- [x] 4.6 Crear `lib/app/accounts/statement_import/screens/success.page.dart` (Screen 5): animación check ring, contador grande de transacciones importadas, CTAs "Ver en historial" / "Listo"
- [x] 4.7 Identificar el archivo de lista de transacciones de la cuenta en `lib/app/accounts/details/`; añadir opción "Deshacer importación" visible únicamente para batches con `createdAt` dentro de los últimos 7 días

## Fase 5 — i18n + entry point + pubspec + purge

- [x] 5.1 Modificar `pubspec.yaml`: añadir `pdfx: ^2.9.0` y `exif: ^3.3.0`; ejecutar `flutter pub get` — **completo**: `pdfx: ^2.9.0` (resuelto a 2.9.2) y `exif: ^3.3.0` añadidos en Fase 2/3 respectivamente; pub get ejecutado sin errores
- [x] 5.2 Modificar `lib/i18n/json/es.json` y `en.json`: añadir rama `STATEMENT_IMPORT.*` con claves para headers, 5 labels de modos, tags (Ya existe / Comisión / Pre-Fresh), banners de warning, CTAs, mensajes de error/timeout/vacío
- [x] 5.3 Ejecutar `dart run slang` y verificar que los archivos generados compilan sin errores
- [x] 5.4 Modificar `lib/app/accounts/details/account_details.dart`: añadir botón "Importar estado de cuenta" que abre `StatementImportFlow` con `accountId`; ocultar el botón si la cuenta tiene `closingDate`
- [x] 5.5 Registrar purge al arrancar la app: localizar el widget raíz o `main.dart` donde se inicializan servicios; llamar `StatementBatchesService.purge()` via `WidgetsBinding.instance.addPostFrameCallback`

## Fase 6 — Smoke test manual MIUI

- [ ] 6.1 Ejecutar `flutter analyze` y resolver cualquier advertencia hasta salida limpia
- [ ] 6.2 Instalar en device MIUI y probar flujo completo con screenshot BDV real: captura → procesado → revisión con chips → confirmar → éxito → ver historial
- [ ] 6.3 Verificar modo `informative` con `trackedSince` configurado: transacciones con `date < trackedSince` no afectan el balance de la cuenta
- [ ] 6.4 Verificar undo desde historial: "Deshacer importación" elimina el batch completo y sus transacciones dentro de la ventana de 7 días
- [ ] 6.5 Verificar comportamiento PDF: warning "Solo procesaremos la página 1" se muestra si el PDF tiene más de una página antes de continuar

---

## Notas de implementación

### No tocar

- `NexusAiService` — reutilizar sin modificaciones
- `ReceiptImageService` — reutilizar sin modificaciones
- Lógica core de balance (`Transaction`, cálculos existentes) — el modo informativas aprovecha `Account.trackedSince` ya implementado; cero cambios adicionales
- Backend Nexus (`AI_infi`, `api.ramsesdb.tech`) — agnóstico al schema del prompt

### Preguntas abiertas

Ninguna — todas resueltas en el design (decisiones 1–9).
