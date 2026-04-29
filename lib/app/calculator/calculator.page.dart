import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:wallex/app/calculator/models/rate_source.dart';
import 'package:wallex/app/calculator/utils/share_card_renderer.dart';
import 'package:wallex/app/calculator/widgets/calculator_keypad.dart';
import 'package:wallex/app/calculator/widgets/currency_amount_pane.dart';
import 'package:wallex/app/calculator/widgets/rate_source_chip.dart';
import 'package:wallex/app/calculator/widgets/share_card.dart';
import 'package:wallex/app/currencies/exchange_rate_form.dart';
import 'package:wallex/app/transactions/form/dialogs/evaluate_expression.dart';
import 'package:wallex/core/database/services/currency/currency_service.dart';
import 'package:wallex/core/models/currency/currency.dart';
import 'package:wallex/core/presentation/widgets/inline_info_card.dart';
import 'package:wallex/core/presentation/widgets/number_ui_formatters/decimal_separator.dart';
import 'package:wallex/core/services/dolar_api_service.dart';
import 'package:wallex/core/utils/logger.dart';
import 'package:wallex/i18n/generated/translations.g.dart';

/// Codes que la Calculadora siempre ofrece como pane currency, aunque el
/// usuario no los tenga habilitados en `CurrencyManager`. USDT en v1 es alias
/// de paralelo; el labeling lo resuelve `RateSourceChip` en Tanda 4.
const List<String> _kCalculatorBaseCodes = ['USD', 'EUR', 'USDT', 'VES'];

/// Calculadora FX standalone.
///
/// Tanda 3 (Keypad + arithmetic): introduce el `CalculatorKeypad`, el buffer
/// `_activeExpression` evaluado vía `evaluateExpression`, el helper
/// `_effectiveRate(RateSource)` (lee de `DolarApiService.instance`) y la
/// conversión sincrónica top↔bottom. Source chip + manual rate + refresh real
/// + share pipeline llegan en tandas 4-5. Toda la wiring de estado vive aquí
/// (per `design.md` § "Estado en el page, no en un service").
class CalculatorPage extends StatefulWidget {
  const CalculatorPage({super.key});

  @override
  State<CalculatorPage> createState() => _CalculatorPageState();
}

class _CalculatorPageState extends State<CalculatorPage> {
  // ─── Currency state (Tanda 2) ──────────────────────────────────────────
  /// Currency mostrada en la pane superior. Default `USD` per spec
  /// (`Default state on first open`).
  Currency? _topCurrency;

  /// Currency mostrada en la pane inferior. Default `VES` per spec.
  Currency? _bottomCurrency;

  /// Cuál pane recibe los keystrokes del keypad. La pane activa default es la
  /// superior; el swap button alterna esta bandera.
  bool _topIsActive = true;

  /// Universo de currencies para el picker. Combina los 4 base
  /// (`USD/EUR/USDT/VES`) con las habilitadas por el usuario en
  /// `CurrencyService`. Resuelto vía stream en `initState`.
  List<Currency> _availableCurrencies = const [];

  // ─── Arithmetic state (Tanda 3) ────────────────────────────────────────
  /// Buffer crudo que se pasa a `evaluateExpression`. Arranca en `'1'`
  /// (default ephemeral) para que el bottom pane muestre la tasa preview
  /// al cold-start. El primer dígito real del user reemplaza el `'1'`
  /// leading (ver `_appendDigit` que ya cubre el reset state). Backspace
  /// remueve el último char (sin caer debajo de `'0'`); clear vuelve a
  /// `'0'`.
  String _activeExpression = '1';

  /// Último monto válido evaluado. Se preserva si el siguiente parse falla
  /// (ej. la expresión termina en operador transitoriamente "100+"). Sirve
  /// como fallback per spec/design "fallback a último valor válido si
  /// `null`". Arranca en `1` coherente con `_activeExpression = '1'`.
  double _lastValidAmount = 1;

  /// Flag que indica si `_activeExpression` aún es el default ephemeral
  /// `'1'` (que solo está ahí para que el bottom pane muestre la tasa
  /// preview al cold-start). Al primer keystroke real del usuario lo
  /// limpiamos para que el dígito tipeado reemplace el `'1'` placeholder
  /// — el usuario no quiere ver "15" cuando tipea "5". Resetea a `true`
  /// al arrancar y al `clear` (ese vuelve a `'0'`, no a `'1'`, y a partir
  /// de ahí ya es input "real" del user).
  bool _isPristineDefault = true;

  // ─── Rate source state (Tanda 4) ───────────────────────────────────────
  /// Source actualmente seleccionada. Default `paralelo` per spec scenario
  /// "First launch with warm cache". Si en `initState` detectamos cold
  /// offline (sin caché), `_bootstrapRateSource` lo flipea a `manual` y
  /// expone el warning inline (per spec scenario "First launch offline").
  RateSource _source = RateSource.paralelo;

  /// Tasa manual introducida por el usuario. Ephemeral — NO se persiste a
  /// `exchangeRates`. Se aplica a todas las conversiones de la sesión.
  /// `null` mientras el usuario no ingresa nada en el field manual.
  double? _manualRate;

  /// Timestamp del último fetch exitoso. Lo mirroreamos del singleton al
  /// `setState` para forzar re-render del chip cuando cambia.
  DateTime? _lastFetched;

  /// Guard contra doble tap del refresh (per design "Refresh durante refresh
  /// (doble tap) → if (_refreshing) return;").
  bool _refreshing = false;

  /// Controller del field de tasa manual. Lo mantenemos en el state para
  /// preservar el texto a través de rebuilds (ej. al cambiar la pane activa).
  final TextEditingController _manualRateController = TextEditingController();
  final GlobalKey<FormState> _manualFormKey = GlobalKey<FormState>();

  /// `FocusNode` del field de tasa manual. Cuando tiene foco, el keypad
  /// on-screen escribe en `_manualRateController.text` en vez de
  /// `_activeExpression` (per fix "manual rate abre teclado sistema") y se
  /// inhibe el teclado del sistema vía `readOnly: true` en el field.
  late final FocusNode _manualRateFocusNode;

  bool get _isEditingManualRate => _manualRateFocusNode.hasFocus;

