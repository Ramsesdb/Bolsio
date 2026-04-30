import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:bolsio/core/presentation/widgets/card_with_header.dart';
import 'package:bolsio/core/services/dolar_api_service.dart';
import 'package:bolsio/core/services/rate_providers/rate_provider_manager.dart';

/// Selector visual de tasa de cambio para usar en una transaccion multi-divisa.
///
/// Muestra 3 opciones: BCV, Paralelo, Manual.
/// - BCV / Paralelo: muestran la tasa cacheada actual (via DolarApiService.instance) y la fecha del fetch.
/// - Manual: revela un TextField numerico para que el usuario ingrese la tasa.
///
/// Callback [onChanged] se dispara cada vez que cambia la seleccion
/// o el monto manual (debounced 500ms para evitar churn).
class ExchangeRateSelector extends StatefulWidget {
  /// Moneda origen (tipicamente USD)
  final String fromCurrency;

  /// Moneda destino (tipicamente VES)
  final String toCurrency;

  /// Tasa inicial (opcional, para edicion de TX existente). Si no null, se selecciona "Manual" por default.
  final double? initialRate;

  /// Source inicial ('bcv'|'paralelo'|'manual'|'auto')
  final String? initialSource;

  /// Callback cuando cambia la seleccion.
  final void Function(double rate, String source) onChanged;

  const ExchangeRateSelector({
    super.key,
    required this.fromCurrency,
    required this.toCurrency,
    this.initialRate,
    this.initialSource,
    required this.onChanged,
  });

  @override
  State<ExchangeRateSelector> createState() => _ExchangeRateSelectorState();
}

enum _RateSource { bcv, paralelo, manual }

class _ExchangeRateSelectorState extends State<ExchangeRateSelector> {
  late _RateSource _selected;
  final TextEditingController _manualController = TextEditingController();
  Timer? _debounce;

  bool _isFetchingBcv = false;
  bool _isFetchingParalelo = false;

  @override
  void initState() {
    super.initState();

    // Determine initial selection
    if (widget.initialSource == 'manual') {
      _selected = _RateSource.manual;
    } else if (widget.initialSource == 'paralelo') {
      _selected = _RateSource.paralelo;
    } else if (widget.initialRate != null &&
        widget.initialSource == null) {
      // Existing TX with rate but no source tag -> treat as manual
      _selected = _RateSource.manual;
    } else {
      _selected = _RateSource.bcv;
    }

    if (widget.initialRate != null && widget.initialRate! > 0) {
      // initialRate is stored in "1 fromCurrency = X toCurrency" direction
      // (inverted). Convert back to human-friendly for the text field.
      _manualController.text = (1.0 / widget.initialRate!).toStringAsFixed(4);
    }

    // Fire initial callback after build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fireCallback();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _manualController.dispose();
    super.dispose();
  }

  /// Raw API rate in "VES per 1 foreign unit" direction (e.g. 479.78).
  /// Used for display only.
  double? get _bcvDisplayRate => _displayRateFor(widget.toCurrency, 'oficial');
  double? get _paraleloDisplayRate => _displayRateFor(widget.toCurrency, 'paralelo');
  DateTime? get _lastFetch => DolarApiService.instance.lastFetchTime;

  /// Returns the raw DolarAPI rate for display purposes.
  /// The rate is in "VES per 1 foreign unit" direction.
  double? _displayRateFor(String currencyCode, String source) {
    final api = DolarApiService.instance;
    if (currencyCode == 'EUR') {
      return source == 'oficial'
          ? api.eurOficialRate?.promedio
          : api.eurParaleloRate?.promedio;
    }
    // Default to USD rates
    return source == 'oficial'
        ? api.oficialRate?.promedio
        : api.paraleloRate?.promedio;
  }

