# Delta: Exchange rate sources and fallback

Cubre la generalización de fuentes de tasa más allá de BCV/Paralelo: nueva
fuente automática vía Frankfurter para fiat-fiat, fuente manual para overrides
del usuario y crypto, normalización del enum `source` a minúsculas, y la
corrección del fallback silencioso `1.0` en `calculateExchangeRate`.

---

## ADDED Requirements

### Requirement: Enum `source` normalizado en lowercase

El campo `exchangeRates.source` (TEXT NULL existente) MUST aceptar exactamente
estos valores en lowercase:

| Valor | Significado |
|-------|-------------|
| `'bcv'` | Banco Central de Venezuela (USD↔VES) — vía `DolarApiProvider` |
| `'paralelo'` | Tasa paralela (USD↔VES) — vía `DolarApiProvider` |
| `'auto_frankfurter'` | Tasa fiat-fiat automática vía frankfurter.app |
| `'manual'` | Override manual del usuario o crypto sin auto-source |

Toda escritura a `exchangeRates` MUST usar uno de estos valores. Lecturas
MUST tolerar valores legacy (`null`, mayúsculas) — un valor desconocido
MUST tratarse como `'manual'` para no perder la fila.

#### Scenario: Escritura de tasa BCV

- GIVEN `DolarApiProvider` retorna la tasa USD→VES del BCV
- WHEN el rate refresh service escribe la fila
- THEN `source='bcv'` (lowercase exacto)

#### Scenario: Lectura de fila con source legacy

- GIVEN una fila preexistente con `source='BCV'` (mayúsculas, instalación vieja)
- WHEN `_getRateWithFallback` la lee
- THEN MUST tratarla como equivalente a `'bcv'` (case-insensitive en lectura)
- O bien la migración de normalización MUST haberla actualizado

---

### Requirement: Frankfurter como fuente automática para fiat-fiat

El sistema MUST exponer un nuevo `FrankfurterProvider` que consulte
`frankfurter.app` para pares fiat-fiat soportados. El provider MUST:

- llamarse SOLO cuando el par lo amerite (no es USD/VES y ambos son fiat
  cubiertos por la API);
- escribir la tasa con `source='auto_frankfurter'`;
- caer a `'manual'` si:
  - (a) hay fallo de red (timeout, 5xx, sin conexión),
  - (b) la API no soporta una de las dos monedas,
  - (c) la respuesta es stale (>24h del último update reportado por la API).

Cada uno de los tres fallbacks MUST surfacearse al usuario con un mensaje
distinto en la UI (no fallback silencioso).

#### Scenario: Par EUR↔GBP exitoso

- GIVEN policy `dual(EUR, GBP)` y red disponible
- WHEN el rate refresh service corre
- THEN MUST llamar a Frankfurter para `EUR→GBP` y `GBP→EUR`
- AND MUST escribir filas con `source='auto_frankfurter'`

#### Scenario: Falla de red — fallback a manual

- GIVEN policy `dual(EUR, GBP)` y red caída
- WHEN el rate refresh service intenta refrescar
- THEN MUST capturar la excepción
- AND NO MUST escribir una fila nueva
- AND la UI MUST exponer banner "tasa automática no disponible — configura manual"
  hasta que el usuario actúe o se restaure la conexión

#### Scenario: Moneda no soportada por Frankfurter

- GIVEN policy `dual(USD, ARS)` (ARS no cubierto por la API)
- WHEN el rate refresh service evalúa el par
- THEN MUST NOT llamar a Frankfurter
- AND MUST exponer al usuario la opción de configurar tasa manual para ese par

#### Scenario: Datos stale

- GIVEN Frankfurter retorna un timestamp > 24h
- WHEN el provider procesa la respuesta
- THEN MUST NOT considerar la tasa válida para escritura
- AND MUST surface "tasa desactualizada" para que el usuario decida (manual o esperar)

---

### Requirement: Manual override per-par

El usuario MUST poder forzar `source='manual'` para cualquier par desde el
manager de monedas. Cuando hay un override manual activo:

- el rate refresh service MUST NOT sobreescribir la fila manual con una
  fuente automática;
- la fila manual MUST tener prioridad en `_getRateWithFallback` por encima
  de cualquier fuente automática para el mismo `(currencyCode, date)`.

