# Delta: Currency Mode settings

Cubre las nuevas claves `currencyMode` y `secondaryCurrency` en `userSettings`, su
migración heurística para los 3 betas, su entrada para edición post-onboarding y su
inclusión en sincronización Firebase.

---

## ADDED Requirements

### Requirement: SettingKey `currencyMode`

El sistema MUST exponer `SettingKey.currencyMode` persistida como TEXT en
`userSettings`. Los valores válidos MUST ser exactamente uno de:
`'single_usd'`, `'single_bs'`, `'single_other'`, `'dual'`. El valor por defecto
para instalaciones nuevas MUST ser `'dual'`. Cualquier lector MUST tratar `null`
o un valor desconocido como `'dual'` (compat forward).

#### Scenario: Lectura en instalación nueva sin onboarding completo

- GIVEN un dispositivo recién instalado sin fila `currencyMode`
- WHEN un widget pregunta por el modo
- THEN el resolver MUST retornar `'dual'` por defecto

#### Scenario: Valor desconocido (versión futura → downgrade)

- GIVEN `userSettings.currencyMode = 'triple'` (escrito por una versión futura)
- WHEN la app actual lee la clave
- THEN MUST tratarse como `'dual'`
- AND el usuario MUST poder corregirlo desde Settings

---

### Requirement: SettingKey `secondaryCurrency`

El sistema MUST exponer `SettingKey.secondaryCurrency` persistida como TEXT
nullable en `userSettings`. Solo es semánticamente relevante cuando
`currencyMode == 'dual'`. En modos `single_*` la clave SHOULD permanecer escrita
(no se borra) — preserva la última pareja para el caso de que el usuario vuelva
a `dual` sin reconfigurar. Los lectores MUST ignorar `secondaryCurrency` cuando
el modo no es `dual`.

#### Scenario: Cambio de `dual` a `single_usd` preserva valor

- GIVEN `currencyMode='dual'`, `secondaryCurrency='VES'`
- WHEN el usuario cambia el modo a `single_usd` desde Settings
- THEN `secondaryCurrency` MUST permanecer en `'VES'` en disco
- AND ningún widget MUST renderizar la línea secundaria

#### Scenario: Re-entrada a modo `dual` con secundaria preservada

- GIVEN un usuario que estuvo en `dual` con `'VES'`, luego pasó a `single_usd`
- WHEN vuelve a seleccionar `dual` sin elegir explícitamente la secundaria
- THEN el sistema MUST proponer `'VES'` como pareja por defecto

---

### Requirement: Cambio de modo post-onboarding desde Settings

`currency_manager.dart` MUST exponer un selector de modo (4 opciones) y, si
`currencyMode='dual'`, un selector de moneda secundaria desde el catálogo
completo de 151 monedas. El cambio MUST persistirse vía `UserSettingService`
y propagarse vía el stream del display policy en menos de un frame perceptible
(< 200ms).

El cambio de modo MUST NOT:
- modificar, ocultar ni convertir cuentas existentes;
- recalcular ninguna transacción histórica;
- borrar filas de `exchangeRates`;
- afectar el `transactions.exchangeRateApplied` ya capturado.

#### Scenario: Switch `dual` → `single_bs` con cuentas USD preexistentes

- GIVEN un usuario con cuentas en USD, EUR y VES y modo `dual`
- WHEN cambia a `single_bs` desde Settings
- THEN las 3 cuentas MUST seguir existiendo y editables
- AND el dashboard MUST renderizar totales en una sola línea (VES)
- AND ninguna fila en `transactions` MUST modificarse

#### Scenario: Switch `single_other` con moneda fuera de USD/VES

- GIVEN un usuario en `single_usd`
- WHEN selecciona `single_other` y elige `EUR`
- THEN `currencyMode='single_other'`, `preferredCurrency='EUR'`
- AND el dashboard renderiza una línea en EUR
- AND el chip BCV/Paralelo NO aparece en ningún widget

---

### Requirement: Migración heurística para usuarios existentes

En el primer cold-start del nuevo build, el sistema MUST ejecutar un seed
idempotente: si `userSettings` no contiene `currencyMode`, calcula el valor
inicial así:

| Condición | `currencyMode` | `secondaryCurrency` |
|-----------|----------------|---------------------|
| `preferredRateSource` existe (cualquier valor) | `'dual'` | `'VES'` |
| `preferredCurrency='USD'` y SIN `preferredRateSource` | `'single_usd'` | `null` |
| `preferredCurrency='VES'` y SIN `preferredRateSource` | `'single_bs'` | `null` |
| Otro `preferredCurrency` | `'single_other'` | `null` |
| Sin ninguna clave | `'dual'` | `'VES'` |

La migración MUST ser idempotente (re-ejecutarla no modifica nada). El rollback
MUST ser posible vía `DELETE FROM userSettings WHERE settingKey IN ('currencyMode','secondaryCurrency')`.

#### Scenario: Beta con preferredRateSource='paralelo'

- GIVEN un usuario beta con `preferredCurrency='USD'`, `preferredRateSource='paralelo'`
- WHEN se ejecuta la migración
- THEN se escribe `currencyMode='dual'`, `secondaryCurrency='VES'`

#### Scenario: Idempotencia

- GIVEN un usuario ya migrado con `currencyMode='dual'`
- WHEN se ejecuta la migración nuevamente (re-cold-start)
- THEN ninguna fila de `userSettings` MUST modificarse

---

### Requirement: Sincronización Firebase

`SettingKey.currencyMode` y `SettingKey.secondaryCurrency` MUST sincronizarse
vía `firebase_sync_service` (NO MUST estar en `_userSettingsSyncExclusions`).
Durante un rollout mixto, el código nuevo MUST tolerar la ausencia de estas
claves en blobs escritos por versiones antiguas (cae al default `'dual'`).
Una escritura de un cliente antiguo (que no incluye estas claves) MUST NOT
borrar las claves de un cliente nuevo si el merge es campo-a-campo; si el
servicio escribe el blob completo, el riesgo MUST documentarse y el cliente
nuevo MUST re-escribir las claves al detectar su ausencia.

#### Scenario: Round-trip multi-dispositivo

- GIVEN dispositivo A en versión nueva con `currencyMode='single_bs'`
- WHEN el blob se sube a Firebase
- AND dispositivo B en versión nueva hace pull
- THEN B MUST mostrar `currencyMode='single_bs'` y aplicar la política

#### Scenario: Cliente antiguo sin las claves

- GIVEN dispositivo A en versión nueva escribió `currencyMode='dual'`
- AND dispositivo B en versión antigua sube un blob sin las claves
- WHEN dispositivo A hace pull
- THEN A MUST detectar la ausencia y restaurar sus claves locales
- AND el modo del usuario MUST preservarse
