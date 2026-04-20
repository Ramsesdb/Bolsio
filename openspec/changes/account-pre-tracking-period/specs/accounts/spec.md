# Delta for accounts

## ADDED Requirements

### Requirement: Campo `trackedSince` en cuenta

Cada cuenta MUST tener un campo `trackedSince` de tipo `DATETIME` nullable. El valor por defecto MUST ser `NULL` tanto en cuentas nuevas como en cuentas existentes tras la migración (opt-in). Cuando `trackedSince IS NULL`, el comportamiento de cálculo de balance MUST ser idéntico al previo a este change (todas las transacciones afectan balance).

#### Scenario: Cuenta nueva creada sin activar tracking

- GIVEN un usuario crea una cuenta desde el formulario
- WHEN no toca el campo "Rastrear desde"
- THEN la cuenta se persiste con `trackedSince = NULL`
- AND el balance se calcula con todas las transacciones

#### Scenario: Cuenta preexistente tras migrar a v24

- GIVEN una cuenta que existía antes de aplicar la migración v24
- WHEN la base de datos migra a schema v24
- THEN `trackedSince` queda en `NULL` para esa cuenta
- AND su balance actual no cambia

---

### Requirement: Cálculo de balance excluye transacciones pre-tracking

Cuando `account.trackedSince` no es `NULL`, el balance actual de la cuenta MUST calcularse como `iniValue + SUM(transactions WHERE accountID = X AND date >= trackedSince)`, aplicando además la regla de simetría de transfers. Las transacciones con `date < trackedSince` MUST NOT afectar el balance. La conversión multi-currency MUST aplicarse después del filtro temporal, no antes.

#### Scenario: Transacción exactamente igual a `trackedSince` sí cuenta

- GIVEN una cuenta con `trackedSince = 2026-04-15 00:00:00` y `iniValue = 100 Bs`
- AND una transacción de ingreso 50 Bs con fecha `2026-04-15 00:00:00`
- WHEN se consulta el balance actual
- THEN el balance resulta `150 Bs`

#### Scenario: Transacción anterior queda fuera del balance

- GIVEN una cuenta con `trackedSince = 2026-04-01` y `iniValue = 100 Bs`
- AND una transacción de gasto 40 Bs con fecha `2026-03-20`
- WHEN se consulta el balance actual
- THEN el balance resulta `100 Bs`

#### Scenario: Cuenta en USD mostrada en VES como preferred

- GIVEN una cuenta en USD con `trackedSince = 2026-04-01` e `iniValue = 10 USD`
- AND una transacción ingreso 5 USD con fecha `2026-04-10`
- AND preferred currency es VES con tasa de cambio activa
- WHEN se consulta el balance en preferred
- THEN el cálculo filtra primero por fecha, luego convierte `15 USD` a VES

---

### Requirement: Simetría de transfers cruzando la frontera

Dada una transfer entre cuentas A y B con fecha D: si `D < A.trackedSince` OR `D < B.trackedSince`, la transfer MUST ser ignorada por completo del cálculo de balance en ambas cuentas. Si D es posterior o igual a `trackedSince` de ambas cuentas (o ambos son NULL), la transfer MUST afectar balances normalmente.

#### Scenario: Transfer pre-tracking en una sola pata no desbalancea

- GIVEN cuenta A con `trackedSince = 2026-06-01`
- AND cuenta B con `trackedSince = NULL`
- AND una transfer A→B de 100 Bs con fecha `2026-01-15`
- WHEN se consultan ambos balances
- THEN ni A ni B ven afectado su balance por esa transfer

#### Scenario: Transfer válida en ambos lados

- GIVEN cuenta A con `trackedSince = 2026-01-01` y cuenta B con `trackedSince = NULL`
- AND una transfer A→B de 100 Bs con fecha `2026-04-10`
- WHEN se consultan ambos balances
- THEN A disminuye 100, B aumenta 100

---

### Requirement: Visibilidad y badge de transacciones pre-tracking

Las transacciones con `date < account.trackedSince` MUST seguir apareciendo en todos los feeds (detalle de cuenta, lista global, dashboard home, búsqueda). MUST mostrar un badge "Histórico" (icono `Icons.history` tamaño 12, color disabled del tema) con tooltip "No afecta el balance actual". MUST seguir siendo editables y eliminables.

#### Scenario: Transacción pre-tracking visible con badge