Pares cripto (BTC, ETH, USDT y cualquier `currencyId` marcado como crypto)
MUST tener `source='manual'` por defecto. El sistema NO MUST llamar a
ninguna API automática para estos pares.

#### Scenario: Override manual sobreescribe automática

- GIVEN una fila `auto_frankfurter` para EUR→GBP
- WHEN el usuario configura una tasa manual para EUR→GBP
- THEN la fila MUST escribirse con `source='manual'`
- AND `_getRateWithFallback('EUR', today)` MUST retornar la fila `manual`
- AND el rate refresh subsiguiente MUST NOT pisar la fila manual

#### Scenario: BTC default manual

- GIVEN policy `dual(USD, BTC)`
- WHEN el rate refresh service evalúa el par
- THEN MUST NOT invocar Frankfurter ni cualquier API
- AND la única vía de obtener tasa BTC↔USD MUST ser entrada manual

---

## MODIFIED Requirements

### Requirement: Fallback de `calculateExchangeRate`

(Previously: `calculateExchangeRate` retornaba silenciosamente `1.0` cuando
no había tasa para un par no-identidad. Esto producía totales incorrectos
sin alerta visible.)

`calculateExchangeRate(from, to, date)` MUST seguir esta regla:

| Caso | Retorno |
|------|---------|
| `from == to` | `1.0` |
| Existe fila para `(to, date)` con cualquier `source` válida | tasa concreta |
| Existe fila reciente (≤ 7 días) | tasa concreta + flag `stale` |
| No hay fila aplicable | `null` (o sentinela `RateUnavailable`) |

NO MUST retornarse `1.0` para pares distintos sin tasa. Los consumidores
MUST manejar el `null` / sentinel: excluir el monto del total y propagar
una señal "tasa no configurada" hacia la UI.

El comportamiento previo (`1.0` silencioso) MUST eliminarse incluso para
modos `single_*` — la corrección aplica universalmente.

#### Scenario: Identidad USD→USD

- GIVEN `from='USD'`, `to='USD'`
- WHEN se invoca `calculateExchangeRate`
- THEN retorna `1.0` (sin consulta a DB)

#### Scenario: Tasa concreta disponible hoy

- GIVEN `from='USD'`, `to='VES'`, fila BCV de hoy = 40
- WHEN se invoca `calculateExchangeRate`
- THEN retorna `40.0`

#### Scenario: Sin tasa configurada — null

- GIVEN `from='USD'`, `to='JPY'` y NO hay fila para `JPY`
- WHEN se invoca
- THEN MUST retornar `null` (NO `1.0`)
- AND el caller MUST surface "tasa no configurada"

#### Scenario: Tasa stale (3 días vieja)

- GIVEN la última fila para `EUR` es de hace 3 días
- WHEN se invoca con `date=today`
- THEN MUST retornar la tasa con flag `stale=true`
- AND la UI MUST mostrar indicador stale (sin bloquear el cómputo)

---

### Requirement: Rate refresh service multi-fuente

(Previously: hardcoded a `['bcv', 'paralelo']` para USD y EUR.)

`RateRefreshService` MUST derivar dinámicamente la lista de pares y fuentes
del policy actual:

- modo `single_*` con moneda == display: ninguna refresh necesaria;
- modo `single_*` con cuentas en otras monedas: refresh `auto_frankfurter`
  o `manual` para esos pares;
- modo `dual(USD, VES)` o `dual(VES, USD)`: refresh `bcv` Y `paralelo` para
  ese par; otras monedas vía `auto_frankfurter`/`manual`;
- modo `dual` otro par: refresh `auto_frankfurter` para ese par + cuentas
  no-display.

#### Scenario: Modo dual USD+VES con cuenta EUR

- GIVEN policy `dual(USD, VES)` y una cuenta en `EUR`
- WHEN `RateRefreshService.refresh()` corre
- THEN MUST refrescar BCV y Paralelo para USD↔VES (vía `DolarApiProvider`)
- AND MUST refrescar EUR↔USD vía `auto_frankfurter`
- AND MUST escribir 3 filas distinguidas por `source`

#### Scenario: Modo single_usd con cuentas USD only

- GIVEN policy `single(USD)`, todas las cuentas en USD
- WHEN `RateRefreshService.refresh()` corre
- THEN NO MUST llamar a ninguna API de tasas (no hay pares pendientes)
