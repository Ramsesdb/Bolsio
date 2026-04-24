# Tasks: onboarding-v2-auto-import

> Audit reconciliation 2026-04-24: Fases 1–4 marked ✅ based on commit `d5d9663`. Fase 5 (controller rewrite) is the blocker for Fase 7. See note under 6.1 for a hidden i18n migration prerequisite.

## Fase 1 — Infraestructura (pubspec, manifest, assets, directorios)

- [x] 1.1 En `pubspec.yaml`: añadir `google_fonts`, `flutter_animate`, `installed_apps` bajo `dependencies`
- [x] 1.2 En `pubspec.yaml`: eliminar la entrada `assets/icons/app_onboarding/` de la sección `flutter.assets`
- [x] 1.3 Eliminar los cuatro SVGs huérfanos: `assets/icons/app_onboarding/first.svg`, `security.svg`, `upload.svg`, `wallet.svg`
      — ejecutar primero `grep -r "app_onboarding" lib/` para confirmar cero referencias
- [x] 1.4 En `android/app/src/main/AndroidManifest.xml`: añadir `<uses-permission android:name="android.permission.QUERY_ALL_PACKAGES"/>` con comentario `<!-- TODO: split Play Store flavor (foss vs play) to omit QUERY_ALL_PACKAGES -->`
- [x] 1.5 Crear los directorios vacíos: `lib/app/onboarding/slides/`, `lib/app/onboarding/widgets/`, `lib/app/onboarding/theme/`, `lib/core/services/bank_detection/`
- [x] 1.6 Ejecutar `flutter pub get` para validar resolución de los tres paquetes nuevos

## Fase 2 — Servicios core

- [x] 2.1 En `lib/core/database/services/user-setting/user_setting_service.dart`: añadir `onboardingGoals` al enum `SettingKey` con docstring que indique «JSON-encoded `List<String>`; `null` se interpreta como lista vacía»
- [x] 2.2 En `lib/core/database/sql/initial/seed.dart`: añadir la fila `('${SettingKey.onboardingGoals.name}', '[]')` en `settingsInitialSeedSQL()` (sin tocar `schemaVersion`)
- [x] 2.3 Crear `lib/core/services/bank_detection/bank_detection_service.dart`:
      - método `Future<List<String>> getInstalledBankIds()` — retorna `const []` en no-Android; en Android llama a `InstalledApps.getInstalledApps(true, true)` y cruza package names con un `const Map<String, String> _kPackageToProfileId` (p.ej. `'com.bbva.bbvacontigo': 'provincial_notif'`); captura excepciones y retorna `const []`
- [x] 2.4 En `lib/core/services/auto_import/capture/device_quirks_service.dart`: añadir `Future<void> openNotificationListenerSettings()` que invoca la operación `'openNotificationListenerSettings'` por el canal `com.wallex.capture/quirks` sin capturar la excepción (el caller en slide 7 la maneja)
- [x] 2.5 En el handler Kotlin del canal `com.wallex.capture/quirks` (localizar en `android/app/src/main/kotlin/`): añadir el case `'openNotificationListenerSettings'` que dispara `startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS).apply { addFlags(Intent.FLAG_ACTIVITY_NEW_TASK) })`

## Fase 3 — Tokens y widgets atómicos

- [x] 3.1 Crear `lib/app/onboarding/theme/v3_tokens.dart`:
      accent `const Color _kAccent = Color(0xFFC8B560)`, spacing map `{8,10,12,14,16,22,24,26}`, radii `{pill:999, lg:22, md:14, sm:10}`, duraciones `{notifIn:600ms, cardIn:300ms, pulse:2400ms}`
