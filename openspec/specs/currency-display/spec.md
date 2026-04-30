# Spec: Currency Display Policy

## Purpose

Define el contrato del nuevo dominio `CurrencyDisplayPolicy` — la abstracción
sealed que reemplaza el render hardcoded "USD primary + Bs equivalence" en
el dashboard. Cubre la resolución del policy desde settings, el contrato de
render para widgets de totales, la independencia multi-moneda de cuentas y
transacciones frente al modo, y la gating del chip BCV/Paralelo.

---

## Requirements

### Requirement: Modelo `CurrencyDisplayPolicy`

El sistema MUST exponer una clase sealed `CurrencyDisplayPolicy` con dos
variantes:

- `CurrencyDisplayPolicy.single({ required String code })`
- `CurrencyDisplayPolicy.dual({ required String primary, required String secondary })`

Un servicio resolver MUST exponer un `Stream<CurrencyDisplayPolicy>` que
combine `SettingKey.currencyMode`, `SettingKey.preferredCurrency` y
`SettingKey.secondaryCurrency` y emita una nueva política cada vez que
cualquiera cambie. La emisión MUST ser idempotente (no emitir si la política
es idéntica a la anterior).

#### Scenario: Resolución de modos `single_*`

- GIVEN `currencyMode='single_usd'`, `preferredCurrency='USD'`
- WHEN un consumidor se suscribe al stream
- THEN MUST recibir `CurrencyDisplayPolicy.single(code: 'USD')`

#### Scenario: Resolución de modo `dual`

- GIVEN `currencyMode='dual'`, `preferredCurrency='USD'`, `secondaryCurrency='VES'`
- WHEN un consumidor se suscribe
- THEN MUST recibir `CurrencyDisplayPolicy.dual(primary: 'USD', secondary: 'VES')`

#### Scenario: Cambio de modo emite nueva política

- GIVEN un suscriptor activo con política `single(USD)`
- WHEN el usuario cambia el modo a `dual` con `USD+VES`
- THEN el stream MUST emitir `dual(USD, VES)` en menos de 200ms

---

### Requirement: Render de totales en modo `single_*`

Los widgets de totales (`TotalBalanceSummaryWidget`, `IncomeOrExpenseCard`,
`AllAccountsBalance`, `FundEvolutionInfo`, `TransactionFilterSet`) MUST
renderizar UNA SOLA línea con el monto convertido a la moneda del policy
cuando `policy is CurrencyDisplayPolicy.single`.

NO MUST renderizarse:
- línea de equivalencia secundaria;
- chip "BCV/Paralelo" / `RateSourceTooltip`;
- cualquier glyph "≈" o "=" implicando equivalencia.

#### Scenario: Saldo total en `single_bs`

- GIVEN policy `single(VES)` y cuentas en USD, EUR y VES
- WHEN `TotalBalanceSummaryWidget` renderiza
- THEN MUST mostrar UNA línea con la suma convertida a VES
- AND NO MUST haber línea secundaria ni chip

#### Scenario: Gasto/Ingreso en `single_other` (EUR)

- GIVEN policy `single(EUR)` y transacciones del mes en USD y VES
- WHEN `IncomeOrExpenseCard` renderiza
- THEN MUST mostrar UNA línea en EUR
- AND NO MUST haber línea secundaria

---

### Requirement: Render de totales en modo `dual`

Cuando `policy is CurrencyDisplayPolicy.dual`, los widgets de totales MUST
renderizar DOS líneas:

- línea principal: monto en `policy.primary`;
- línea secundaria (visualmente subordinada): monto equivalente en
  `policy.secondary`.

El orden visual MUST ser principal arriba, secundaria abajo.

#### Scenario: Dual USD+VES con cuentas mixtas

- GIVEN policy `dual(USD, VES)` y cuentas en USD, EUR y VES
- WHEN `TotalBalanceSummaryWidget` renderiza
- THEN MUST mostrar línea principal en USD y línea secundaria en VES
- AND el chip BCV/Paralelo MUST aparecer (ver requirement de chip)

#### Scenario: Dual EUR+ARS

- GIVEN policy `dual(EUR, ARS)`
- WHEN se renderiza
- THEN MUST mostrar línea principal en EUR y secundaria en ARS
- AND el chip BCV/Paralelo NO MUST aparecer

---

### Requirement: Cómputo de totales mixtos

Cuando se agrega una colección de montos en distintas monedas para mostrar
en una moneda objetivo `display`, el cómputo MUST seguir esta regla:

```
total_display = Σ (monto_nativo_i si moneda_i == display)
              + Σ (monto_nativo_j × rate(moneda_j → display)) si moneda_j != display
```

La porción nativa (montos cuya moneda ya es la `display`) MUST NEVER
multiplicarse por una tasa. En particular, esta porción MUST permanecer
estable cuando el usuario cambia entre BCV y Paralelo en el chip — solo la
porción foránea MUST recomputar.

