# Delta: Currency Modes en onboarding

Cubre el rework del slide 2 (selección de moneda) a un selector de 4 modos, el
gating del slide 3 (fuente de tasa) y la persistencia de los nuevos campos
`currencyMode` y `secondaryCurrency`.

---

## MODIFIED Requirements

### Requirement: Selección de moneda preferida (slide 2)

(Previously: presentaba 3 opciones `USD | VES | DUAL`, donde `DUAL` se
colapsaba a `USD` antes de persistir, perdiendo la distinción.)

El slide MUST presentar exactamente 4 opciones en este orden:
`single_usd`, `single_bs`, `single_other`, `dual`. Solo una puede estar
activa a la vez. El default MUST derivarse de
`CurrencyService.getDeviceDefaultCurrencyCode()`:

| Default del dispositivo | Modo seleccionado por defecto |
|------------------------|-------------------------------|
| `USD` | `single_usd` |
| `VES` | `single_bs` |
| Otro | `single_other` con esa moneda |

Al seleccionar `single_other`, MUST abrirse `CurrencySelectorModal` (catálogo
completo de 151 monedas). Al seleccionar `dual`, MUST abrirse un sub-selector
con dos campos: moneda principal (default `USD`) y moneda secundaria
(default `VES`); ambos MUST permitir cualquier moneda del catálogo.

Al avanzar, el controller MUST persistir, vía `UserSettingService`:
- `SettingKey.currencyMode` con el modo seleccionado;
- `SettingKey.preferredCurrency` con la moneda principal del modo;
- `SettingKey.secondaryCurrency` con la secundaria (solo si modo es `dual`,
  si no, MAY escribirse `null` o no escribirse).

El colapso `'DUAL' → 'USD'` MUST eliminarse del código de persistencia.

#### Scenario: Selección `single_usd`

- GIVEN el usuario selecciona `single_usd`
- WHEN presiona "Siguiente"
- THEN `currencyMode='single_usd'`, `preferredCurrency='USD'`
- AND `secondaryCurrency` se escribe como `null` o se omite
- AND el slide 3 (fuente de tasa) NO MUST mostrarse

#### Scenario: Selección `single_other` con `EUR`

- GIVEN el usuario selecciona `single_other` y elige `EUR` en el modal
- WHEN presiona "Siguiente"
- THEN `currencyMode='single_other'`, `preferredCurrency='EUR'`
- AND el slide 3 NO MUST mostrarse

#### Scenario: Selección `dual` con default USD+VES

- GIVEN el usuario selecciona `dual` sin modificar las monedas sugeridas
- WHEN presiona "Siguiente"
- THEN `currencyMode='dual'`, `preferredCurrency='USD'`, `secondaryCurrency='VES'`
- AND el slide 3 (fuente de tasa) MUST mostrarse

#### Scenario: Selección `dual` con par no-USD/VES

- GIVEN el usuario selecciona `dual` y configura par `EUR + ARS`
- WHEN presiona "Siguiente"
- THEN `currencyMode='dual'`, `preferredCurrency='EUR'`, `secondaryCurrency='ARS'`
- AND el slide 3 NO MUST mostrarse (no aplica a pares no-USD/VES)

---

### Requirement: Gating del slide 3 (fuente de tasa)

(Previously: el slide se mostraba siempre, independientemente de la moneda
seleccionada en slide 2.)

El slide 3 MUST mostrarse SOLO cuando `currencyMode='dual'` AND el par es
exactamente `(USD, VES)` (en cualquier orden de principal/secundaria). En
todos los otros modos/pares, el controller MUST saltar directamente al
siguiente slide del flujo.

La lista de slides MUST recalcularse de forma reactiva cuando el usuario
vuelve atrás y modifica el modo en slide 2.

#### Scenario: `single_usd` salta el slide 3

- GIVEN modo seleccionado `single_usd` en slide 2
- WHEN el usuario presiona "Siguiente"
- THEN el flujo MUST avanzar al slide siguiente (slide 4) sin pasar por slide 3
- AND `preferredRateSource` NO MUST escribirse

#### Scenario: `dual` con USD+VES muestra slide 3

- GIVEN modo seleccionado `dual` con principal `USD`, secundaria `VES`
- WHEN el usuario presiona "Siguiente" en slide 2
- THEN el slide 3 MUST renderizarse
- AND el usuario MUST poder elegir `bcv` o `paralelo`

#### Scenario: `dual` con par no-USD/VES salta el slide 3

- GIVEN modo `dual` con principal `EUR`, secundaria `ARS`
- WHEN el usuario presiona "Siguiente" en slide 2
- THEN el flujo MUST avanzar al slide siguiente sin pasar por slide 3
- AND `preferredRateSource` NO MUST escribirse para este par

#### Scenario: Volver atrás y cambiar de `dual` a `single_usd`

- GIVEN el usuario llegó al slide 3 con modo `dual` USD+VES
- AND vuelve atrás al slide 2 y selecciona `single_usd`
- WHEN avanza nuevamente
- THEN el slide 3 NO MUST mostrarse
- AND el orden y total de slides reflejan el nuevo modo