- [x] 3.2 Crear `lib/app/onboarding/widgets/v3_progress_bar.dart`: barra segmentada de 3px a `top:52`, un segmento por slide activo, color accent para completados
- [x] 3.3 Crear `lib/app/onboarding/widgets/v3_slide_template.dart`: scaffold que aplica padding, expone `child`, `primaryCta` y `secondaryCta` opcionales; el primaryCta recibe `enabled` para el estado deshabilitado
- [x] 3.4 Crear `lib/app/onboarding/widgets/v3_goal_chip.dart`: chip seleccionable con `label`, `selected`, `onTap`
- [x] 3.5 Crear `lib/app/onboarding/widgets/v3_currency_tile.dart`: tile radio con `currencyCode`, `selected`, `onTap`
- [x] 3.6 Crear `lib/app/onboarding/widgets/v3_rate_tile.dart`: tile radio con `label`, `subtitle`, `selected`, `onTap`
- [x] 3.7 Crear `lib/app/onboarding/widgets/v3_bank_tile.dart`: placeholder geométrico con color de marca, nombre, y `Switch` para el toggle de perfil; recibe `enabled`, `onChanged`
- [x] 3.8 Crear `lib/app/onboarding/widgets/v3_notification_card.dart`: card estática animada con `v3-notif-in` (stagger 0.6s vía `flutter_animate`)
- [x] 3.9 Crear `lib/app/onboarding/widgets/v3_seeding_overlay.dart`: overlay con logo + texto + `CircularProgressIndicator` compacto

## Fase 4 — Slides

- [x] 4.1 Crear `lib/app/onboarding/slides/s01_goals.dart` — `StatelessWidget`; recibe `Set<String> selectedGoals`, `void Function(String) onToggle`; renderiza chips para los 5 objetivos (`track_expenses, save_usd, reduce_debt, budget, analyze`); CTA siempre habilitado
- [x] 4.2 Crear `lib/app/onboarding/slides/s02_currency.dart` — recibe `String selectedCurrency`, `void Function(String) onSelect`; tiles para `USD`, `VES`, `DUAL`; CTA siempre habilitado
- [x] 4.3 Crear `lib/app/onboarding/slides/s03_rate_source.dart` — recibe `String selectedRateSource`, `void Function(String) onSelect`; tiles para `bcv` y `paralelo` con descripción; CTA siempre habilitado
- [x] 4.4 Crear `lib/app/onboarding/slides/s04_initial_accounts.dart` — recibe `Set<String> selectedBankIds`, `void Function(String) onToggleBank`; renderiza grid de `_kBanks` como `v3_bank_tile` sin toggle (solo selección); CTA siempre habilitado
- [x] 4.5 Crear `lib/app/onboarding/slides/s05_autoimport_sell.dart` — sin estado; monta `v3_notification_card` con `v3-notif-in` en `initState`; CTA siempre habilitado
- [x] 4.6 Crear `lib/app/onboarding/slides/s06_privacy.dart` — sin estado; bullets de privacidad en texto; CTA siempre habilitado
- [x] 4.7 Crear `lib/app/onboarding/slides/s07_activate_listener.dart`:
      - `StatefulWidget`; implementa `WidgetsBindingObserver`
      - en `didChangeAppLifecycleState(resumed)`: llama `PermissionCoordinator.check()` y actualiza `_granted`
      - detecta quirk MIUI/HyperOS via `DeviceQuirksService.detect()` al montar; muestra instrucciones OEM inline si aplica
      - botón "Activar ahora": invoca `DeviceQuirksService.openNotificationListenerSettings()`; en excepción llama `openAppDetails()` + toast
      - botón "Omitir por ahora": persiste `notifListenerEnabled = '0'` y llama `onSkip`
      - CTA principal ("Siguiente") habilitado solo cuando `_granted == true`
- [x] 4.8 Crear `lib/app/onboarding/slides/s08_apps_included.dart`:
      - `StatefulWidget`; en `initState` llama `BankDetectionService().getInstalledBankIds()`; si vacío o excepción usa `_kBanks` completo como fallback
      - renderiza `v3_bank_tile` con toggle para cada banco detectado
      - cada toggle llama `UserSettingService.instance.setItem(SettingKey.{profile}Enabled, value)` de inmediato
      - CTA siempre habilitado
- [x] 4.9 Crear `lib/app/onboarding/slides/s09_seeding_overlay.dart`:
      - `StatefulWidget`; en `initState` ejecuta `Future.wait([_doSeed(), Future.delayed(const Duration(milliseconds: 500))])` y llama `onDone` al completar
      - `_doSeed()` llama `PersonalVESeeder.seedAll(selectedBankIds: bankIds)`
      - renderiza `v3_seeding_overlay`; sin botones
