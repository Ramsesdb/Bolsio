# Spec: Onboarding v2 — Auto-Import First

Cubre los 10 slides del nuevo flujo de onboarding, los servicios transversales
(`BankDetectionService`, `DeviceQuirksService.openNotificationListenerSettings`,
`SettingKey.onboardingGoals`) y las obligaciones de i18n y limpieza de assets.

---

## Módulo 1: Controller y gate de plataforma

### Requirement: Gate de plataforma para slides 5–8

El `OnboardingController` MUST evaluar `Platform.isAndroid` (verificación positiva)
antes de presentar el slide 5. En runtimes no-Android (web, Windows, cualquier
objetivo futuro incluyendo iOS hasta que el directorio `ios/` exista y se scaffoldee
oficialmente), el flujo MUST saltar de slide 4 directamente a slide 9 (Seeding overlay).
El código MUST NOT usar `!Platform.isIOS` como condición equivalente.

#### Scenario: Android — flujo completo 10 slides

- GIVEN el dispositivo es Android
- WHEN el usuario completa el slide 4 (Cuentas iniciales)
- THEN el controller avanza al slide 5 (Auto-import sell)

#### Scenario: No-Android — slides 5–8 omitidos

- GIVEN el dispositivo NO es Android (web, Windows u otro)
- WHEN el usuario completa el slide 4
- THEN el controller avanza directamente al slide 9 (Seeding overlay)
- AND los slides 5, 6, 7 y 8 MUST NOT renderizarse en ningún momento

---

### Requirement: Navegación entre slides

El controller MUST exponer métodos `next()` y `back()`. El botón "Atrás" en slide 1
MUST estar deshabilitado. El botón "Siguiente" de cada slide MUST estar deshabilitado
mientras no se cumpla la condición mínima de ese slide (si la hay). El slide 9
(Seeding overlay) MUST NOT exponer botón "Atrás" ni "Siguiente" — el avance es
automático al completar `PersonalVESeeder.seedAll`.

#### Scenario: Botón atrás deshabilitado en slide 1

- GIVEN el usuario está en el slide 1 (Objetivos)
- WHEN se renderiza el slide
- THEN el botón "Atrás" aparece deshabilitado o no visible
- AND presionarlo (si visible) no produce acción

---

## Módulo 2: Slide 1 — Objetivos

### Requirement: Selección de objetivos financieros

El slide MUST presentar al menos 5 opciones de objetivo como chips seleccionables:
`track_expenses`, `save_usd`, `reduce_debt`, `budget`, `analyze`. El usuario MUST poder
seleccionar múltiples opciones. La selección SHOULD estar vacía al entrar por primera vez.
El botón "Siguiente" MUST estar habilitado incluso sin selección (los objetivos son
opcionales — sirven para personalización futura, no bloquean el flujo).

#### Scenario: Avance sin selección

- GIVEN el usuario está en slide 1
- AND no ha seleccionado ningún objetivo
- WHEN presiona "Siguiente"
- THEN el controller persiste `SettingKey.onboardingGoals` con valor `'[]'`
- AND avanza al slide 2

#### Scenario: Avance con selección parcial

- GIVEN el usuario selecciona "Ahorrar en USD" y "Reducir deudas"
- WHEN presiona "Siguiente"
- THEN el controller persiste `SettingKey.onboardingGoals` con valor `'["save_usd","reduce_debt"]'`
- AND avanza al slide 2

#### Scenario: Deselección de chip activo

- GIVEN el usuario tiene un chip activo
- WHEN lo presiona nuevamente
- THEN el chip vuelve a estado inactivo
- AND no se persiste la clave hasta que avance con "Siguiente"

---

## Módulo 3: Slide 2 — Moneda

### Requirement: Selección de moneda preferida

El slide MUST presentar tres opciones: `USD`, `VES`, `DUAL`. Solo puede estar activa
una a la vez. El valor por defecto MUST ser el resultado de
`CurrencyService.getDeviceDefaultCurrencyCode()`. El botón "Siguiente" MUST
estar habilitado en todo momento (siempre hay una opción seleccionada).

Al avanzar, el controller MUST llamar
`UserSettingService.setItem(SettingKey.preferredCurrency, value)`.

#### Scenario: Avance con moneda por defecto

- GIVEN el dispositivo detecta VES como moneda del sistema
- AND el usuario no modifica la selección
- WHEN presiona "Siguiente"
- THEN `preferredCurrency` se persiste con valor `'VES'`

#### Scenario: Cambio a USD