(Esto corrige el bug actual en `select-full-data.drift::countTransactions`
donde toda fila se multiplica por la tasa activa.)

#### Scenario: Toggle BCV ↔ Paralelo no altera porción nativa

- GIVEN policy `dual(USD, VES)`, una cuenta USD con saldo 100 USD,
  una cuenta VES con saldo 1000 VES, BCV=40, Paralelo=45
- WHEN el usuario toggles desde BCV a Paralelo
- THEN la línea principal (USD) MUST permanecer en `100 + 1000/45 ≈ 122.22 USD`
  pasando de `100 + 1000/40 = 125.00 USD` (cambia SOLO la porción VES→USD)
- AND la porción nativa USD (= 100) MUST permanecer constante

#### Scenario: Tasa faltante para par foráneo

- GIVEN policy `single(EUR)` y una transacción en JPY sin tasa configurada
- WHEN el widget agrega el total
- THEN la transacción JPY MUST excluirse del total Y mostrarse un indicador
  inline "tasa no configurada" (o similar)
- AND NO MUST asumirse `1.0` silenciosamente

---

### Requirement: Chip BCV/Paralelo gated a USD+VES

El chip / tooltip de fuente de tasa (`RateSourceTooltip`) MUST aparecer
EXCLUSIVAMENTE cuando todas estas condiciones se cumplen:

1. `policy is CurrencyDisplayPolicy.dual`;
2. el par (`primary`, `secondary`) es exactamente `(USD, VES)` o
   `(VES, USD)`.

En CUALQUIER otro caso, el chip MUST NOT renderizarse y el toggle MUST NOT
estar accesible. Cuando el chip se muestra, MUST poder toggle entre `'bcv'`
y `'paralelo'` y persistir la elección en `SettingKey.preferredRateSource`.

El estado `_rateSource` del dashboard MUST derivarse del policy stream (no
cachearse en `initState`), de modo que al cambiar de modo en Settings el
chip aparezca/desaparezca sin reload.

#### Scenario: Modo `single_bs` — chip ausente

- GIVEN policy `single(VES)`
- WHEN el dashboard renderiza
- THEN ningún widget MUST mostrar el chip BCV/Paralelo

#### Scenario: Modo `dual` con `EUR+ARS` — chip ausente

- GIVEN policy `dual(EUR, ARS)`
- WHEN el dashboard renderiza
- THEN ningún widget MUST mostrar el chip BCV/Paralelo
- AND la conversión EUR↔ARS MUST usar UNA SOLA tasa (la activa para ese par)

#### Scenario: Modo `dual` con `VES+USD` (orden invertido) — chip presente

- GIVEN policy `dual(VES, USD)`
- WHEN el dashboard renderiza
- THEN el chip BCV/Paralelo MUST aparecer (orden no afecta la condición)

#### Scenario: Cambio de modo en Settings actualiza visibilidad del chip

- GIVEN dashboard montado con policy `dual(USD, VES)` (chip visible)
- WHEN el usuario cambia el modo a `single_usd` desde Settings
- THEN el chip MUST desaparecer en el siguiente frame
- AND NO MUST requerir reiniciar la app o cambiar de pantalla

---

### Requirement: Independencia multi-moneda de cuentas

Las cuentas MUST ser creables en cualquiera de las 151 monedas del catálogo
INDEPENDIENTEMENTE del `currencyMode`. El cambio de modo MUST NOT:

- ocultar cuentas existentes;
- bloquear la creación de cuentas en monedas distintas a las del policy;
- auto-convertir el `currencyId` ni el saldo de ninguna cuenta;
- afectar `transactions.currencyId` (heredado del account) ni
  `transactions.exchangeRateApplied` (capturado al registrar).

#### Scenario: Crear cuenta JPY con policy `single(USD)`

- GIVEN policy `single(USD)`
- WHEN el usuario crea una cuenta nueva en `JPY`
- THEN la creación MUST permitirse sin advertencia ni bloqueo
- AND la cuenta MUST aparecer en la lista con su currencyId real (`JPY`)

#### Scenario: Cambio de modo no convierte cuentas

- GIVEN un usuario con cuentas en `USD`, `EUR`, `VES`, `JPY` y policy `dual(USD, VES)`
- WHEN cambia a `single_bs`
- THEN cada cuenta MUST conservar exactamente su `currencyId` y `iniValue`
- AND ninguna fila de `accounts` MUST modificarse

---

## Out of Scope

- Triple-display o watch-face (la sealed admite extensión vía nuevas variantes,
  pero NO se construye en este change).
- Conversión retroactiva de transacciones al cambiar modo o tasa.
- UI de edición masiva de moneda de cuenta.
- Conversión de saldos entre cuentas al cambiar modo.