- GIVEN una cuenta con `trackedSince = 2026-04-01`
- AND una transacción con fecha `2026-03-10`
- WHEN el usuario abre el detalle de la cuenta
- THEN la transacción aparece en la lista con badge "Histórico"

#### Scenario: Editar transacción pre-tracking

- GIVEN la misma transacción anterior con badge
- WHEN el usuario la edita y guarda
- THEN los cambios se persisten sin restricciones adicionales

---

### Requirement: Estadísticas incluyen transacciones pre-tracking

Los widgets de estadísticas (balance_bar_chart, income_expense_comparason, fund_evolution, income_by_source) MAY incluir transacciones pre-tracking por defecto. El "balance actual" mostrado en headers MUST excluirlas, usando el núcleo modificado de cálculo de balance.

#### Scenario: Gráfico de ingresos/gastos incluye histórico

- GIVEN una cuenta con `trackedSince = 2026-04-01` y transacciones antes y después
- WHEN el usuario ve stats del rango `2026-03-01` a `2026-04-30`
- THEN las transacciones de marzo aparecen en el gráfico

#### Scenario: Header de cuenta excluye histórico

- GIVEN la misma cuenta anterior
- WHEN el usuario abre detalle de la cuenta
- THEN el balance actual del header solo refleja transacciones `>= 2026-04-01`

---

### Requirement: Formulario crea cuenta con tracking opcional

El formulario de creación de cuenta MUST incluir un campo opcional "Rastrear desde" (DateTimeFormField). `firstDate` MUST ser igual a la fecha de apertura elegida. `lastDate` MUST ser `DateTime.now()`. Dejar el campo vacío MUST resultar en `trackedSince = NULL`. Label i18n: "Rastrear desde" (es) / "Track since" (en).

#### Scenario: Usuario activa tracking al crear cuenta

- GIVEN el formulario de nueva cuenta con opening date `2026-01-01`
- WHEN el usuario elige `trackedSince = 2026-04-15` y guarda
- THEN la cuenta se persiste con ambas fechas correctas

#### Scenario: Campo vacío resulta en NULL

- GIVEN el formulario de nueva cuenta
- WHEN el usuario deja vacío el campo "Rastrear desde"
- THEN la cuenta se persiste con `trackedSince = NULL`

---

### Requirement: Edición retroactiva de `trackedSince` con confirmación

Al cambiar `trackedSince` en una cuenta existente con transacciones, al pulsar Guardar el sistema MUST mostrar un diálogo con preview "Balance actual: X → Balance nuevo: Y". Si `Y < 0` OR `|X - Y| > 0.5 * |X|`, MUST requerir confirmación extra tipeando "CONFIRMAR". Si el usuario cancela, `trackedSince` MUST NOT modificarse. El sistema MUST NOT bloquear el cambio por completo.

#### Scenario: Diferencia menor al 50% solo advierte

- GIVEN cuenta con balance actual 1000 Bs
- WHEN el usuario cambia `trackedSince` de forma que el nuevo balance sería 800 Bs
- THEN el diálogo muestra el preview y basta con pulsar "Aceptar"

#### Scenario: Balance quedaría negativo requiere CONFIRMAR

- GIVEN cuenta con balance actual 100 Bs
- WHEN el usuario cambia `trackedSince` de forma que el nuevo balance sería -200 Bs
- THEN el diálogo exige tipear "CONFIRMAR" para proceder
- AND si el texto no coincide el guardado se cancela

---

### Requirement: Migración v24 retrocompatible

La migración Drift `v24.sql` MUST añadir columna `trackedSince DATETIME` nullable a la tabla `accounts`. `schemaVersion` MUST pasar de 23 a 24. Tras aplicar la migración, el balance de toda cuenta existente MUST ser idéntico al que tenía antes de migrar.

#### Scenario: Migración limpia

- GIVEN una base de datos en schema v23 con 5 cuentas existentes
- WHEN la app arranca y aplica v24
- THEN todas las cuentas quedan con `trackedSince = NULL`
- AND sus balances no cambian

#### Scenario: Validación defensiva de trackedSince vs closingDate

- GIVEN una cuenta con `closingDate = 2026-03-01`
- WHEN el usuario intenta establecer `trackedSince = 2026-04-01`
- THEN el formulario rechaza la entrada con mensaje de validación
