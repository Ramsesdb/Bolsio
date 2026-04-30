# Delta: Restricted Settings Onboarding Step

Cubre la inserción condicional de un paso "permitir configuración restringida"
en los dos hosts que llevan al permiso de notification listener
(`OnboardingPage` y `ReturningUserFlow`), reutilizando un widget compartido
`v3_restricted_settings_step.dart`. Solo agrega comportamiento; no modifica
slides existentes.

---

## ADDED Requirements

### Requirement: Detección del gate de configuración restringida

El sistema MUST consultar el AppOp `android:access_restricted_settings` vía
`DeviceQuirksService.isRestrictedSettingsAllowed()` durante `initState` de
cada host. La consulta MUST usar `AppOpsManager.unsafeCheckOpNoThrow` envuelto
en `try/catch` con política fail-open: cualquier excepción MUST retornar
`true` (= permitido = no se inserta paso). En Android < 13 o cuando el AppOp
reporta `allow`/`default`, el método MUST retornar `true`. Solo cuando el
AppOp reporta `ignore` o `error` MUST retornar `false`.

#### Scenario: Detección positiva en sideload Android 13+

- GIVEN el dispositivo es Android 13+ con instalación sideload
- AND el AppOp `android:access_restricted_settings` reporta `ignore`
- WHEN el host (cualquiera de los dos) evalúa `isRestrictedSettingsAllowed()`
- THEN el método retorna `false`
- AND el host marca `_restrictedSettingsBlocked = true`

#### Scenario: Detección negativa — Play Store o pre-13

- GIVEN el AppOp reporta `allow` o el SDK es < 33
- WHEN el host evalúa la detección
- THEN retorna `true`
- AND el paso NO se inserta en la lista de slides/steps

#### Scenario: Excepción en AppOps — fail-open

- GIVEN `AppOpsManager.unsafeCheckOpNoThrow` lanza excepción (firmware drift)
- WHEN el host evalúa la detección
- THEN la excepción se captura y el método retorna `true`
- AND el paso NO se inserta (el usuario procede al paso de listener estándar)

---

### Requirement: Inserción condicional en `OnboardingPage`

`OnboardingPage._buildSlides()` MUST insertar el slide
`s075_restricted_settings` entre `s07_post_notifications` y
`s08_activate_listener` solo cuando `_restrictedSettingsBlocked == true`.
Cuando es `false`, la lista de slides MUST mantenerse idéntica al onboarding
v2 actual (longitud y orden invariables). El slide MUST renderizar el widget
compartido `V3RestrictedSettingsStep` con `showBackPill: true` y wrapped en
el `V3SlideTemplate` estándar (con barra de progreso del host).

#### Scenario: Sideload Android 13+ — slide insertado

- GIVEN `_restrictedSettingsBlocked = true`
- WHEN `_buildSlides()` se ejecuta
- THEN la lista incluye `s075_restricted_settings` entre s07 y s08
- AND la barra de progreso del host refleja la nueva longitud

#### Scenario: Play Store / pre-13 — longitud invariable

- GIVEN `_restrictedSettingsBlocked = false`
- WHEN `_buildSlides()` se ejecuta
- THEN la lista NO incluye s075
- AND la longitud y orden coinciden con el onboarding v2 previo a este cambio

---

### Requirement: Inserción condicional en `ReturningUserFlow`

`ReturningUserFlow` MUST expandir su máquina de estados de `0|1` a `0|1|2`
cuando `_restrictedSettingsBlocked == true`: paso 0 = welcome-back hero,
paso 1 = `V3RestrictedSettingsStep`, paso 2 = `_ActivateListenerStep`.
Cuando es `false`, la máquina MUST mantener `0|1` (welcome-back →
`_ActivateListenerStep`) sin cambios. El widget compartido MUST montarse con
`showBackPill: false` (el host no expone back-pill global). La detección
MUST resolverse antes de que el CTA "Continuar" del welcome-back avance;
si está pendiente, el CTA MUST mostrar un spinner inline.

#### Scenario: Returning user con gate activo — 3 pasos