- GIVEN la moneda por defecto es VES
- AND el usuario selecciona USD
- WHEN presiona "Siguiente"
- THEN `preferredCurrency` se persiste con valor `'USD'`

#### Scenario: Selección DUAL

- GIVEN el usuario selecciona DUAL
- WHEN presiona "Siguiente"
- THEN `preferredCurrency` se persiste con valor `'DUAL'`

---

## Módulo 4: Slide 3 — Tasa de cambio

### Requirement: Selección de fuente de tasa

El slide MUST presentar dos opciones: `BCV` y `Paralelo`. Solo puede estar activa
una. El valor por defecto MUST ser `'bcv'` (coincide con el default documentado en
`user_setting_service.dart:123`). Al avanzar, el controller MUST llamar
`UserSettingService.setItem(SettingKey.preferredRateSource, value)`.

El slide SHOULD mostrar una breve descripción de cada fuente para orientar al usuario.
El slide MUST mostrarse independientemente de la moneda seleccionada en slide 2,
incluyendo cuando se seleccionó USD puro (el usuario puede cambiar de moneda después
sin volver a hacer onboarding).

#### Scenario: Avance con BCV por defecto

- GIVEN el usuario no modifica la selección
- WHEN presiona "Siguiente"
- THEN `preferredRateSource` se persiste con valor `'bcv'`

#### Scenario: Selección Paralelo

- GIVEN el usuario selecciona Paralelo
- WHEN presiona "Siguiente"
- THEN `preferredRateSource` se persiste con valor `'paralelo'`

---

## Módulo 5: Slide 4 — Cuentas iniciales

### Requirement: Selección de bancos para sembrado

El slide MUST mostrar la lista de bancos disponibles en `PersonalVESeeder`
(como mínimo: Banco de Venezuela, Mercantil, Banesco, BBVA Provincial, Bicentenario,
Zinli). El usuario MUST poder seleccionar múltiples bancos. La selección SHOULD estar
vacía al entrar. El botón "Siguiente" MUST estar habilitado sin selección mínima
(selección vacía genera cuentas sin perfil bancario específico).

Los logos de bancos MUST renderizarse como placeholders geométricos usando los colores
de marca existentes en `_kBanks`; NO se usan SVGs de terceros en esta fase.

#### Scenario: Avance sin bancos seleccionados

- GIVEN el usuario no selecciona ningún banco
- WHEN presiona "Siguiente"
- THEN el controller almacena una lista de `selectedBankIds` vacía
- AND el flujo continúa (seeding se ejecutará con lista vacía — idempotente)

#### Scenario: Selección de dos bancos

- GIVEN el usuario selecciona BDV y Zinli
- WHEN presiona "Siguiente"
- THEN el controller almacena `selectedBankIds = ['bdv', 'zinli']` en memoria
- AND el flujo continúa al slide 5 (Android) o slide 9 (no-Android)

---

## Módulo 6: Slides 5–8 — Bloque Android (Auto-import)

### Requirement: Slide 5 — Venta del auto-import

El slide MUST mostrar una animación de notificación entrante (`v3-notif-in`, 0.6s
staggered), el título del beneficio y un CTA "Cómo funciona" no bloqueante.
No requiere ninguna acción del usuario para avanzar — el botón "Siguiente" MUST
estar habilitado en todo momento.

#### Scenario: Animación al entrar

- GIVEN el usuario llega al slide 5
- WHEN el widget se monta
- THEN la animación `v3-notif-in` se ejecuta una sola vez (no en loop)

---

### Requirement: Slide 6 — Privacidad

El slide MUST mostrar los bullets de privacidad (procesamiento local, sin envío a
terceros, sin acceso a contenido de mensajes fuera de patrones BDV/Zinli/Binance).
No requiere interacción; el botón "Siguiente" MUST estar habilitado en todo momento.

#### Scenario: Avance directo

- GIVEN el usuario está en slide 6
- WHEN presiona "Siguiente"
- THEN avanza a slide 7 sin ninguna persistencia adicional

---

### Requirement: Slide 7 — Activar listener (decisión soft-skip)

El slide MUST mostrar un botón "Activar ahora" que invoca
`DeviceQuirksService.openNotificationListenerSettings()`. Después de que el
usuario regresa desde la pantalla del sistema, el slide MUST llamar a
`PermissionCoordinator.check()` para leer el estado actualizado del permiso.

