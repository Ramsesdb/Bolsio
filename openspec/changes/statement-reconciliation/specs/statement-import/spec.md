# Delta for statement-import

## ADDED Requirements

### Requirement: Entry point desde detalle de cuenta

El detalle de una cuenta activa MUST exponer una acción "Importar estado de cuenta" que inicie el flujo de importación pasando `accountId` como contexto.

#### Scenario: Usuario abre el flujo desde su cuenta

- GIVEN una cuenta activa "BDV" abierta en el detalle
- WHEN el usuario toca "Importar estado de cuenta"
- THEN se abre Screen 1 Captura con `accountId` fijado

#### Scenario: Cuenta cerrada

- GIVEN una cuenta con `closingDate` en el pasado
- WHEN se renderiza su detalle
- THEN la acción "Importar estado de cuenta" SHOULD estar oculta o deshabilitada

---

### Requirement: Captura de imagen o PDF

El flujo MUST aceptar tres fuentes: cámara, galería, archivo PDF. Si el PDF tiene más de una página, MUST advertir que solo se procesa la página 1. La fecha pivote MUST derivarse de EXIF si está presente; sino MUST solicitarse con un picker pre-rellenado a `DateTime.now()`.

#### Scenario: Foto con EXIF válido

- GIVEN el usuario toma una foto con metadato de fecha `2026-04-17`
- WHEN selecciona la imagen
- THEN el flujo usa `2026-04-17` como fecha pivote sin preguntar

#### Scenario: PDF multi-página

- GIVEN un PDF con 4 páginas
- WHEN el usuario lo selecciona
- THEN se muestra warning "Solo procesaremos la página 1" antes de continuar

---

### Requirement: Extracción vía Nexus AI multimodal

El Screen 2 MUST llamar `NexusAiService.completeMultimodal` con prompt que solicite JSON `{transactions: [...]}`. El parser MUST tolerar markdown/prosa alrededor del JSON. MUST permitir cancelar la operación. Timeout 30 s con reintento manual.

#### Scenario: Extracción exitosa

- GIVEN una imagen válida y `api.ramsesdb.tech` responde en <30 s
- WHEN se completa la llamada
- THEN se obtiene un array con filas `{amount, kind, date, description, confidence?}` y el flujo avanza a Screen 3

#### Scenario: Timeout

- GIVEN Nexus AI no responde en 30 s
- WHEN vence el timeout
- THEN se muestra error inline "No pudimos leer. Reintenta" con botón Reintentar

---

### Requirement: Matching con transacciones existentes

El MatchingEngine MUST consultar `transactions` de la cuenta en ventana `[minRowDate - 1 día, maxRowDate + 1 día]`. Score por fila = 0.4 (mismo día) + 0.4 (monto diff < 0.005) + 0.2 (signo coincide). Score ≥ 0.8 → `existsInApp = true` y la tx matcheada se marca consumida. Cada fila MUST calcular `isPreFresh = account.trackedSince != null AND row.date < account.trackedSince`.

#### Scenario: Match exacto

- GIVEN una fila OCR 25/02 −50 Bs y una tx en DB con misma fecha y monto
- WHEN corre el matcher
- THEN la fila queda `existsInApp = true`

#### Scenario: Doble match protegido

- GIVEN dos filas OCR 10/04 −10 Bs y una sola tx en DB de 10/04 −10 Bs
- WHEN corre el matcher
- THEN la primera queda `existsInApp = true`, la segunda `existsInApp = false`

---

### Requirement: Pantalla de revisión con modos chips

Screen 3 MUST mostrar 5 chips combinables (`missing`, `income`, `expense` excluye fees, `fees`, `informative`) con semántica AND. Counter prominente muestra "N de M filas se importarán". Toggle "Todos/Ninguno" en header. Cuando ≥2 chips activos, MUST mostrar etiqueta "AND · N criterios". Botón "Limpiar" visible si ≥1 chip activo.

#### Scenario: Filtro combinado missing + fees

- GIVEN 10 filas OCR, 3 son fees, de ellas 2 con `existsInApp = true`
- WHEN el usuario activa chips `missing` y `fees`
- THEN el counter muestra "1 de 10" y la lista renderiza solo 1 fila visible

#### Scenario: Tags por fila

- GIVEN una fila con `existsInApp = true`, `kind = 'fee'`, `isPreFresh = true`
- WHEN se renderiza
- THEN muestra los tres tags: "Ya existe", "Comisión", "Pre-Fresh"

---

### Requirement: Modo informativas — precondición y warning

Si el usuario activa chip `informative` y la cuenta destino NO tiene `trackedSince`, MUST bloquearse con diálogo "Configura Fresh Start primero" que enlaza al form de cuenta. Si `informative` queda activo y hay filas seleccionadas con `date >= account.trackedSince`, MUST mostrarse banner warning inline (no bloquea).