- GIVEN `pulledAccounts > 0` y `_restrictedSettingsBlocked = true`
- WHEN el usuario presiona "Continuar" en el welcome-back hero
- THEN el flujo avanza al paso `V3RestrictedSettingsStep` (paso 1)
- AND el siguiente paso será `_ActivateListenerStep` (paso 2)

#### Scenario: Returning user sin gate — flujo original

- GIVEN `_restrictedSettingsBlocked = false`
- WHEN el usuario avanza desde welcome-back
- THEN el flujo va directo a `_ActivateListenerStep`
- AND la longitud del flujo es 2 pasos (sin cambios respecto al actual)

#### Scenario: Detección pendiente al presionar "Continuar"

- GIVEN la consulta `isRestrictedSettingsAllowed()` aún no resolvió
- WHEN el usuario presiona "Continuar" en welcome-back
- THEN el CTA muestra un spinner inline
- AND el avance ocurre cuando la detección termina (~50ms típico)

---

### Requirement: CTA primario — deep-link a App Info

El widget compartido MUST exponer un CTA primario que invoque
`DeviceQuirksService.openAppDetails()`, el cual dispara
`Settings.ACTION_APPLICATION_DETAILS_SETTINGS` con el package
`com.bolsio.app` y `FLAG_ACTIVITY_NEW_TASK`. El sistema operativo MUST abrir
la pantalla de información de la app de Bolsio.

#### Scenario: CTA primario abre App Info

- GIVEN el paso restricted-settings está renderizado
- WHEN el usuario presiona el CTA primario ("Abrir Configuración" o copy equivalente)
- THEN el sistema abre `Settings.ACTION_APPLICATION_DETAILS_SETTINGS` para `com.bolsio.app`

---

### Requirement: Re-chequeo en lifecycle resume

El widget compartido MUST registrar un `WidgetsBindingObserver` y, al recibir
`AppLifecycleState.resumed`, MUST volver a invocar
`isRestrictedSettingsAllowed()`. Si el resultado pasó a `true`, el host MUST
auto-avanzar al siguiente paso (`s08_activate_listener` en `OnboardingPage`,
`_ActivateListenerStep` en `ReturningUserFlow`). Si sigue en `false`, el
widget MUST renderizar un hint inline minimalista de UNA sola línea bajo el
CTA (copy ejemplo: "Toca el menú ⋮ y permite la configuración restringida")
y MUST NOT auto-avanzar.

#### Scenario: Resume con AppOp ahora permitido — auto-advance

- GIVEN el usuario regresó a Bolsio tras habilitar "Allow restricted settings"
- WHEN `didChangeAppLifecycleState(resumed)` dispara la re-consulta
- AND `isRestrictedSettingsAllowed()` retorna `true`
- THEN el host avanza automáticamente al siguiente paso (s08 o `_ActivateListenerStep`)

#### Scenario: Resume con AppOp aún bloqueado — hint inline

- GIVEN el usuario regresó pero el AppOp sigue en `ignore`
- WHEN se ejecuta la re-consulta
- THEN el widget renderiza el hint de 1 línea bajo el CTA
- AND el paso NO auto-avanza
- AND el CTA primario sigue disponible para reintentar

---

### Requirement: Acción secundaria "Hacer esto más tarde"

El widget compartido MUST exponer un botón/enlace secundario "Hacer esto más
tarde" visible en todo momento. Al presionarlo, el host MUST avanzar al
siguiente paso sin persistir ningún estado de bloqueo. El comportamiento
existente de skip de `s08`/`_ActivateListenerStep` (persistir
`SettingKey.notifListenerEnabled = '0'` solo cuando se omite ese paso
posterior) MUST permanecer inalterado.

#### Scenario: Skip desde restricted-settings step

- GIVEN el paso restricted-settings está renderizado
- WHEN el usuario presiona "Hacer esto más tarde"
- THEN el host avanza al siguiente paso
- AND no se persiste ninguna clave nueva relacionada al gate
- AND `SettingKey.notifListenerEnabled` NO se modifica en este paso

---

### Requirement: Back-pill configurable según host