El slide MUST mostrar un enlace/botón secundario "Omitir por ahora" visible en todo
momento. Si el usuario omite sin activar, el controller MUST escribir
`UserSettingService.setItem(SettingKey.notifListenerEnabled, '0')` y avanzar
al slide 8. El flujo MUST NOT bloquearse ni mostrar un modal de advertencia modal
al omitir — puede mostrar un texto informativo inline ("Sin esto, el auto-import
no estará disponible hasta que lo actives en Ajustes").

En dispositivos MIUI/HyperOS (detectados vía `DeviceQuirksService.detect()`), el
slide MUST mostrar las instrucciones OEM adicionales inline antes del CTA principal.

#### Scenario: Activación exitosa

- GIVEN el usuario está en slide 7
- AND presiona "Activar ahora"
- AND en la pantalla del sistema activa el permiso para Wallex
- AND regresa a la app
- WHEN `PermissionCoordinator.check()` confirma `notificationListener = true`
- THEN el slide muestra estado "Activado" (badge de check)
- AND el botón "Siguiente" avanza al slide 8

#### Scenario: Regreso sin activar — soft-skip

- GIVEN el usuario presiona "Activar ahora"
- AND regresa desde la pantalla del sistema SIN activar el permiso
- WHEN `PermissionCoordinator.check()` confirma `notificationListener = false`
- THEN el slide muestra el mensaje inline "Sin esto, el auto-import no estará disponible hasta que lo actives en Ajustes"
- AND el botón "Omitir por ahora" sigue visible
- AND el botón "Activar ahora" sigue disponible para reintentar

#### Scenario: Omisión directa sin intentar activar

- GIVEN el usuario está en slide 7
- AND nunca presiona "Activar ahora"
- WHEN presiona "Omitir por ahora"
- THEN el controller persiste `SettingKey.notifListenerEnabled = '0'`
- AND avanza al slide 8
- AND NO se muestra ningún modal ni diálogo bloqueante

#### Scenario: MIUI detectado — instrucciones adicionales

- GIVEN `DeviceQuirksService.detect()` retorna quirk MIUI o HyperOS
- WHEN el slide 7 se monta
- THEN las instrucciones OEM se muestran inline encima del CTA "Activar ahora"

#### Scenario: Fallo del intent de settings

- GIVEN `DeviceQuirksService.openNotificationListenerSettings()` lanza excepción
- WHEN el usuario presiona "Activar ahora"
- THEN el controller captura la excepción
- AND llama a `DeviceQuirksService.openAppDetails()` como fallback
- AND muestra un toast con instrucción manual

---

### Requirement: Slide 8 — Apps incluidas

El slide MUST invocar `BankDetectionService.getInstalledBankIds()` al montarse.
El resultado MUST cruzarse con la lista estática `_kBanks` para mostrar solo los
bancos detectados. Por cada banco detectado, MUST mostrarse un toggle que lea
su estado inicial desde `UserSettingService.isProfileEnabled(profileId)`. El usuario
MUST poder activar o desactivar cada perfil de banco; el cambio MUST persistirse de
inmediato con `UserSettingService.setItem(SettingKey.{profile}Enabled, value)`.

Si `BankDetectionService.getInstalledBankIds()` retorna lista vacía o lanza
excepción, el slide MUST mostrar la lista estática completa de `_kBanks` como
fallback con todos los toggles en estado default (ON).

#### Scenario: Bancos detectados correctamente

- GIVEN BDV y Zinli están instalados en el dispositivo
- WHEN el slide 8 se monta
- THEN se muestran únicamente los tiles de BDV y Zinli con su toggle en ON (default)

#### Scenario: Toggle desactivado por el usuario

- GIVEN el tile de BDV está en ON
- WHEN el usuario lo desactiva
- THEN `UserSettingService.setItem(SettingKey.bdvNotifProfileEnabled, '0')` se persiste de inmediato
- AND el toggle muestra estado OFF

#### Scenario: Ninguna app detectada — fallback a lista estática

- GIVEN `BankDetectionService.getInstalledBankIds()` retorna `[]`
- WHEN el slide 8 se monta
- THEN se muestra la lista estática completa de `_kBanks`
- AND todos los toggles inician en ON

#### Scenario: Excepción en detección — fallback a lista estática

- GIVEN `BankDetectionService.getInstalledBankIds()` lanza excepción
- WHEN el slide 8 se monta
- THEN se captura la excepción (no propagada al usuario como error visible)
- AND se muestra la lista estática completa con toggles en ON

---

## Módulo 7: Slide 9 — Seeding overlay

### Requirement: Seeding teatral durante `PersonalVESeeder.seedAll`

El slide MUST mostrarse automáticamente antes de la pantalla "Listo". El controller
MUST llamar `PersonalVESeeder.seedAll(selectedBankIds: bankIds)` inmediatamente
al montarse este slide. La animación del overlay MUST ejecutarse durante al menos
500ms antes de avanzar automáticamente al slide 10, incluso si `seedAll` completa
antes. El botón "Siguiente" MUST NOT mostrarse — el avance es automático.

`PersonalVESeeder.seedAll` es idempotente (guard en `personal_ve_seeders.dart:28`);
si el usuario llega al slide 9 más de una vez (re-entry por crash o fondo/primer plano),
MUST re-ejecutarse sin error.

#### Scenario: Seeding completado antes del mínimo visual

- GIVEN `PersonalVESeeder.seedAll` completa en 100ms
- WHEN el slide 9 se monta
- THEN la animación se mantiene al menos 500ms totales antes de avanzar
- AND el usuario ve la transición suave al slide 10

#### Scenario: Seeding tarda más del mínimo visual

- GIVEN `PersonalVESeeder.seedAll` tarda 800ms
- WHEN el slide 9 se monta
- THEN el avance al slide 10 ocurre al completarse `seedAll` (~800ms)
- AND la animación no se interrumpe artificialmente

#### Scenario: Re-entry al slide 9 (app en background durante seeding)

- GIVEN el usuario pone la app en background mientras está en slide 9
- AND regresa
- WHEN `PersonalVESeeder.seedAll` se re-ejecuta
- THEN no se produce error ni duplicado de datos
- AND el flujo continúa normalmente hacia slide 10

---

## Módulo 8: Slide 10 — Listo + handoff

### Requirement: Handoff al finalizar el onboarding

Al presionar el CTA del slide 10 ("Listo" / "Empezar"), el controller MUST ejecutar
las siguientes operaciones en orden:

1. `AppDataService.setItem(AppDataKey.introSeen, '1')`
2. `RouteUtils.pushRoute(PageSwitcher, withReplacement: true)`

La operación (1) MUST completarse antes de ejecutar (2). Si (1) falla, MUST NOT
ejecutarse (2) — el onboarding no debe dejarse marcado como completado sin la
navegación correspondiente.

#### Scenario: CTA presionado correctamente

- GIVEN el usuario está en slide 10
- WHEN presiona el CTA principal
- THEN `AppDataKey.introSeen` se establece en `'1'`
- AND la app navega a `PageSwitcher` reemplazando el historial de navegación
- AND el onboarding no vuelve a mostrarse en reinicios posteriores

#### Scenario: Verificación de gate en `InitialPageRouteNavigator` post-onboarding

- GIVEN `AppDataKey.introSeen = '1'` y `AppDataKey.onboarded = '1'`
- WHEN la app se reinicia
- THEN `InitialPageRouteNavigator` navega directamente a `PageSwitcher`
- AND `OnboardingPage` no se muestra

---

## Módulo 9: BankDetectionService

### Requirement: Servicio de detección de bancos instalados

`BankDetectionService` MUST ser el único punto de acceso al paquete `installed_apps`
dentro del proyecto. Ningún widget ni slide MUST importar `installed_apps` directamente.
En plataformas no-Android, `getInstalledBankIds()` MUST retornar `const []` sin
invocar al paquete. Si la llamada al paquete lanza excepción, el método MUST
capturarla y retornar `const []`.

#### Scenario: Detección en Android con apps presentes

- GIVEN el dispositivo es Android y tiene instalado el app de BdV
- WHEN se invoca `BankDetectionService.getInstalledBankIds()`
- THEN el resultado contiene `'bdv_notif'` (o el profileId correspondiente)

#### Scenario: Detección en plataforma no-Android

- GIVEN el runtime es Windows o web
- WHEN se invoca `BankDetectionService.getInstalledBankIds()`
- THEN retorna `const []` sin llamar al paquete `installed_apps`

#### Scenario: Excepción del paquete

- GIVEN `installed_apps` lanza una excepción en runtime
- WHEN se invoca `BankDetectionService.getInstalledBankIds()`
- THEN el servicio captura la excepción
- AND retorna `const []`

---

## Módulo 10: DeviceQuirksService — openNotificationListenerSettings

### Requirement: Nueva operación en el MethodChannel existente

`DeviceQuirksService` MUST exponer el método
`Future<void> openNotificationListenerSettings()` que invoca la operación
`'openNotificationListenerSettings'` por el canal `com.wallex.capture/quirks`.
El lado Kotlin MUST disparar `Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)`
con `FLAG_ACTIVITY_NEW_TASK`. Si el intent falla (excepción o plataforma no-Android),
el método MUST propagar la excepción para que el caller (slide 7) pueda activar
el fallback a `openAppDetails()`.

#### Scenario: Intent disparado correctamente en Android estándar

- GIVEN el dispositivo es Android con AOSP/OxygenOS/etc.
- WHEN se invoca `DeviceQuirksService.openNotificationListenerSettings()`
- THEN el sistema abre la pantalla de configuración de listeners de notificación

#### Scenario: Excepción propagada al caller

- GIVEN el intent lanza `PlatformException`
- WHEN se invoca el método
- THEN la excepción se propaga sin capturar en `DeviceQuirksService`
- AND el slide 7 ejecuta el fallback a `openAppDetails()`

---

## Módulo 11: SettingKey.onboardingGoals

### Requirement: Persistencia de objetivos del onboarding

`SettingKey.onboardingGoals` MUST almacenarse como un JSON-encoded `List<String>`
en la tabla `userSettings` (clave `'onboardingGoals'`). Cualquier código que lea
esta clave MUST interpretar `null` (clave ausente) como lista vacía `[]`.
No se escribe ninguna fila inicial para instalaciones existentes; la fila se crea
en el primer `setItem` del slide 1. Para instalaciones nuevas, el seed en
`seed.dart` MUST incluir la fila con valor `'[]'`.

#### Scenario: Lectura de clave ausente en instalación existente

- GIVEN una instalación que existía antes de esta versión (sin fila `onboardingGoals`)
- WHEN se lee `SettingKey.onboardingGoals`
- THEN el código retorna lista vacía `[]` (no arroja excepción ni null pointer)

#### Scenario: Escritura y lectura posterior

- GIVEN el usuario seleccionó `save_usd` y `budget`
- WHEN el slide 1 persiste la selección
- AND posteriormente se lee `SettingKey.onboardingGoals`
- THEN el valor retornado es `['save_usd', 'budget']`

---

## Módulo 12: i18n — Purga INTRO, introduce intro snake_case

### Requirement: Limpieza del namespace legacy y creación del nuevo

El namespace `INTRO` (mayúsculas) MUST eliminarse de los 10 archivos JSON de
localización (`lib/i18n/json/*.json`). Se MUST introducir el namespace `intro`
(snake_case) con las claves necesarias para los 10 slides. Las locales `es` y `en`
MUST tener todas las claves completas el día de entrega. Las otras 8 locales
(`de, fr, hu, it, tr, uk, zh-CN, zh-TW`) MUST contener únicamente las claves
que ya tenían en el namespace `INTRO` legacy que sean reutilizables; el resto cae a
la locale base `en` por `fallback_strategy: base_locale`.

Después de toda modificación a los JSON, MUST ejecutarse `dart run slang` para
regenerar `translations.g.dart`. El build MUST estar limpio (`flutter analyze` sin
errores) antes de considerar esta tarea completa.

#### Scenario: Grep de referencias legacy post-purga

- GIVEN el namespace `INTRO` ha sido eliminado de todos los JSON
- AND `dart run slang` ha sido ejecutado
- WHEN se ejecuta `grep -r "t\.INTRO" lib/`
- THEN el resultado está vacío (cero coincidencias)

#### Scenario: Locale de fallback en alemán

- GIVEN la app está configurada en alemán (`de`)
- AND la clave `intro.slide1_title` no existe en `de.json`
- WHEN el slide 1 renderiza el título
- THEN se muestra el texto en inglés (fallback a `en` por `fallback_strategy: base_locale`)

---

## Módulo 13: Limpieza de assets huérfanos

### Requirement: Eliminación de SVGs del onboarding anterior

Los archivos `assets/icons/app_onboarding/first.svg`, `security.svg`, `upload.svg`
y `wallet.svg` MUST eliminarse del repositorio. La entrada
`assets/icons/app_onboarding/` MUST eliminarse de `pubspec.yaml`. Antes de
eliminar, MUST ejecutarse un grep de confirmación que verifique cero referencias
a esos archivos en el árbol `lib/`.

#### Scenario: Grep de confirmación antes de borrar

- GIVEN se ejecuta `grep -r "app_onboarding" lib/`
- WHEN se revisa el resultado
- THEN no hay ninguna referencia a ninguno de los 4 SVGs ni al directorio
- AND se procede con la eliminación

#### Scenario: Build limpio post-eliminación

- GIVEN los 4 SVGs y la entrada en `pubspec.yaml` han sido eliminados
- WHEN se ejecuta `flutter pub get` y `flutter analyze`
- THEN no se produce ningún error relacionado con assets faltantes
