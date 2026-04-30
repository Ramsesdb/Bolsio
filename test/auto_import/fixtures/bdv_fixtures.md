# BDV — Fixtures reales para tests del auto-import

Capturados el 2026-04-15 por el usuario. Usar textualmente en tests unitarios.
Teléfonos y cédulas son del usuario real — NO publicar este archivo fuera del repo privado.

---

## Canal SMS — remitente shortcode `2661`

### Pagomóvil recibido (positivo)

Ejemplo 1 (fecha reciente, sin espacio tras `Bs.`):
```
Recibiste un PagomovilBDV por Bs.12.000,00 del 0412-7635070 Ref: 108834202054 en fecha: 29-03-26 hora: 18:01.
```

Ejemplo 2 (2023, con espacio tras `Bs.`, monto pequeño):
```
Recibiste un PagomovilBDV por Bs. 210,00 del 0412-6638500 Ref: 000390572967 en fecha: 30-10-23 hora: 12:35
```

Ejemplo 3 (2025, con espacio tras `Bs.`):
```
Recibiste un PagomovilBDV por Bs. 900,00 del 0412-7635070 Ref: 002103869591 en fecha: 25-01-25 hora: 21:26
```

Observaciones:
- Espaciado tras `Bs.` es **inconsistente** — regex debe tolerar `Bs\.\s*` (0+ espacios).
- Formato de fecha: `DD-MM-YY` (año de 2 dígitos). Formato de hora: `HH:MM`.
- Punto final del mensaje a veces presente, a veces ausente (ver ej. 1 vs 2).
- Separador de miles: `.`   Separador decimal: `,`   (formato español).
- `Ref:` puede tener o no espacio después.
- Parser debe extraer: `amount`, `counterpartyPhone`, `bankRef`, `date`, `time`.
- `type = income`, `currencyId = 'VES'`, `accountMatchName = 'Banco de Venezuela'`.

### Negativos — deben retornar null

OTP clave de pago:
```
BDV: La clave de pago para procesar tu operacion es 67928761
```
```
BDV: La clave de pago para procesar tu operacion es 68010677
```

Código de vinculación de app terceros:
```
Tu codigo para proceder con la vinculacion de Ami Ven es 2256800 emr2y27v6wc
```

Observación: los negativos del MISMO shortcode `2661` pasan el filtro de sender pero deben ser rechazados por el BdvSmsProfile (ninguna regex matchea).

---

## Canal SMS — remitente shortcode `2662` (segundo shortcode BDV)

### Pagomóvil recibido (positivo)

Mismo formato que el shortcode `2661`. Capturados 2026-04-15.

Ejemplo 1 (2023, con espacio tras `Bs.`, con `:` tras `fecha`):
```
Recibiste un PagomovilBDV por Bs. 30,00 del 0412-6638500 Ref: 000379526101 en fecha: 22-10-23 hora: 19:16
```

Ejemplo 2 (2026, sin espacio tras `Bs.`, **sin `:` tras `fecha`**, con `.` final):
```
Recibiste un PagomovilBDV por Bs.10.620,00 del 0412-7635070 Ref: 108639858076 en fecha 27-03-26 hora: 21:31.
```

Ejemplo 3 (2026, sin espacio tras `Bs.`, **sin `:` tras `fecha`**, con `.` final):
```
Recibiste un PagomovilBDV por Bs.29.428,10 del 0424-6218586 Ref: 108639894484 en fecha 27-03-26 hora: 21:47.
```

Ejemplo 4 (2026, sin espacio tras `Bs.`, **sin `:` tras `fecha`**, con `.` final):
```
Recibiste un PagomovilBDV por Bs.5.953,10 del 0424-6125380 Ref: 000717467994 en fecha 27-03-26 hora: 22:25.
```

Observaciones:
- El `:` tras la palabra `fecha` es **inconsistente**: presente en ej. 1 ("en fecha: 22-10-23"), ausente en ej. 2-4 ("en fecha 27-03-26"). El regex debe tolerar `fecha:?` (`:` opcional).
- El `:` tras `hora` parece consistente en estos fixtures, pero el regex usa `hora:?` por defensa.
- El resto del formato es idéntico al shortcode `2661`.

### Formatos aún sin fixture real (pendientes)

- **Pagomóvil enviado**: esperado algo como `Realizaste un PagomovilBDV por Bs. X al 0416-... comisión Bs. Y Ref: Z` — FALTA CAPTURA REAL.
- **Consumo con tarjeta (TDC/TDD)**: posiblemente ya no se envía por SMS (se migró a push, ver canal push abajo). FALTA VERIFICACIÓN.

---

## Canal Notification Listener — app BDV

Formato común:
- **Título** (notification title) → identifica el tipo de operación
- **Timestamp visible** en el detalle: `DD-MM-YYYY HH:MM AM/PM`
- **Body** (notification text) → contiene monto y metadata

### Transferencia recibida (interbancaria ACH, positivo, income)

- Título: `Transferencia BDV recibida`
- Timestamp: `15-04-2026 02:36 PM`
- Body: `"Recibiste una transferencia BDV de JOINER ALEXANDER ROVARIO SAAVEDRA por Bs.277.000,00 bajo el número de operación 059135723999"`