El widget compartido `V3RestrictedSettingsStep` MUST aceptar un parámetro
`showBackPill: bool`. En `OnboardingPage` el slide MUST montarse con
`showBackPill: true` (el host tiene navegación global hacia atrás). En
`ReturningUserFlow` MUST montarse con `showBackPill: false` (el host no
expone back-pill y volver al welcome-back hero es redundante).

#### Scenario: Back-pill visible en `OnboardingPage`

- GIVEN el slide s075 se renderiza dentro de `OnboardingPage`
- WHEN el widget compartido se monta
- THEN el back-pill es visible y permite volver al slide s07

#### Scenario: Back-pill oculto en `ReturningUserFlow`

- GIVEN el paso se renderiza dentro de `ReturningUserFlow`
- WHEN el widget compartido se monta
- THEN el back-pill NO se renderiza

---

### Requirement: Resolución asíncrona tardía de la detección

La detección del gate se inicia en `initState` y resuelve típicamente en
<50ms. Mientras la consulta está in-flight, el host MUST asumir
`_restrictedSettingsBlocked = false` (no insertar el paso). Cuando la
consulta resuelve y reporta `true`, el host MUST hacer rebuild de la lista
de slides/steps; si el usuario ya pasó del punto de inserción (caso raro),
el flujo continúa normalmente sin interrumpir al usuario.

#### Scenario: Resolución antes de que el usuario llegue al punto de inserción

- GIVEN la detección resuelve en 40ms con `blocked = true`
- AND el usuario está en s04 (mucho antes de s07)
- WHEN la lista de slides se reconstruye
- THEN s075 aparece insertado entre s07 y s08 cuando el usuario llegue ahí

#### Scenario: Resolución tardía después del punto de inserción

- GIVEN la detección resuelve después de que el usuario ya pasó s07 → s08
- WHEN el resultado llega
- THEN el flujo en curso NO se interrumpe
- AND el usuario continúa en s08 con el comportamiento estándar

---

### Requirement: i18n — namespace `onboarding.restricted_settings.*`

Las nuevas cadenas de UI del paso MUST agregarse bajo el namespace
`onboarding.restricted_settings.*` únicamente en `lib/i18n/json/en.json` y
`lib/i18n/json/es.json`. Las otras 9 locales MUST caer al fallback `en` vía
`fallback_strategy: base_locale` (no se duplican claves). Después de
modificar los JSON, `dart run slang` MUST ejecutarse para regenerar
`translations.g.dart`.

#### Scenario: Locale `de` — fallback a `en`

- GIVEN la app está configurada en alemán (`de`)
- AND `de.json` no contiene `onboarding.restricted_settings.title`
- WHEN el paso se renderiza
- THEN el título se muestra en inglés (fallback)

#### Scenario: Build limpio post-regeneración

- GIVEN se agregaron las 9 claves a `en.json` y `es.json`
- WHEN se ejecuta `dart run slang` y luego `flutter analyze`
- THEN no hay errores ni claves huérfanas reportadas

---

### Requirement: Campo `restrictedSettingsAllowed` en `CapturePermissionsState`

`CapturePermissionsState` MUST exponer un campo nuevo
`restrictedSettingsAllowed: bool` poblado por `PermissionCoordinator.check()`
vía `DeviceQuirksService.isRestrictedSettingsAllowed()`. El campo MUST
existir aunque ninguna UI lo consuma en este cambio (la fila en
`Settings → Auto-import` está deferred a un follow-up). En plataformas
no-Android o cuando la consulta lanza, el campo MUST ser `true` (fail-open).

#### Scenario: Campo poblado en Android sideload con gate activo

- GIVEN el dispositivo es Android 13+ sideload con AppOp `ignore`
- WHEN `PermissionCoordinator.check()` se ejecuta
- THEN `state.restrictedSettingsAllowed == false`

#### Scenario: Campo en plataforma no-Android

- GIVEN el runtime es Windows o web
- WHEN `PermissionCoordinator.check()` se ejecuta
- THEN `state.restrictedSettingsAllowed == true` (fail-open)