- [x] 4.10 Crear `lib/app/onboarding/slides/s10_ready.dart` — sin estado; CTA llama `onFinish`; lista de criterios de éxito (feature highlights)

## Fase 5 — Controller (reescritura de onboarding.dart)

- [x] 5.1 Reescribir `lib/app/onboarding/onboarding.dart` conservando la clase `OnboardingPage` (el router la referencia por nombre):
      - campos de estado: `_selectedGoals`, `_selectedCurrency`, `_selectedRateSource`, `_selectedBankIds`, `_currentIndex`, `_pageController`
      - calcular `_totalSlides`: 10 en Android, 6 en no-Android (slides 5–8 omitidos); construir lista de widgets de slide condicionalmente con `Platform.isAndroid`
      - método `_next()` / `_prev()` con `pageController.animateToPage`
      - método `_finish()` en orden: `UserSettingService.setItem(onboardingGoals, json)` → `setItem(preferredCurrency)` → `setItem(preferredRateSource)` → `PersonalVESeeder.seedAll` (ya ejecutado en slide 9 — esta llamada es un no-op por idempotencia, pero es el último punto de seguridad) → `AppDataService.setItem(introSeen, '1')` → `RouteUtils.pushRoute(PageSwitcher, withReplacement: true)`
      - pasar `v3_progress_bar` con `currentIndex` y `totalSlides`
- [x] 5.2 Verificar que `lib/main.dart` no requiere cambios: el gate `AppDataKey.introSeen` y la referencia a `OnboardingPage` permanecen intactos

## Fase 6 — i18n

- [x] 6.1 En los 10 ficheros `lib/i18n/json/*.json`: eliminar el bloque `"INTRO": { … }` completo
      — ejecutar antes `grep -r "t\.INTRO" lib/` para confirmar cero consumidores
      - **Audit correction 2026-04-24:** the "3 callers" assumption was wrong — only `about.page.dart:82` actually consumed the namespace (`t.intro.welcome_subtitle2` → app tagline). `main.dart` and `app_db.g.dart` were false positives (`introSeen` AppDataKey + drift `introducedVariables`). That single caller has been migrated to a new `shared.app_tagline` key; the full `INTRO` block is now deleted from all 10 locale JSONs.
- [ ] 6.2 En `lib/i18n/json/es.json`: añadir bloque `"intro"` snake_case con todas las claves necesarias para los 10 slides (títulos, subtítulos, CTAs, labels de chips/tiles, mensajes de estado del listener, bullets de privacidad, texto de seeding)
- [ ] 6.3 En `lib/i18n/json/en.json`: replicar el bloque `"intro"` completo en inglés
- [ ] 6.4 En los otros 8 JSON (`de, fr, hu, it, tr, uk, zh-CN, zh-TW`): no añadir claves `intro` — el fallback a `en` via `fallback_strategy: base_locale` cubre estas locales
- [ ] 6.5 Ejecutar `dart run slang` y verificar que `translations.g.dart` regenera sin errores ni claves faltantes para `es` y `en`

### Deferred to a future change (scoped out 2026-04-24)

Tasks 6.2-6.5 required wiring the v3 slides, the `onboarding.dart` controller, and `v3_seeding_overlay.dart` to a new `t.intro.*` namespace. This was deferred during the minimal-close pass for path A because:

- Wallex's sole active audience is Spanish-speaking Venezuelan users; the other 9 locales are Monekin legacy with no Wallex-specific content.
- The slides' strings are deeply Venezuela-specific (BCV, paralelo, local bank names) and would not translate meaningfully into the other locales.
- The slides ship working in Spanish today. Hardcoded Spanish is not a correctness bug.

Follow-up: open a new SDD change (e.g. `onboarding-i18n-extension`) if/when Wallex targets a second locale.

## Fase 7 — Verificación y smoke tests