#### Scenario: Cuenta sin Fresh Start

- GIVEN la cuenta BDV con `trackedSince = NULL`
- WHEN el usuario toca chip `informative`
- THEN se abre diálogo con CTA que lleva al form; el chip no queda activo hasta configurarlo

#### Scenario: Warning por fechas post-Fresh-Start

- GIVEN `trackedSince = 2026-03-01` y 3 filas con fechas de abril seleccionadas
- WHEN se activa chip `informative`
- THEN arriba de la lista aparece banner "Algunas filas tienen fecha posterior al Fresh Start"

---

### Requirement: Confirmación y desglose

Screen 4 MUST mostrar contador grande, nombre de cuenta destino, card de desglose (Ingresos / Gastos / Comisiones) calculado por `kind`, helper de undo 7 días. Si modo `informative` activo, MUST mostrar chip "Historial · no afecta balance".

#### Scenario: Modo informativas confirma

- GIVEN 5 filas aprobadas con modo `informative` activo
- WHEN se renderiza Screen 4
- THEN aparece chip "Historial · no afecta balance" y el CTA principal es "Importar"

---

### Requirement: Commit atómico del batch

La confirmación MUST insertar las transacciones en una sola transacción Drift y crear un row en `statement_import_batches(id, accountId, createdAt, mode, transactionIds)`. Si algún insert falla, MUST hacer rollback completo.

#### Scenario: Rollback por fallo

- GIVEN 8 filas a insertar y la 5ª viola una constraint
- WHEN ocurre el error
- THEN ninguna fila queda persistida y el batch NO se crea; se muestra error

#### Scenario: Éxito

- GIVEN 7 filas válidas
- WHEN se confirma
- THEN las 7 aparecen en `transactions` y el batch queda registrado con los 7 IDs

---

### Requirement: Éxito y navegación al historial

Screen 5 MUST mostrar animación check + contador grande + CTA "Ver en historial" (abre lista de transacciones de la cuenta con filtro por `batchId`) y CTA secundaria "Listo".

#### Scenario: Ver historial tras import

- GIVEN import de 5 transacciones completado
- WHEN el usuario toca "Ver en historial"
- THEN abre la lista de transacciones filtrada por ese `batchId`

---

### Requirement: Undo 7 días

En la lista de transacciones de la cuenta, cada batch con `createdAt` dentro de los últimos 7 días MUST exponer acción "Deshacer importación". Al deshacer, MUST eliminar las `transactions` con IDs del batch y el batch row. Batches con `createdAt > 7 días` MUST limpiarse automáticamente al arrancar la app.

#### Scenario: Deshacer dentro de ventana

- GIVEN un batch de hace 3 días con 6 transacciones
- WHEN el usuario toca "Deshacer importación"
- THEN las 6 transacciones y el batch se eliminan

#### Scenario: Batch expirado se purga

- GIVEN un batch con `createdAt` de hace 8 días
- WHEN la app arranca
- THEN el batch row se elimina (las transacciones quedan intactas)

---

### Requirement: Migración v25 retrocompatible

Migration `v25.sql` MUST añadir tabla `statement_import_batches(id PK, accountId FK accounts ON DELETE CASCADE, createdAt, mode TEXT, transactionIds TEXT)`. `schemaVersion` MUST pasar de 24 a 25. Ninguna tabla existente MUST alterarse.

#### Scenario: Migración limpia

- GIVEN schema v24 con 3 cuentas y 200 transacciones
- WHEN se aplica v25
- THEN la tabla nueva existe vacía y las otras quedan idénticas

#### Scenario: Cascada al borrar cuenta

- GIVEN una cuenta con 2 batches asociados
- WHEN la cuenta se elimina
- THEN los 2 batches se eliminan por la FK con ON DELETE CASCADE

---

### Requirement: Edge cases

- OCR devuelve array vacío → Screen 3 MUST mostrar mensaje "No se detectaron movimientos" y botón Volver.
- Multi-currency: Bolsio NO convierte moneda en v1; `amount` se registra tal cual lo devuelve el AI.
- PDF escaneado vs PDF con texto: ambos tratados igual (rasterizados).

#### Scenario: OCR vacío

- GIVEN el AI devuelve `{transactions: []}`
- WHEN Screen 3 se renderiza
- THEN muestra mensaje "No se detectaron movimientos" y botón Volver a Screen 1

#### Scenario: Moneda distinta a la cuenta

- GIVEN cuenta en USD y screenshot con montos en VES
- WHEN se extrae la fila "+50"
- THEN se registra como `amount = 50` en USD (sin conversión) — el usuario debe verificar manualmente
