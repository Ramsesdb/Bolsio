# Delta: Transactions — rate history y agregación por moneda nativa

Cubre la fijación inmutable del `exchangeRateApplied` por transacción y el
fix del bug de agregación que multiplica toda fila por la tasa activa al
toggle BCV/Paralelo.

---

## ADDED Requirements

### Requirement: `exchangeRateApplied` inmutable por transacción

Cada fila en `transactions` MUST capturar `exchangeRateApplied` (DOUBLE
nullable) en el momento de registro, usando la tasa vigente al `date` y al
`policy` activos. Esta captura MUST ser FINAL para la vida útil de la
transacción.

Las siguientes operaciones MUST NOT recalcular `exchangeRateApplied` de
filas existentes:

- cambio de `currencyMode` desde Settings;
- toggle BCV ↔ Paralelo;
- override manual de tasa (afecta solo escrituras posteriores);
- cualquier refresh de `exchangeRates`.

La edición manual del `exchangeRateApplied` de una transacción específica
MAY permitirse desde el editor de transacciones, pero MUST quedar fuera
del scope de este change (no se cambia su comportamiento actual).

#### Scenario: Toggle BCV→Paralelo no recalcula histórico

- GIVEN una transacción registrada hace 1 mes con `exchangeRateApplied=39.50`
  (tasa BCV de ese día)
- WHEN el usuario toggles del chip a Paralelo en el dashboard
- THEN la fila de la transacción MUST permanecer con `exchangeRateApplied=39.50`
- AND ninguna escritura a `transactions` MUST ocurrir como efecto del toggle

#### Scenario: Cambio de modo no recalcula histórico

- GIVEN un usuario cambia de `dual(USD, VES)` a `single_bs`
- WHEN la migración de modo corre
- THEN ninguna fila en `transactions` MUST modificarse
- AND `exchangeRateApplied` MUST quedar tal como estaba

---

### Requirement: Agregación por moneda nativa

Las queries que computan totales para la UI (`countTransactions` en
`select-full-data.drift`, métodos en `TransactionService` y los streams
consumidos por `TotalBalanceSummaryWidget` / `IncomeOrExpenseCard`) MUST
adoptar este patrón:

1. Agrupar transacciones (o sus saldos) por `currencyId` nativo.
2. Sumar dentro de cada grupo en la moneda nativa.
3. Convertir SOLO los grupos cuya moneda no coincide con la `display`
   actual, usando `ExchangeRateService.calculateExchangeRate(native, display, today)`.
4. Sumar las contribuciones convertidas + la porción nativa.

La query Drift MUST EXPONER, como mínimo, una proyección
`(currencyId, sumValue)` para que la conversión se haga en Dart sobre
`ExchangeRateService` (en lugar de embeber la conversión en SQL con un CTE
sesgado por `:rateSource`).

La rama existente del CTE
`WHEN a.currencyId = :preferredCurrency THEN 1.0` MUST eliminarse (queda
implícita y correcta tras la nueva agregación). Toda multiplicación
indiscriminada `t.value * latestRates.rate` para filas en moneda nativa
== display MUST eliminarse.

#### Scenario: Toggle BCV→Paralelo NO altera porción nativa USD

- GIVEN policy `dual(USD, VES)`, una cuenta USD con balance 100 USD,
  una cuenta VES con balance 1000 VES, BCV=40, Paralelo=45
- WHEN el dashboard toggles a Paralelo
- THEN la línea principal MUST recomputar SOLO la conversión VES→USD
  (1000/45 ≈ 22.22)
- AND la suma final MUST ser `100 + 22.22 = 122.22 USD`
  (NO `(100 + 1000)/45 = 24.44 USD`, que es el bug actual)

#### Scenario: Modo single_bs con cuentas USD

- GIVEN policy `single(VES)`, una cuenta USD con balance 50 USD,
  una cuenta VES con balance 500 VES, tasa BCV=40
- WHEN `TotalBalanceSummaryWidget` agrega
- THEN MUST agrupar: `{USD: 50, VES: 500}`
- AND convertir SOLO la porción USD: `50 × 40 = 2000 VES`
- AND el total MUST ser `2000 + 500 = 2500 VES`

#### Scenario: Tasa faltante para un grupo

- GIVEN policy `single(EUR)` y una cuenta JPY con balance 1000 JPY
  donde `calculateExchangeRate('JPY', 'EUR', today)` retorna `null`
- WHEN se agrega el total
- THEN el grupo JPY MUST excluirse del total numérico
- AND la UI MUST exponer un indicador "1 moneda sin tasa" o similar
- AND el resto de monedas MUST sumarse normalmente

---

## MODIFIED Requirements

### Requirement: Currency de transacciones heredada del account

(Previously: implícito en código pero no especificado.)

La moneda de cada transacción MUST heredarse de su `account.currencyId` en
el momento del registro. La UI NO MUST permitir registrar una transacción
en una moneda distinta a la de su cuenta. El cambio de `currencyMode` MUST
NOT alterar `transactions.currencyId` (heredado, fijo).

#### Scenario: Transacción en cuenta JPY con policy single(EUR)

- GIVEN policy `single(EUR)` y una cuenta `JPY`
- WHEN el usuario registra una transacción de 5000 JPY en esa cuenta
- THEN la fila MUST tener `currencyId='JPY'` (heredado)
- AND el monto nativo `value=5000` MUST registrarse sin conversión
- AND `exchangeRateApplied` MUST capturar la tasa JPY→EUR vigente
  (o `null` si no había tasa configurada)
