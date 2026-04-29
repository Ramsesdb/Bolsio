/// Source de tasa que el usuario puede elegir desde la Calculadora FX.
///
/// IMPORTANTE: este enum es **UI-only** y NO debe confundirse con
/// `ExchangeRateSource` de la base de datos (`core/database/...`). El valor
/// elegido aquí solo decide qué tasa cacheada en `DolarApiService.instance`
/// se aplica a la conversión activa; nunca se persiste como columna ni se
/// escribe a `exchangeRates`.
///
/// Orden fijo (usado por el tap-cycle del `RateSourceChip` en Tanda 4):
/// `bcv → paralelo → promedio → manual → bcv …`
enum RateSource {
  /// Tasa oficial publicada por el BCV vía DolarApi.
  bcv,

  /// Tasa "paralelo" (mercado no oficial) vía DolarApi.
  paralelo,

  /// Promedio aritmético entre BCV y Paralelo (`(bcv + paralelo) / 2`).
  promedio,

  /// Tasa ingresada manualmente por el usuario en la sesión actual.
  /// Ephemeral: se descarta al hacer pop del page.
  manual,
}
