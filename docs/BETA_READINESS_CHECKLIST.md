# Bolsio — Beta Readiness Checklist

> Auditoría a fondo del repo previa a distribuir un APK a dos amigos para pruebas.
> Generado: 2026-04-29
> Cubrimos: seguridad/secretos, hardcodeos/config, TODOs/bugs/análisis estático.

---

## Checklist mínimo antes del APK

```
[ ] 1. Generar release.jks, llenar android/keys/key.properties
[ ] 2. Descomentar línea 57 de android/app/build.gradle, comentar 58
[ ] 3. Eliminar _ramseBalances + condicional email en welcome_screen
[ ] 4. Borrar android/app/google-services.json.bak
[ ] 5. Decidir buildNumber sensato en pubspec.yaml (no auto-bump)
[ ] 6. (Opcional) parchear null-bang en evaluate_expression.dart:136
[ ] 7. flutter clean && flutter build apk --release (con receta bolsio)
```

---

## 🔴 BLOQUEANTES — arreglar antes de mandar el APK

### 1. APK firmado con keystore de DEBUG en release
- **Archivo:** `android/app/build.gradle:57-58`
- **Estado:** la línea `signingConfig = signingConfigs.release` está comentada y release usa `signingConfigs.debug`.
- **Impacto:** cualquier APK que se genere ahora está firmado con el keystore de Android Studio. Si luego se firma con el real, los amigos NO podrán actualizar (firmas distintas → reinstalar a mano).
- **Acción:** generar `release.jks`, llenar `android/keys/key.properties` (hoy solo tiene `.gitkeep`), descomentar línea 57 y comentar la 58.

### 2. Datos personales se inyectan automáticamente al login
- **Archivos:**
  - `lib/app/auth/welcome_screen.dart:175` — detecta el email `ramsesdavidba@gmail.com` y dispara seed.
  - `lib/core/database/utils/personal_ve_seeders.dart:59-70` — `_ramseBalances` con saldos reales: `'Banco de Venezuela': 359484.35`, `'Banco de Venezuela USD': 46.21`, `'Binance': 571.29`, etc. (9 cuentas).
- **Impacto:** los amigos no van a disparar el branch (otro email), pero los saldos están **dentro del APK** y son extraíbles.
- **Acción:** quitar `_ramseBalances` y el condicional, o moverlo a un archivo `.gitignore`d cargado en runtime.

### 3. `google-services.json.bak` versionado
- **Archivo:** `android/app/google-services.json.bak`
- **Estado:** duplicado del `google-services.json` original. NO está cubierto por `.gitignore`.
- **Acción:** borrarlo del working tree y del historial si aplica.

---

## 🟠 IMPORTANTE — revisar antes o avisar a los amigos

### 4. Backend privado sin fallback
- **Archivos:**
  - `lib/core/services/ai/providers/nexus_provider.dart:28` → `const _defaultBaseUrl = 'https://api.ramsesdb.tech'`
  - `lib/core/services/ai/nexus_ai_service.dart:64` → `const _baseUrl = 'https://api.ramsesdb.tech'` (clase `@Deprecated`, aún referenciada).
- **Impacto:** si el servidor cae o se apaga, las features de IA dejan de funcionar para ellos. Además, expone el endpoint privado a cualquiera que extraiga el APK.
- **Acción:** confirmar rate-limiting/auth en `api.ramsesdb.tech`, o documentar en README que requiere BYOK (clave propia de OpenAI/Anthropic/Gemini).

### 5. Crash potencial en evaluador de expresiones matemáticas
- **Archivo:** `lib/app/transactions/form/dialogs/evaluate_expression.dart:136`
- **Patrón:** `precedence[op]!` y `precedence[operators.last]!` con null-bang.
- **Impacto:** si el usuario teclea un operador inesperado en el campo de monto → crash.
- **Acción:** usar `?? defaultPrecedence` o validar el set de operadores antes.

### 6. `pubspec.yaml` versión `1.0.0+99999`
- **Archivo:** `pubspec.yaml:16` → `version: 1.0.0+99999`
- **Impacto:** buildNumber `99999` es placeholder irreal. Si luego sale una v2 con `1.0.0+1`, los amigos no podrán actualizar (Android exige `versionCode` mayor).
- **Acción:** decidir un número coherente (ej. `1.0.0+1` o `0.9.0+1` para beta) **antes** de distribuir. NO auto-bumpear (regla del usuario).

### 7. Permiso `QUERY_ALL_PACKAGES`
- **Archivo:** `android/app/src/main/AndroidManifest.xml:28` (TODO comentado para flavor FOSS).
- **Estado:** justificado (detección de bancos para auto-import) pero es el permiso más invasivo.
- **Impacto:** para amigos vía sideload da igual; relevante el día que suba a Play Store (Google audita su uso).
- **Acción:** considerar flavor FOSS sin este permiso, o preparar justificación para Play Console.

---

## 🟡 MENORES / DOCUMENTABLE

### i18n incompleto
Strings en español hardcodeados (sin `.tr()`) en:
- `lib/app/stats/stats_page.dart:155` → `'Ingresos'`
- `lib/app/stats/widgets/income_by_source/income_breakdown_table.dart:104, 128, 162, 226`
- `lib/app/stats/widgets/income_by_source/income_by_source_tab.dart:61, 68, 85-86, 96`
- `lib/app/transactions/transaction_details.page.dart:79, 81, 477, 512, 519, 528, 541, 549, 674, 745`
- `lib/app/transactions/form/widgets/exchange_rate_selector.dart:201, 221, 274, 365, 367`
- `lib/app/categories/selectors/category_multi_selector.dart:132` (TODO explícito)