- [ ] 7.1 Ejecutar `flutter analyze` — resolver cualquier warning antes de continuar
- [ ] 7.2 Ejecutar `grep -r "INTRO" lib/i18n/` — resultado esperado: cero coincidencias
- [ ] 7.3 Ejecutar `grep -r "app_onboarding" lib/ pubspec.yaml` — resultado esperado: cero coincidencias
- [ ] 7.4 Smoke — Android (POCO Rodin, Android 15): flujo completo 10 slides sin omitir nada; verificar que al llegar al slide 10 y presionar "Listo" la app navega a `PageSwitcher` y no vuelve a mostrar el onboarding al reiniciar
- [ ] 7.5 Smoke — Slide 1: seleccionar 3 objetivos → avanzar → verificar con DevTools/logs que `onboardingGoals` contiene el JSON correcto
- [ ] 7.6 Smoke — Slide 7: presionar "Activar ahora" → ir al sistema → activar → volver → badge "Activado" visible → "Siguiente" habilitado
- [ ] 7.7 Smoke — Slide 7: presionar "Omitir por ahora" sin activar → avanza a slide 8 → sin modal bloqueante; verificar que `notifListenerEnabled = '0'` está en DB
- [ ] 7.8 Smoke — Slide 7 en MIUI/HyperOS: instrucciones OEM visibles antes del CTA principal
- [ ] 7.9 Smoke — Slide 8: con BDV instalado → tile detectado visible; desactivar toggle → verificar que `bdvNotifProfileEnabled = '0'` se persiste de inmediato
- [ ] 7.10 Smoke — Slide 8: sin apps de bancos instaladas → lista estática completa visible con todos los toggles en ON
- [ ] 7.11 Smoke — Slide 9: observar que la animación de seeding dura al menos 500ms incluso en device rápido
- [ ] 7.12 Smoke — No-Android (Windows): ejecutar `flutter run -d windows`; verificar que el flujo salta de slide 4 a slide 9 directamente (slides 5–8 no renderizan)
- [ ] 7.13 Smoke — Re-entrada: con `introSeen = '0'` forzado en DB, reiniciar app → onboarding aparece; completar de nuevo → seeding idempotente, sin error
- [ ] 7.14 Verificar light mode + dark mode en POCO Rodin: tokens v3 (accent `#C8B560`, radii, progress bar) visibles correctamente en ambos modos

---

## Notas de implementación

### Qué NO hacer

- No modificar `lib/main.dart` ni el gate `AppDataKey.introSeen` / `AppDataKey.onboarded`.
- No crear un fichero de migración SQL bajo `assets/sql/migrations/` para `onboardingGoals` — cero `vN.sql` para este change.
- No incrementar `schemaVersion` en `app_db.dart`.
- No añadir `installed_apps` fuera de `BankDetectionService`.
- No añadir `onboardingGoals` a `firebase_sync_service.dart` — dato de onboarding de primer uso, no sincronizable.
- No tocar `AppColors` ni `ThemeData` globales — los tokens v3 son locales al módulo de onboarding.

### Dependencias críticas

- Fase 2 debe completarse antes de Fase 4 (los slides usan los servicios).
- Fase 3 debe completarse antes de Fase 4 (los slides usan los widgets atómicos).
- Tarea 4.9 (slide 9) depende de que `PersonalVESeeder` esté accesible — no requiere cambios en el seeder, solo importarlo.
- Tarea 5.1 depende de todas las Fases 3 y 4 completas.
- Fase 6 (i18n) puede ejecutarse en paralelo con Fases 3 y 4; solo bloquea la compilación final si las claves están referenciadas antes de que `dart run slang` se ejecute.
- Tarea 7.5 (verificar `onboardingGoals`) requiere las Fases 5 y 6 completas.

### Orden de implementación recomendado

1. Fases 1 y 2 juntas (infraestructura + servicios) — base para todo lo demás.
2. Fase 3 (widgets) — construir de más genérico a más específico (`v3_slide_template` primero).
3. Fases 4 y 6 en paralelo — slides e i18n son independientes hasta que se conecten en `onboarding.dart`.
4. Fase 5 (controller) — última, integra todo.
5. Fase 7 (verificación) — solo después de que `flutter analyze` pase limpio.