  String _formatTimeSince(DateTime? time) {
    if (time == null) return '';
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) return 'hace un momento';
    if (diff.inMinutes < 60) return 'hace ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'hace ${diff.inHours}h';
    return DateFormat('dd/MM HH:mm').format(time);
  }

  void _fireCallback() {
    double? rate;
    String source;

    switch (_selected) {
      case _RateSource.bcv:
        // DolarAPI rate is "VES per 1 foreign unit" (e.g. 479.78).
        // We need "1 fromCurrency = X toCurrency", i.e. the inverse
        // when fromCurrency is VES and toCurrency is USD/EUR.
        final displayRate = _bcvDisplayRate;
        rate = (displayRate != null && displayRate > 0)
            ? 1.0 / displayRate
            : null;
        source = 'bcv';
        break;
      case _RateSource.paralelo:
        final displayRate = _paraleloDisplayRate;
        rate = (displayRate != null && displayRate > 0)
            ? 1.0 / displayRate
            : null;
        source = 'paralelo';
        break;
      case _RateSource.manual:
        // Manual input is in human-friendly direction (VES per 1 foreign unit),
        // same as BCV/paralelo display. Invert for the callback.
        final manualRate = double.tryParse(_manualController.text);
        rate = (manualRate != null && manualRate > 0)
            ? 1.0 / manualRate
            : null;
        source = 'manual';
        break;
    }

    if (rate != null && rate > 0) {
      widget.onChanged(rate, source);
    }
  }

  void _onManualChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      _fireCallback();
    });
  }

  Future<void> _retryFetch(_RateSource source) async {
    if (source == _RateSource.bcv) {
      setState(() => _isFetchingBcv = true);
      try {
        await RateProviderManager.instance.fetchRate(
          date: DateTime.now(),
          source: 'bcv',
        );
        // Also refresh cached DolarApiService rate
        await DolarApiService.instance.fetchOficialRate();
      } catch (_) {}
      if (mounted) {
        setState(() => _isFetchingBcv = false);
        _fireCallback();
      }
    } else if (source == _RateSource.paralelo) {
      setState(() => _isFetchingParalelo = true);
      try {
        await DolarApiService.instance.fetchParaleloRate();
      } catch (_) {}
      if (mounted) {
        setState(() => _isFetchingParalelo = false);
        _fireCallback();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return CardWithHeader(
      title: 'Tasa de cambio aplicada', // TODO: i18n
      body: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Currency pair indicator
            Row(
              children: [
                Icon(Icons.swap_horiz, size: 16, color: colorScheme.primary),
                const SizedBox(width: 4),
                Text(
                  '${widget.fromCurrency} -> ${widget.toCurrency}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
                const Spacer(),
                if (_lastFetch != null)
                  Text(
                    'Actualizado ${_formatTimeSince(_lastFetch)}', // TODO: i18n
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurface.withValues(alpha: 0.5),
                      fontSize: 11,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),

            // Choice chips
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                _buildRateChip(
                  label: 'BCV',
                  displayRate: _bcvDisplayRate,
                  source: _RateSource.bcv,
                  isFetching: _isFetchingBcv,
                ),
                _buildRateChip(
                  label: 'Paralelo',
                  displayRate: _paraleloDisplayRate,
                  source: _RateSource.paralelo,
                  isFetching: _isFetchingParalelo,
                ),
                ChoiceChip(
                  label: const Text('Manual'),
                  selected: _selected == _RateSource.manual,
                  onSelected: (selected) {
                    if (selected) {
                      setState(() => _selected = _RateSource.manual);
                      _fireCallback();
                    }
                  },
                ),
              ],
            ),

            // Manual text field
            if (_selected == _RateSource.manual) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _manualController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,4}')),
                ],
                decoration: InputDecoration(
                  labelText:
                      'Tasa (${widget.fromCurrency}/${widget.toCurrency})', // TODO: i18n
                  hintText: 'Ej: 479.7800',
                  border: const OutlineInputBorder(),
                  isDense: true,
                  prefixIcon: const Icon(Icons.edit, size: 18),
                ),
                onChanged: _onManualChanged,
              ),
            ],

            // Summary of selected rate (show human-friendly direction)
            if (_selected != _RateSource.manual &&
                _getSelectedDisplayRate() != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.check_circle_outline,
                      size: 14,
                      color: colorScheme.primary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '1 ${widget.toCurrency} = ${_getSelectedDisplayRate()!.toStringAsFixed(2)} ${widget.fromCurrency}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Returns the raw display rate (VES per 1 foreign unit) for the
  /// currently selected source. Used for UI labels only, NOT for the
  /// callback (which receives the inverted rate).
  double? _getSelectedDisplayRate() {
    switch (_selected) {
      case _RateSource.bcv:
        return _bcvDisplayRate;
      case _RateSource.paralelo:
        return _paraleloDisplayRate;
      case _RateSource.manual:
        return double.tryParse(_manualController.text);
    }
  }

  Widget _buildRateChip({
    required String label,
    required double? displayRate,
    required _RateSource source,
    required bool isFetching,
  }) {
    final isAvailable = displayRate != null;
    final isSelected = _selected == source;

    if (isFetching) {
      return Chip(
        label: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label),
            const SizedBox(width: 6),
            const SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(strokeWidth: 1.5),
            ),
          ],
        ),
      );
    }

    if (!isAvailable) {
      return InputChip(
        label: Text('$label: N/D'), // TODO: i18n
        tooltip:
            'No disponible (sin conexion). Toca para reintentar.', // TODO: i18n
        isEnabled: true,
        selected: false,
        avatar: const Icon(Icons.refresh, size: 16),
        onPressed: () => _retryFetch(source),
      );
    }

    // Display in human-friendly direction: "VES per 1 foreign unit"
    // e.g. "BCV (479.78 VES/USD)"
    final rateStr = displayRate.toStringAsFixed(2);
    final currPair =
        '${widget.fromCurrency}/${widget.toCurrency}';

    return ChoiceChip(
      label: Text('$label ($rateStr $currPair)'),
      selected: isSelected,
      onSelected: (selected) {
        if (selected) {
          setState(() => _selected = source);
          _fireCallback();
        }
      },
    );
  }
}