Si los amigos hablan español no afecta. Sistema i18n (slang + intl) ya está configurado, solo faltan strings.

### Bancos "Próximamente"
- `lib/app/onboarding/slides/s09_apps_included.dart:283`
- `lib/app/onboarding/widgets/v3_bank_tile.dart:38, 50`

Diseño deliberado (tiles deshabilitados + badge), no bug.

### Parser BDV SMS incompleto
- `lib/core/services/auto_import/profiles/bdv_sms_profile.dart:51-52`
- TODOs: agregar "pagomovil enviado" y "consumo TDC/TDD" cuando haya fixtures reales.
- Fallback genérico funciona.

### 23 `catch (_) {}` vacíos
La mayoría son fallbacks defensivos legítimos:
- `lib/core/services/statement_import/statement_extractor_service.dart:204, 211` (JSON parsing fallback con regex retry).
- `lib/core/services/receipt_ocr/receipt_extractor_service.dart:40, 50`.
- `lib/core/services/rate_providers/rate_refresh_service.dart:244` (DolarApi fetch).
- `lib/app/transactions/form/widgets/exchange_rate_selector.dart:178, 187`.
- `lib/core/services/auto_import/orchestrator/capture_orchestrator.dart:133, 379, 629, 746`.

No crashean, pero sin telemetry no se ven los errores en producción.

### Archivos personales versionados (no en APK pero ensucian repo)
- `Gemini_Generated_Image_6ecvb46ecvb46ecv.png` (~4.9 MB)
- `Gemini_Generated_Image_dwwexldwwexldwwe.png` (~4.6 MB)
- `Registro_Financiero_Iglesia.xlsx` (~83 KB)
- `Registro_Financiero_Iglesia_3_Meses.xlsx` (~30 KB)
- `generate_excel_iglesia.py` (~17 KB)

NO están en `pubspec.yaml > flutter > assets`, no se empaquetan en el APK. Pero quien clone el repo los obtiene.

**Acción:** mover a `.gitignore` o eliminar.

### Fuentes posiblemente no usadas
`assets/fonts/` ~3.9 MB. Auditar si Cairo, Exo, Jost realmente se usan en la UI; Nunito sí es la principal. Si no se usan, removerlas.

### Email de contacto público
- `lib/app/settings/about.page.dart:121` → `mailto:ramsesdavidba@gmail.com` (intencional, contacto oficial).
- URLs de GitHub apuntan a `Ramsesdb/Bolsio` (about.page.dart:105, 114, 130, 139). OK si la marca personal es esa.

### Tag personal
- `lib/core/database/utils/personal_ve_seeders.dart:770-771` → `'pve_tag_bigwise'` con nombre `'bigwise'`. Renombrar a genérico o parametrizar.

### Tests lentos (no bloqueantes)
3 tests con timeout (2:57 min) — receipt OCR + Nexus AI:
- `test/transactions/transaction_details_receipt_test.dart` (receipt chip)
- `test/settings/avatar_custom_flow_test.dart` (replace avatar)

362/365 passing. No bloquea distribución.

---

## 🟢 LO QUE ESTÁ BIEN

- `flutter analyze` → **0 errores, 0 warnings** (96.7s).
- 362/365 tests passing.
- Credenciales sensibles en `flutter_secure_storage` con `EncryptedSharedPreferences`:
  - `lib/core/services/ai/ai_credentials_store.dart:24-26` (OpenAI, Anthropic, Gemini, Nexus).
  - `lib/core/services/auto_import/binance/binance_credentials_store.dart:18-20`.
- `.gitignore` correcto: keystores, `.env*`, `key.properties`, `google-services.json`, `*.pem`, `*.jks`.
- `minifyEnabled true` + `shrinkResources true` en release (`build.gradle:59-60`).
- Sin `usesCleartextTraffic`, sin `android:debuggable="true"`.
- Todos los endpoints externos HTTPS (OpenAI, Anthropic, Gemini, Binance, dolarapi, ramsesdb).
- `applicationId = "com.bolsio.app"` (no genérico `com.example.*`).
- `android:exported` correcto en MainActivity, BackgroundService (false), NotificationListener (con permission gate).
- Permission flow correcto: `voice_permission_dialog.dart`, `permission_coordinator.dart`, SMS graceful degradation.
- Migraciones DB coherentes: schema v27, v5→v27 todas presentes en `assets/sql/migrations/`.
- Sin `throw UnimplementedError()` en `lib/`.
- Generadores OK: `app_db.g.dart` (Drift), `translations_*.g.dart` (Slang), `pubspec.lock` sincronizado.
- Logging de AI services NO loguea apiKey ni cuerpo de respuesta — solo status code + latencia.
- `Logger.printDebug` solo imprime en `kDebugMode`.

---

## Resumen ejecutivo

**Riesgo general: BAJO-MEDIO.** El proyecto está bien estructurado.

**Bloqueantes reales para distribuir el APK:**
1. Firma de release con debug keystore.
2. Datos financieros personales hardcodeados (saldos reales).
3. `google-services.json.bak` filtrado.

**Acciones obligatorias:** 1, 2, 3, 5 (buildNumber).
**Acciones recomendadas:** 4 (documentar Nexus), 6 (null-bang), limpieza de archivos personales del repo.

Una vez resueltos los 3 bloqueantes, el APK es seguro de compartir con los amigos para beta testing.