  /// Flag que desacopla el "valor visible" del "valor lógico" durante el
  /// primer paint para forzar la animación cold-load del
  /// `AnimatedFlipCounter`. Mientras es `true`, los `numericValue` que se
  /// pasan a las panes son `0.0`; tras el primer frame + 50ms lo flipeamos
  /// a `false` y los counters reciben el valor real → `didUpdateWidget`
  /// detecta el cambio y dispara el rolling 0 → tasa. Si lo dejaramos
  /// siempre con el valor real, el counter monta con el final value y no
  /// anima (la 0.3.4 solo anima en updates post-mount).
  bool _animateInitialPaint = true;

  @override
  void initState() {
    super.initState();
    _manualRateFocusNode = FocusNode()
      ..addListener(() {
        if (!mounted) return;
        // Al ganar foco, el cursor va al final del texto preexistente
        // (ej. user reabrió la calculadora con manual rate previo).
        if (_manualRateFocusNode.hasFocus) {
          final t = _manualRateController.text;
          _manualRateController.selection =
              TextSelection.collapsed(offset: t.length);
        }
        setState(() {});
      });
    _bootstrapCurrencies();
    _bootstrapRateSource();
    // Cold-load animation: el primer paint pasa `0.0` a los counters
    // (vía `_animateInitialPaint = true`); 1 frame + 50ms después
    // flipeamos el flag y los counters reciben el value real → rolling
    // 0 → tasa visible. El delay extra garantiza que el primer paint con
    // value=0 ya se haya commiteado antes del update.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Future<void>.delayed(const Duration(milliseconds: 50), () {
        if (!mounted) return;
        setState(() => _animateInitialPaint = false);
      });
    });
  }

  @override
  void dispose() {
    _manualRateFocusNode.dispose();
    _manualRateController.dispose();
    super.dispose();
  }

  /// Cold-start handling per spec scenario "First launch offline with no
  /// cache": si `DolarApiService` no tiene NI oficial NI paralelo cacheados,
  /// arrancamos en `manual` para que el page renderice algo útil aún sin
  /// network. Si hay caché tibia, mantenemos el default `paralelo` y
  /// mirroreamos `lastFetchTime` al state para que el chip muestre la edad.
  void _bootstrapRateSource() {
    final api = DolarApiService.instance;
    final hasAnyCache = api.oficialRate != null || api.paraleloRate != null;
    if (!hasAnyCache) {
      _source = RateSource.manual;
    }
    _lastFetched = api.lastFetchTime;
  }

  /// Lee currencies desde la DB y arma el set disponible para los pickers.
  /// Si la DB aún no tiene `USD`/`VES` (caso muy edge), construye instancias
  /// in-memory para no bloquear el render — la calculadora debe abrirse aún
  /// sin caché ni network (per spec scenario "First launch offline with no
  /// cache").
  Future<void> _bootstrapCurrencies() async {
    final dbCurrencies =
        await CurrencyService.instance.getAllCurrencies().first ?? const [];

    Currency findByCode(String code) {
      final fromDb = dbCurrencies.where((c) => c.code == code).firstOrNull;
      if (fromDb != null) return fromDb;
      return Currency(
        code: code,
        name: code,
        symbol: code,
        decimalPlaces: code == 'VES' ? 2 : 2,
      );
    }

    // Prepend del orden base, luego el resto en el orden que devuelve la DB
    // (sin duplicados).
    final baseCurrencies = _kCalculatorBaseCodes.map(findByCode).toList();
    final extras = dbCurrencies.where(
      (c) => !_kCalculatorBaseCodes.contains(c.code),
    );

    if (!mounted) return;
    setState(() {
      _availableCurrencies = [...baseCurrencies, ...extras];
      _topCurrency ??= findByCode('USD');
      _bottomCurrency ??= findByCode('VES');
    });
  }

  // ─── Arithmetic helpers (Tanda 3) ──────────────────────────────────────

  /// Evalúa el buffer actual. Si la expresión está malformada (ej. termina
  /// en operador), `evaluateExpression` lanza `ArgumentError` o pisa el
  /// final del operador — capturamos para devolver el último valor válido.
  ///
  /// Side-effect: actualiza `_lastValidAmount` cuando el parse tiene éxito,
  /// para que el próximo fallo caiga al valor anterior (per design "fallback
  /// a último valor válido si `null`").
  double _activeAmount() {
    final expr = _activeExpression;
    if (expr.isEmpty) return _lastValidAmount;
    try {
      final raw = evaluateExpression(expr);
      if (raw.isNaN || raw.isInfinite) return _lastValidAmount;
      _lastValidAmount = raw;
      return raw;
    } on ArgumentError {
      return _lastValidAmount;
    } catch (_) {
      return _lastValidAmount;
    }
  }

  /// Devuelve la tasa cacheada en `DolarApiService.instance` para el
  /// `RateSource` recibido. `null` significa "no hay tasa disponible" — el
  /// caller decide qué mostrar (Tanda 4 mostrará el warning offline).
  ///
  /// Importante:
  ///   * `RateSource.bcv` mapea a `oficialRate` en DolarApi — el "BCV" del
  ///     UI es la tasa oficial publicada por DolarApi como `fuente: oficial`.
  ///   * `RateSource.promedio` requiere AMBAS rates en caché; si una falta,
  ///     devuelve `null`.
  ///   * `RateSource.manual` lee `_manualRate`.
  double? _effectiveRate(RateSource source) {
    final api = DolarApiService.instance;
    switch (source) {
      case RateSource.bcv:
        return api.oficialRate?.promedio;
      case RateSource.paralelo:
        return api.paraleloRate?.promedio;
      case RateSource.promedio:
        final bcv = api.oficialRate?.promedio;
        final par = api.paraleloRate?.promedio;
        if (bcv == null || par == null) return null;
        return (bcv + par) / 2;
      case RateSource.manual:
        return _manualRate;
    }
  }

  /// Convierte `amount` (expresado en la currency activa) a la currency de
  /// la pane convertida, usando la tasa efectiva del source actual.
  ///
  /// Modelo: la tasa siempre se interpreta como `1 USD = N VES` (DolarApi
  /// retorna así). Para currencies USD/EUR/USDT, asumimos pareja USD↔VES y
  /// reusamos la misma tasa — Tanda 4 cambiará el source a EUR cuando
  /// aplique. Para v1 (MVP):
  ///   * top non-VES → bottom VES   : multiplicar por rate
  ///   * top VES     → bottom non-VES: dividir por rate
  ///   * misma currency en ambos panes: rate efectiva = 1
  ///
  /// Si no hay rate disponible o la currency es desconocida, devuelve
  /// `null` y el caller muestra el placeholder.
  double? _convertAmount({
    required double amount,
    required Currency from,
    required Currency to,
  }) {
    if (from.code == to.code) return amount;
    final rate = _effectiveRate(_source);
    if (rate == null || rate <= 0) return null;

    final fromIsVes = from.code == 'VES';
    final toIsVes = to.code == 'VES';

    if (!fromIsVes && toIsVes) {
      // USD/EUR/USDT → VES
      return amount * rate;
    }
    if (fromIsVes && !toIsVes) {
      // VES → USD/EUR/USDT
      return amount / rate;
    }
    // Caso non-VES ↔ non-VES (ej. USD ↔ EUR): v1 no expone source EUR
    // distinto, así que asumimos pareja vía VES.
    return amount;
  }

  /// Formato locale-aware del monto en pane. Usa `NumberFormat` con la
  /// locale actual (la misma que `currentDecimalSep` lee). `decimalDigits`
  /// se ajusta a la currency cuando es la pane convertida.
  String _formatAmount(double value, {required Currency currency}) {
    if (value.isNaN || value.isInfinite) return '—';
    final formatter = NumberFormat.decimalPatternDigits(
      locale: Intl.defaultLocale,
      decimalDigits: currency.decimalPlaces,
    );
    return formatter.format(value);
  }

  /// Display value para la pane indicada. Para la pane activa devolvemos el
  /// monto evaluado del buffer (con fallback a último valor válido). Para
  /// la convertida, aplicamos la tasa.
  String _displayValueFor({
    required bool top,
    required Currency topCurrency,
    required Currency bottomCurrency,
  }) {
    final activeCurrency = _topIsActive ? topCurrency : bottomCurrency;
    final convertedCurrency = _topIsActive ? bottomCurrency : topCurrency;
    final isActivePane = top == _topIsActive;

    final activeValue = _activeAmount();

    if (isActivePane) {
      return _formatAmount(activeValue, currency: activeCurrency);
    }

    final converted = _convertAmount(
      amount: activeValue,
      from: activeCurrency,
      to: convertedCurrency,
    );
    if (converted == null) return '—';
    return _formatAmount(converted, currency: convertedCurrency);
  }

  /// Valor numérico crudo para la pane indicada — alimenta el rolling
  /// digits del `AnimatedFlipCounter` en la pane pasiva. Devuelve `null`
  /// cuando no hay tasa disponible (pane pasiva sin convert), en cuyo
  /// caso la pane cae al `Text` plano con el placeholder `'—'`.
  double? _numericValueFor({
    required bool top,
    required Currency topCurrency,
    required Currency bottomCurrency,
  }) {
    final activeCurrency = _topIsActive ? topCurrency : bottomCurrency;
    final convertedCurrency = _topIsActive ? bottomCurrency : topCurrency;
    final isActivePane = top == _topIsActive;

    final activeValue = _activeAmount();
    if (isActivePane) return activeValue;

    return _convertAmount(
      amount: activeValue,
      from: activeCurrency,
      to: convertedCurrency,
    );
  }

  // ─── Keypad handler (Tanda 3) ──────────────────────────────────────────

  /// Mapea `KeypadKey` a mutación del buffer. Reglas:
  ///   * Dígitos: si el buffer es `'0'` (reset state) o termina en
  ///     operador con un `0` solitario tras el operador, reemplazamos; si
  ///     no, append.
  ///   * Decimal: append solo si la última "número-token" no contiene ya
  ///     un separador. Usa `currentDecimalSep` para coincidir con el
  ///     keypad render.
  ///   * `+`/`-`: si el buffer termina en otro operador, reemplazamos ese
  ///     operador (evita "100+-"). Si está vacío, no se inserta operador.
  ///   * Backspace: remueve último char; si queda vacío, vuelve a `'0'`.
  ///   * Clear: reset a `'0'` y `_lastValidAmount = 0`.
  ///   * Equals: re-evaluar y "colapsar" el buffer al resultado (para que
  ///     siguientes digits empiecen una expresión nueva).
  void _onKey(KeypadKey key) {
    final sep = currentDecimalSep;

    // Si el field de tasa manual tiene foco, el keypad escribe ahí en vez
    // del buffer aritmético. Sub-handler dedicado para no inflar el switch
    // principal.
    if (_isEditingManualRate) {
      _onKeyForManualRate(key, sep);
      return;
    }

    setState(() {
      // Polish: el `'1'` default es ephemeral; en cuanto el user toca una
      // tecla "de input" (digit/decimal/operator) lo limpiamos a `'0'`
      // para que el primer dígito tipeado lo reemplace via la regla
      // existente de `_appendDigit("0")` → reemplazar. Backspace, clear y
      // equals NO necesitan este reset (clear ya snapea a `'0'`,
      // backspace sobre `'1'` cae a `'0'` natural, y equals con `'1'` da
      // `1` y se sale del estado pristine).
      if (_isPristineDefault &&
          key != KeypadKey.clear &&
          key != KeypadKey.backspace &&
          key != KeypadKey.equals) {
        _activeExpression = '0';
        _lastValidAmount = 0;
      }
      _isPristineDefault = false;

      switch (key) {
        case KeypadKey.clear:
          _activeExpression = '0';
          _lastValidAmount = 0;
          break;

        case KeypadKey.backspace:
          if (_activeExpression.length <= 1) {
            _activeExpression = '0';
          } else {
            _activeExpression = _activeExpression.substring(
              0,
              _activeExpression.length - 1,
            );
            if (_activeExpression.isEmpty) _activeExpression = '0';
          }
          break;

        case KeypadKey.plus:
          _appendOperator('+');
          break;

        case KeypadKey.minus:
          _appendOperator('-');
          break;

        case KeypadKey.decimal:
          _appendDecimal(sep);
          break;

        case KeypadKey.equals:
          // Re-evaluar y colapsar: si el parse tiene éxito, el buffer se
          // sustituye por la representación canónica del número (con `.`
          // como decimal porque el engine espera notación standard).
          final value = _activeAmount();
          if (value.isFinite) {
            _activeExpression = _canonicalNumber(value);
          }
          break;

        case KeypadKey.digit0:
        case KeypadKey.digit1:
        case KeypadKey.digit2:
        case KeypadKey.digit3:
        case KeypadKey.digit4:
        case KeypadKey.digit5:
        case KeypadKey.digit6:
        case KeypadKey.digit7:
        case KeypadKey.digit8:
        case KeypadKey.digit9:
          _appendDigit(_digitChar(key));
          break;
      }
    });
  }

  /// Sub-handler del keypad cuando el field de tasa manual tiene foco.
  /// Escribe en `_manualRateController.text` en vez de `_activeExpression`.
  /// Operadores (`+`/`-`) y `=` se ignoran (no tiene sentido sumar tasas).
  /// Cada cambio re-parsea a `double?` (normalizando `,`→`.`); si el parse
  /// falla, el `_manualRate` previo se mantiene.
  void _onKeyForManualRate(KeypadKey key, String sep) {
    String text = _manualRateController.text;

    switch (key) {
      case KeypadKey.plus:
      case KeypadKey.minus:
      case KeypadKey.equals:
        // Sumar tasas no tiene sentido — ignorar.
        return;

      case KeypadKey.clear:
        text = '';
        break;

      case KeypadKey.backspace:
        if (text.isNotEmpty) {
          text = text.substring(0, text.length - 1);
        }
        break;

      case KeypadKey.decimal:
        // Solo un separador decimal por número. Aceptamos tanto `,` como `.`
        // pre-existente.
        if (!text.contains(sep) && !text.contains('.') && !text.contains(',')) {
          text = text.isEmpty ? '0$sep' : '$text$sep';
        }
        break;

      case KeypadKey.digit0:
      case KeypadKey.digit1:
      case KeypadKey.digit2:
      case KeypadKey.digit3:
      case KeypadKey.digit4:
      case KeypadKey.digit5:
      case KeypadKey.digit6:
      case KeypadKey.digit7:
      case KeypadKey.digit8:
      case KeypadKey.digit9:
        text = '$text${_digitChar(key)}';
        break;
    }

    _manualRateController.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );

    final normalized = text.replaceAll(',', '.').trim();
    final parsed = double.tryParse(normalized);
    setState(() {
      if (parsed != null && parsed > 0) {
        _manualRate = parsed;
      } else if (text.isEmpty) {
        // Clear total → limpiamos también `_manualRate` para que el rate
        // explicit/conversiones reflejen "sin tasa".
        _manualRate = null;
      }
      // Parse falla con texto no vacío (ej. "0," transitorio) → mantener
      // el `_manualRate` anterior.
    });
  }

  String _digitChar(KeypadKey key) {
    switch (key) {
      case KeypadKey.digit0:
        return '0';
      case KeypadKey.digit1:
        return '1';
      case KeypadKey.digit2:
        return '2';
      case KeypadKey.digit3:
        return '3';
      case KeypadKey.digit4:
        return '4';
      case KeypadKey.digit5:
        return '5';
      case KeypadKey.digit6:
        return '6';
      case KeypadKey.digit7:
        return '7';
      case KeypadKey.digit8:
        return '8';
      case KeypadKey.digit9:
        return '9';
      // Casos no-digit nunca llegan acá; el switch del caller los filtra.
      default:
        return '';
    }
  }

  void _appendDigit(String digit) {
    final expr = _activeExpression;
    // Si el buffer es solo "0" y entra un dígito → reemplazar (evita "07").
    if (expr == '0') {
      _activeExpression = digit;
      return;
    }
    // Si el último token-número es exactamente "0" (ej. "100+0"), también
    // reemplazamos ese cero.
    if (expr.length >= 2 &&
        expr[expr.length - 1] == '0' &&
        _isOperatorChar(expr[expr.length - 2])) {
      _activeExpression = '${expr.substring(0, expr.length - 1)}$digit';
      return;
    }
    _activeExpression = '$expr$digit';
  }

  void _appendOperator(String op) {
    final expr = _activeExpression;
    if (expr.isEmpty) {
      _activeExpression = '0$op';
      return;
    }
    final last = expr[expr.length - 1];
    if (_isOperatorChar(last)) {
      // Reemplazar el operador anterior.
      _activeExpression = '${expr.substring(0, expr.length - 1)}$op';
      return;
    }
    _activeExpression = '$expr$op';
  }

  void _appendDecimal(String sep) {
    final expr = _activeExpression;
    // Buscar el último número-token: chars desde el último operador (excl).
    int startOfLastNumber = 0;
    for (int i = expr.length - 1; i >= 0; i--) {
      if (_isOperatorChar(expr[i])) {
        startOfLastNumber = i + 1;
        break;
      }
    }
    final lastNumber = expr.substring(startOfLastNumber);
    if (lastNumber.contains(sep) || lastNumber.contains('.')) return;
    if (lastNumber.isEmpty) {
      // Después de un operador y sin dígito aún → "0,"
      _activeExpression = '${expr}0$sep';
      return;
    }
    _activeExpression = '$expr$sep';
  }

  bool _isOperatorChar(String c) => c == '+' || c == '-' || c == '×' || c == '÷';

  /// Representación canónica (sin trailing zeros innecesarios) que
  /// `evaluateExpression` puede re-parsear. Usa punto como decimal porque
  /// el engine espera notación standard; el render UI sigue usando
  /// `currentDecimalSep` vía `_formatAmount`.
  String _canonicalNumber(double v) {
    if (v == v.truncateToDouble()) return v.toInt().toString();
    return v.toString();
  }

  // ─── Pane handlers (Tanda 2) ───────────────────────────────────────────

  void _onTopTap() {
    // Tap en una currency pane → si el manual rate field tenía foco, soltalo
    // para que el keypad vuelva a escribir en `_activeExpression`.
    if (_manualRateFocusNode.hasFocus) _manualRateFocusNode.unfocus();
    if (_topIsActive) return;
    setState(() => _topIsActive = true);
  }

  void _onBottomTap() {
    if (_manualRateFocusNode.hasFocus) _manualRateFocusNode.unfocus();
    if (!_topIsActive) return;
    setState(() => _topIsActive = false);
  }

  void _onTopCurrencyChanged(Currency next) {
    if (next.code == _topCurrency?.code) return;
    setState(() => _topCurrency = next);
  }

  void _onBottomCurrencyChanged(Currency next) {
    if (next.code == _bottomCurrency?.code) return;
    setState(() => _bottomCurrency = next);
  }

  /// Swap top↔bottom currencies + alterna pane activa. La expresión activa
  /// (Tanda 3) se mantiene en su pane: como el `_topIsActive` se invierte
  /// junto con las currencies, el monto que el usuario tipeó queda
  /// "viajando" con su pane original (per spec scenario "Swap inverts
  /// conversion": "further keystrokes target the new top pane").
  void _onSwap() {
    setState(() {
      final temp = _topCurrency;
      _topCurrency = _bottomCurrency;
      _bottomCurrency = temp;
      _topIsActive = !_topIsActive;
    });
  }

  // ─── Rate source handlers (Tanda 4) ────────────────────────────────────

  /// Avanza al siguiente `RateSource` en el ciclo fijo
  /// `bcv → paralelo → promedio → manual → bcv …` (per spec REQ-CALC-4).
  /// Sincrónico — no dispara red, solo lee de la caché del singleton.
  void _onCycleSource() {
    setState(() {
      _source = _nextSource(_source);
    });
    // Defensivo: si el cycle nos saca de `manual` mientras el field tenía
    // foco, soltarlo para que el keypad reanude escritura aritmética.
    if (_source != RateSource.manual && _manualRateFocusNode.hasFocus) {
      _manualRateFocusNode.unfocus();
    }
  }

  RateSource _nextSource(RateSource current) {
    switch (current) {
      case RateSource.bcv:
        return RateSource.paralelo;
      case RateSource.paralelo:
        return RateSource.promedio;
      case RateSource.promedio:
        return RateSource.manual;
      case RateSource.manual:
        return RateSource.bcv;
    }
  }

  /// El chip muestra `Paralelo (USDT)` cuando la pane activa-USD es USDT y
  /// el source es uno de los 3 cacheados (per spec scenario "USDT label").
  /// Tomamos como referencia la pane activa: si el usuario tappea VES como
  /// activa pero la otra es USDT, el modelo de tasa sigue siendo USDT/VES,
  /// así que también aplicamos el label.
  bool _shouldForceUsdtLabel() {
    final top = _topCurrency;
    final bottom = _bottomCurrency;
    if (top == null || bottom == null) return false;
    return top.code == 'USDT' || bottom.code == 'USDT';
  }

  /// Abre el `ExchangeRateFormDialog` pre-fillado con `_manualRate` (per
  /// spec REQ-CALC-5 scenario "Persist via existing dialog"). El diálogo usa
  /// el flujo de persistencia existente — la calculadora NUNCA escribe
  /// directamente a la DB.
  Future<void> _onSaveManualRate() async {
    final rate = _manualRate;
    if (rate == null || rate <= 0) return;

    // Antes de abrir el dialog: soltamos el foco del manual rate field para
    // que el dialog no quede compitiendo con el keypad on-screen.
    if (_manualRateFocusNode.hasFocus) _manualRateFocusNode.unfocus();

    // Pre-fill: pasamos la currency activa-no-VES (USD por default) para que
    // el diálogo arranque con currency seleccionada coherente.
    Currency? prefillCurrency;
    final top = _topCurrency;
    final bottom = _bottomCurrency;
    if (top != null && top.code != 'VES') {
      prefillCurrency = top;
    } else if (bottom != null && bottom.code != 'VES') {
      prefillCurrency = bottom;
    }

    await showExchangeRateFormDialog(
      context,
      ExchangeRateFormDialog(
        currency: prefillCurrency,
        initialRate: rate,
      ),
    );
  }

  /// Refresh real (per task 4.7 + spec REQ-CALC-6). Llama
  /// `DolarApiService.fetchAll()` (USD + EUR), actualiza `_lastFetched` en
  /// éxito, snackbar non-blocking en falla. Guard contra doble tap.
  Future<void> _onRefresh() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);

    final api = DolarApiService.instance;
    final beforeFetch = api.lastFetchTime;

    try {
      await api.fetchAll();
    } catch (_) {
      // El service ya hace catch internamente; este try es defensivo.
    }

    final afterFetch = api.lastFetchTime;
    final didUpdate = afterFetch != null && afterFetch != beforeFetch;

    if (!mounted) return;
    setState(() {
      _lastFetched = afterFetch;
      _refreshing = false;
    });

    if (!didUpdate) {
      final messenger = ScaffoldMessenger.of(context);
      messenger.showSnackBar(
        SnackBar(
          content: Text(Translations.of(context).calculator.refresh.error),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  /// `true` cuando NO hay forma de mostrar una tasa: ningún source devuelve
  /// algo (ni manual, ni caché). Disparado en cold-offline.
  bool _shouldShowNoRateWarning() {
    final api = DolarApiService.instance;
    final hasAnyCache = api.oficialRate != null || api.paraleloRate != null;
    return !hasAnyCache && _manualRate == null;
  }

  // ─── Copy bottom amount (polish) ───────────────────────────────────────

  /// Copia al clipboard el monto de la pane convertida (la **NO** activa)
  /// como `"<symbol> <formatted>"` (ej. `"Bs. 484,74"`). SnackBar floating
  /// para feedback. El payload incluye el símbolo de la currency destino
  /// — no el código ISO — porque es lo que el user ve en pantalla.
  Future<void> _onCopyBottom() async {
    final top = _topCurrency;
    final bottom = _bottomCurrency;
    if (top == null || bottom == null) return;

    // La pane convertida es la NO-activa: si top es activa, la convertida
    // es bottom y viceversa.
    final convertedCurrency = _topIsActive ? bottom : top;
    final value = _numericValueFor(
      top: !_topIsActive,
      topCurrency: top,
      bottomCurrency: bottom,
    );
    final formatted = (value == null || !value.isFinite)
        ? '—'
        : _formatAmount(value, currency: convertedCurrency);

    final text = '${convertedCurrency.symbol} $formatted';

    await Clipboard.setData(ClipboardData(text: text));

    if (!mounted) return;
    final t = Translations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(t.calculator.copy.snackbar(value: text)),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // ─── Share pipeline (Tanda 5) ──────────────────────────────────────────

  /// `GlobalKey` del `RepaintBoundary` que envuelve al `ShareCard`. El page
  /// monta el card SIEMPRE en su árbol bajo `Offstage(offstage: true)` para
  /// que el render layer esté caliente y la captura sea instantánea (per
  /// design § "Render del share card off-screen").
  final GlobalKey _shareCardKey = GlobalKey();

  /// Guard contra doble tap del share button mientras el render asíncrono
  /// está en vuelo.
  bool _sharing = false;

  /// Resuelve el label de la fuente para el share card / payload textual.
  /// Reusa la lógica del chip (`Paralelo (USDT)` cuando aplique) — pero
  /// reimplementada acá para no acoplar el chip con el page.
  String _resolveSourceLabel(Translations t) {
    if (_shouldForceUsdtLabel() && _source != RateSource.manual) {
      return t.calculator.source.usdt_label;
    }
    switch (_source) {
      case RateSource.bcv:
        return t.calculator.source.bcv;
      case RateSource.paralelo:
        return t.calculator.source.paralelo;
      case RateSource.promedio:
        return t.calculator.source.promedio;
      case RateSource.manual:
        return t.calculator.source.manual;
    }
  }

  /// Timestamp formateado `27/04/2026 14:23` (locale-aware) para el share
  /// card y el payload. Si no hay fetch aún, devuelve el placeholder
  /// estandarizado del chip (`—`).
  String _resolveTimestampLabel(Translations t) {
    final fetched = _lastFetched;
    if (fetched == null) return t.calculator.source.updated_unknown;
    final formatter = DateFormat.yMd(Intl.defaultLocale).add_Hm();
    return formatter.format(fetched);
  }

  /// Construye el payload textual del share. Formato (per design §
  /// "Render del share card" + spec REQ-CALC-7):
  ///   ```
  ///   <fromCode> <fromAmount> = <toCode> <toAmount>
  ///   <sourceLabel> · <timestamp>
  ///   <footer>
  ///   ```
  /// El primer renglón usa los códigos ISO (USD/VES/EUR/USDT) en vez de
  /// símbolos para evitar dependencia de glyphs raros en clipboards.
  String _buildPlainTextPayload(BuildContext context) {
    final t = Translations.of(context);
    final top = _topCurrency;
    final bottom = _bottomCurrency;
    if (top == null || bottom == null) {
      return t.calculator.share.footer;
    }

    final fromCurrency = _topIsActive ? top : bottom;
    final toCurrency = _topIsActive ? bottom : top;

    final fromAmount = _activeAmount();
    final convertedAmount =
        _convertAmount(amount: fromAmount, from: fromCurrency, to: toCurrency);

    final fromText = _formatAmount(fromAmount, currency: fromCurrency);
    final toText = convertedAmount == null
        ? '—'
        : _formatAmount(convertedAmount, currency: toCurrency);

    final sourceLabel = _resolveSourceLabel(t);
    final timestamp = _resolveTimestampLabel(t);
    final separator = t.calculator.share.equals_separator;

    return [
      '${fromCurrency.code} $fromText $separator ${toCurrency.code} $toText',
      '$sourceLabel · $timestamp',
      t.calculator.share.footer,
    ].join('\n');
  }

  /// Handler del share button (task 5.5). Flujo:
  ///   1. Render del `ShareCard` montado off-screen vía
  ///      `renderShareCard(_shareCardKey, ...)`. `pixelRatio` cap a 2× en
  ///      pantallas chicas (`shortestSide < 360`), 3× sino — per design.
  ///   2. Si el render produce `XFile`, share via `SharePlus.instance.share`
  ///      con file + payload textual.
  ///   3. Si el render falla (devuelve `null` o lanza), share solo el
  ///      payload textual. SIN toast (per spec REQ-CALC-7 "no error toast").
  ///   4. Cualquier excepción del flujo entero se loguea a
  ///      `Logger.printDebug` y degrada a fallback de texto.
  Future<void> _onShare() async {
    if (_sharing) return;
    setState(() => _sharing = true);

    final payload = _buildPlainTextPayload(context);
    final shortest = MediaQuery.of(context).size.shortestSide;
    final pixelRatio = shortest < 360 ? 2.0 : 3.0;
    final t = Translations.of(context);
    final subject = t.calculator.share.subject;

    try {
      final xFile = await renderShareCard(
        _shareCardKey,
        pixelRatio: pixelRatio,
      );

      if (xFile != null) {
        await SharePlus.instance.share(
          ShareParams(text: payload, subject: subject, files: [xFile]),
        );
      } else {
        // Fallback silencioso: sin toast, solo texto plano.
        await SharePlus.instance.share(
          ShareParams(text: payload, subject: subject),
        );
      }
    } catch (e, st) {
      Logger.printDebug('Calculator share failed: $e\n$st');
      // Último resort: re-intentar texto plano. Si esto también revienta,
      // ya lo logueamos arriba; no propagamos al user.
      try {
        await SharePlus.instance.share(
          ShareParams(text: payload, subject: subject),
        );
      } catch (_) {
        // Silent — per spec scenario "Render failure falls back to text"
        // no surface error toast.
      }
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);

    final topCurrency = _topCurrency;
    final bottomCurrency = _bottomCurrency;
    final currenciesReady = topCurrency != null && bottomCurrency != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(t.calculator.title),
        actions: [
          Semantics(
            button: true,
            label: t.calculator.refresh.a11y,
            child: IconButton(
              icon: _refreshing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh_rounded),
              tooltip: t.calculator.refresh.a11y,
              onPressed: _refreshing ? null : _onRefresh,
            ),
          ),
          Semantics(
            button: true,
            label: t.calculator.share.action_a11y,
            child: IconButton(
              icon: _sharing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.share_outlined),
              tooltip: t.calculator.share.action_a11y,
              onPressed: (_sharing || !currenciesReady) ? null : _onShare,
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: !currenciesReady
            ? const Center(child: CircularProgressIndicator())
            : Stack(
                children: [
                  // Polish: el body ahora es Column en vez de un único
                  // ListView raíz. Esto deja al `CalculatorKeypad`
                  // anclado al fondo (no scrollea, no flota como un item
                  // de lista), mientras que la parte refrescable +
                  // scrolleable (panes, swap, chip, source extras, rate
                  // explicit) vive en `Expanded(RefreshIndicator(ListView))`.
                  Column(
                    children: [
                      Expanded(
                        child: RefreshIndicator(
                          onRefresh: _onRefresh,
                          child: ListView(
                            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                            physics: const AlwaysScrollableScrollPhysics(),
                            children: [
                              CurrencyAmountPane(
                                currency: topCurrency,
                                displayValue: _displayValueFor(
                                  top: true,
                                  topCurrency: topCurrency,
                                  bottomCurrency: bottomCurrency,
                                ),
                                numericValue: _animateInitialPaint
                                    ? 0.0
                                    : _numericValueFor(
                                        top: true,
                                        topCurrency: topCurrency,
                                        bottomCurrency: bottomCurrency,
                                      ),
                                isActive: _topIsActive,
                                availableCurrencies: _availableCurrencies,
                                onCurrencyChanged: _onTopCurrencyChanged,
                                onTap: _onTopTap,
                              ),
                              _SwapButton(
                                onPressed: _onSwap,
                                semanticsLabel: t.calculator.swap.a11y,
                              ),
                              CurrencyAmountPane(
                                currency: bottomCurrency,
                                displayValue: _displayValueFor(
                                  top: false,
                                  topCurrency: topCurrency,
                                  bottomCurrency: bottomCurrency,
                                ),
                                numericValue: _animateInitialPaint
                                    ? 0.0
                                    : _numericValueFor(
                                        top: false,
                                        topCurrency: topCurrency,
                                        bottomCurrency: bottomCurrency,
                                      ),
                                isActive: !_topIsActive,
                                availableCurrencies: _availableCurrencies,
                                onCurrencyChanged: _onBottomCurrencyChanged,
                                onTap: _onBottomTap,
                                trailing: Semantics(
                                  button: true,
                                  label: t.calculator.copy.a11y,
                                  child: IconButton(
                                    icon: const Icon(
                                      Icons.content_copy_outlined,
                                      size: 20,
                                    ),
                                    tooltip: t.calculator.copy.tooltip,
                                    onPressed: _onCopyBottom,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              _RateExplicitBlock(
                                topCurrency: topCurrency,
                                bottomCurrency: bottomCurrency,
                                source: _source,
                                effectiveRate: _effectiveRate(_source),
                                lastFetched: _lastFetched,
                                formatAmount: _formatAmount,
                              ),
                              const SizedBox(height: 12),
                              Center(
                                child: RateSourceChip(
                                  source: _source,
                                  lastFetched: _lastFetched,
                                  onTap: _onCycleSource,
                                  forceUsdtLabel: _shouldForceUsdtLabel(),
                                ),
                              ),
                              if (_source == RateSource.manual) ...[
                                const SizedBox(height: 12),
                                _ManualRateField(
                                  controller: _manualRateController,
                                  focusNode: _manualRateFocusNode,
                                  formKey: _manualFormKey,
                                  labelText: t.calculator.manual.field_label,
                                  hintText: t.calculator.manual.field_hint(
                                    currency:
                                        (_topCurrency?.code != 'VES'
                                                ? _topCurrency?.code
                                                : _bottomCurrency?.code) ??
                                            'USD',
                                  ),
                                  invalidText:
                                      t.calculator.manual.field_invalid,
                                ),
                                const SizedBox(height: 8),
                                Align(
                                  alignment: AlignmentDirectional.centerEnd,
                                  child: TextButton.icon(
                                    icon: const Icon(
                                      Icons.save_outlined,
                                      size: 18,
                                    ),
                                    label: Text(t.calculator.manual.save_link),
                                    onPressed:
                                        (_manualRate != null && _manualRate! > 0)
                                            ? _onSaveManualRate
                                            : null,
                                  ),
                                ),
                              ],
                              if (_shouldShowNoRateWarning()) ...[
                                const SizedBox(height: 12),
                                InlineInfoCard(
                                  text: t.calculator.warn.no_rate,
                                  mode: InlineInfoCardMode.warn,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      // Keypad fijo al fondo, fuera del scroll (per polish
                      // §1: no debe haber gap entre la última fila y el
                      // bottom edge del Scaffold).
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                        child: CalculatorKeypad(onKey: _onKey),
                      ),
                    ],
                  ),
                  // ShareCard montado off-screen (per design § "Render del
                  // share card off-screen"): `Offstage` lo saca del layout
                  // pero `RepaintBoundary` mantiene la layer pintada y lista
                  // para captura via `_shareCardKey.currentContext`. Se
                  // alimenta con los mismos derivados que el body normal
                  // para que cualquier captura refleje el estado actual.
                  Offstage(
                    offstage: true,
                    child: RepaintBoundary(
                      key: _shareCardKey,
                      child: Builder(
                        builder: (ctx) {
                          final fromCurrency =
                              _topIsActive ? topCurrency : bottomCurrency;
                          final toCurrency =
                              _topIsActive ? bottomCurrency : topCurrency;
                          final fromAmount = _activeAmount();
                          final converted = _convertAmount(
                            amount: fromAmount,
                            from: fromCurrency,
                            to: toCurrency,
                          );
                          return ShareCard(
                            fromCurrency: fromCurrency,
                            toCurrency: toCurrency,
                            fromAmountText: _formatAmount(
                              fromAmount,
                              currency: fromCurrency,
                            ),
                            toAmountText: converted == null
                                ? '—'
                                : _formatAmount(
                                    converted,
                                    currency: toCurrency,
                                  ),
                            sourceLabel: _resolveSourceLabel(t),
                            timestampLabel: _resolveTimestampLabel(t),
                            equalsSeparator:
                                t.calculator.share.equals_separator,
                            footerText: t.calculator.share.footer,
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

/// Round swap button entre las dos panes (per proposal "Round swap button
/// between panes"). Decisión de iconografía: `Icons.swap_vert` — coherente
/// con el eje vertical de las panes apiladas (per design.md § "No-decisiones:
/// iconografía exacta del swap button"). Usa `colorScheme.primary` para
/// matchear el accent dinámico de wallex (mismo patrón que el FAB de
/// `transactions.page.dart`).
class _SwapButton extends StatelessWidget {
  const _SwapButton({required this.onPressed, required this.semanticsLabel});

  final VoidCallback onPressed;
  final String semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Center(
        child: Semantics(
          button: true,
          label: semanticsLabel,
          child: Material(
            color: colors.primary,
            shape: const CircleBorder(),
            elevation: 2,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onPressed,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Icon(Icons.swap_vert, color: colors.onPrimary),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Field inline para la tasa manual (Tanda 4, task 4.5). Validator rechaza
/// `null`, vacío, no-numérico o ≤0; el page mantiene `_manualRate` ephemeral
/// y NUNCA escribe a `exchangeRates` (per spec REQ-CALC-5). Usa
/// `colorScheme.*` — sin colores hardcodeados.
class _ManualRateField extends StatelessWidget {
  const _ManualRateField({
    required this.controller,
    required this.focusNode,
    required this.formKey,
    required this.labelText,
    required this.hintText,
    required this.invalidText,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final GlobalKey<FormState> formKey;
  final String labelText;
  final String hintText;
  final String invalidText;

  @override
  Widget build(BuildContext context) {
    return Form(
      key: formKey,
      child: TextFormField(
        controller: controller,
        focusNode: focusNode,
        // `readOnly: true` + `showCursor: true` → el field NO levanta el
        // teclado del sistema (Gboard) al tappear, pero sí muestra cursor y
        // recibe foco. El keypad on-screen de la calculadora escribe el
        // texto vía `_onKeyForManualRate` en `_CalculatorPageState`.
        readOnly: true,
        showCursor: true,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        decoration: InputDecoration(
          labelText: labelText,
          hintText: hintText,
          border: const OutlineInputBorder(),
          prefixIcon: const Icon(Icons.tune_rounded),
        ),
        validator: (raw) {
          final v = (raw ?? '').replaceAll(',', '.').trim();
          if (v.isEmpty) return invalidText;
          final parsed = double.tryParse(v);
          if (parsed == null || parsed <= 0) return invalidText;
          return null;
        },
      ),
    );
  }
}

/// Bloque info-only debajo del bottom pane (polish §3). Dos líneas:
///   * Línea 1: tasa unitaria explícita (`<symbolFrom>1 = <symbolTo>484,74`)
///     en `titleMedium` weight 500. La currency origen es la **non-VES** —
///     la tasa siempre se modela como `1 USD = N VES` así que invertimos
///     para que el `1` quede en la pareja USD/EUR/USDT, no en el VES.
///   * Línea 2: timestamp largo (`Actualizado 27 abr. de 2026, 8:00 p. m.`)
///     en `bodySmall` color `onSurfaceVariant`. Si `lastFetched == null`
///     muestra el placeholder `timestamp_unknown`. Si `source == manual`
///     muestra `timestamp_manual`.
///
/// No es clickeable. No hay colores hardcodeados — todo del `colorScheme`.
class _RateExplicitBlock extends StatelessWidget {
  const _RateExplicitBlock({
    required this.topCurrency,
    required this.bottomCurrency,
    required this.source,
    required this.effectiveRate,
    required this.lastFetched,
    required this.formatAmount,
  });

  final Currency topCurrency;
  final Currency bottomCurrency;
  final RateSource source;
  final double? effectiveRate;
  final DateTime? lastFetched;
  final String Function(double value, {required Currency currency}) formatAmount;

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    // La tasa siempre se modela como `1 <USD/EUR/USDT> = N VES`. La
    // pareja origen es la non-VES (si existe en alguno de los panes); si
    // ambas son non-VES o ambas son VES caemos al patrón `top → bottom`.
    Currency from;
    Currency to;
    if (topCurrency.code == 'VES' && bottomCurrency.code != 'VES') {
      from = bottomCurrency;
      to = topCurrency;
    } else if (bottomCurrency.code == 'VES' &&
        topCurrency.code != 'VES') {
      from = topCurrency;
      to = bottomCurrency;
    } else {
      // Ambas VES o ambas non-VES — fallback al orden visual top→bottom.
      from = topCurrency;
      to = bottomCurrency;
    }

    // Usamos el símbolo de la currency (Bs., $, €, ...) — fallback al code
    // si symbol está vacío.
    String sym(Currency c) => c.symbol.isNotEmpty ? c.symbol : c.code;

    final String line1Text;
    if (effectiveRate == null || !effectiveRate!.isFinite || from.code == to.code) {
      // Sin tasa o panes con misma currency: línea 1 cae al placeholder
      // estándar.
      line1Text = '${sym(from)} 1 = ${sym(to)} —';
    } else {
      // Usamos el `formatAmount` del page para mantener el mismo formato
      // locale-aware (decimal places, separators) que ya usan las panes.
      final formatted = formatAmount(effectiveRate!, currency: to);
      line1Text = t.calculator.rate_explicit.format(
        from: sym(from),
        to: sym(to),
        amount: formatted,
      );
    }

    final String line2Text;
    if (source == RateSource.manual) {
      line2Text = t.calculator.rate_explicit.timestamp_manual;
    } else if (lastFetched == null) {
      line2Text = t.calculator.rate_explicit.timestamp_unknown;
    } else {
      final formatter =
          DateFormat.yMMMd(Intl.defaultLocale).add_jm();
      line2Text = t.calculator.rate_explicit.timestamp_long(
        date: formatter.format(lastFetched!),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            line1Text,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(
              color: colors.onSurface,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            line2Text,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