Parser extrae:
- `amount = 277000.00`, `currencyId = 'VES'`, `type = income`
- `counterpartyName = 'JOINER ALEXANDER ROVARIO SAAVEDRA'` (cedula no disponible, solo nombre)
- `bankRef = '059135723999'` (número de operación de 12 dígitos)
- `accountMatchName = 'Banco de Venezuela'`

### Pago sin contacto / BiopagoBDV (POS contactless, expense)

- Título: `Operaciones por Punto de venta / BiopagoBDV`
- Timestamp: `15-04-2026 05:46 PM`
- Body: `Pago sin contacto realizado en punto de venta por Bs. 5.910,00, bajo el #2977, disp. 366.258,19 el 15-04-26 a las 17:46.`

Parser extrae:
- `amount = 5910.00`, `currencyId = 'VES'`, `type = expense`
- `bankRef = '#2977'` (referencia corta tipo POS)
- `balanceAfter = 366258.19` (opcional, no persiste pero sirve para validación)
- `counterpartyName = null` (POS no provee nombre del comercio en esta notif)
- `accountMatchName = 'Banco de Venezuela'`

### Pago en línea con Tarjeta Internacional (expense, USD)

- Título: `Pago en linea con tu Tarjeta Internacional`
- Timestamp: `15-04-2026 02:04 PM`
- Body: `Operacion en linea con tu Tarjeta Internacional #4325 por $.300,00 el 15-04-26 a las 14:04. Inf. 0500-6425283`

Parser extrae:
- `amount = 300.00`, **`currencyId = 'USD'`** (detectado por prefijo `$.`)
- `type = expense`
- `cardLast4 = '4325'` (metadata opcional)
- `bankRef` → ESTA NOTIFICACIÓN NO TIENE REFERENCIA — dedupe solo por `(amount, accountId, ±2h)`
- `counterpartyName = null`
- `accountMatchName = 'Banco de Venezuela'` (la cuenta VES sigue siendo la misma porque la tarjeta es del BDV; el amount USD indica que la TX debe registrarse con currencyId USD y la conversión se resuelve en ProposalReview)

### Observaciones importantes sobre notificaciones push

1. **Los `bankRef` del canal push NO coinciden con los `Ref:` del canal SMS** para el mismo evento. Las referencias son de sistemas distintos (SMS usa Ref del core bancario, push usa `número de operación` o `#XXXX`). Consecuencia: el **dedupe cross-channel por `bankRef` no es confiable**. Debe caer al dedupe por `(amount, accountId, date±window)`.

2. Prefijo de moneda en body:
   - `Bs.` → VES
   - `Bs. ` → VES
   - `$.` → USD (tarjeta internacional)

3. Separador de miles `.`, decimal `,` (formato español) consistente entre SMS y push.

4. El título de la notificación es el discriminador principal para decidir qué regex aplicar dentro del profile.

5. `disp.` indica saldo disponible post-operación. Útil para validación pero no se persiste.

### Formatos push aún sin fixture real

- Pago móvil enviado por app BDV (push)
- Pago móvil recibido por app BDV (push — confirmar si es diferente al SMS o idéntico con distinta metadata)
- Consumo tarjeta nacional TDC/TDD (push)
- Retiro por cajero automático (push)
- Transferencia enviada (push)

---

## Package name de la app BDV (Android)

Pendiente de confirmar con `adb shell pm list packages | grep -iE "bdv|venezuela"` en el dispositivo del usuario.
Candidatos conocidos:
- `com.bancodevenezuela.bdvdigital`
- `com.bdv.personas`
- `com.banco_venezuela.bdvapp`

Se actualiza este archivo cuando se confirme.

---

## Limitaciones del modelo de captura

### Operaciones ejecutadas desde la app bancaria en foreground

Cuando el usuario realiza una operación DESDE la app BDV (o Binance/Zinli) mientras
está abierta en foreground, **no hay camino automatizable para capturarla**:

1. **SMS de pagomóvil enviado**: BDV no envía SMS de confirmación al EMISOR, solo al
   receptor. Por eso no existen fixtures "Realizaste un PagomovilBDV...". El usuario
   emisor queda sin registro SMS automático de su propia operación.
2. **Push notifications con la app en foreground**: Android suprime las notificaciones
   push de la app que está activa en foreground. Si operas DESDE la app BDV, ni
   NotificationListenerService ni flutter_local_notifications pueden ver esa notif.

### Operaciones que SÍ se capturan automáticamente
- Pagomóvil **recibido** por SMS (tanto si el pagador usa BDV como otro banco).
- Operaciones realizadas desde la **web banking** (bdv.com.ve) que disparan notif push
  a la app BDV en background → el listener las captura.
- Operaciones entrantes (transferencias recibidas, abonos) por push notification.
- Consumos con tarjeta (POS, online) por push notification — la app BDV las notifica
  aunque no estés operándola.

### Mitigación — entrada manual rápida (Fase 3, fuera de alcance ahora)
Para las operaciones salientes ejecutadas desde la app bancaria, la única opción es
registro manual. Como mejora futura se podría exponer un "quick action" en Bolsio
(shortcut de Android o tile del panel rápido) que abra directamente el formulario de
transacción pre-seleccionado con la cuenta BDV/Binance/Zinli activa.
