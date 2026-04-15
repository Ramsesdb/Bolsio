import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:wallex/core/utils/logger.dart';

/// Model for exchange rate from DolarApi.com
class DolarApiRate {
  final String fuente;
  final String nombre;
  final double? compra;
  final double? venta;
  final double promedio;
  final DateTime fechaActualizacion;

  DolarApiRate({
    required this.fuente,
    required this.nombre,
    this.compra,
    this.venta,
    required this.promedio,
    required this.fechaActualizacion,
  });

  factory DolarApiRate.fromJson(Map<String, dynamic> json) {
    return DolarApiRate(
      fuente: json['fuente'] as String,
      nombre: json['nombre'] as String,
      compra: json['compra'] as double?,
      venta: json['venta'] as double?,
      promedio: (json['promedio'] as num).toDouble(),
      fechaActualizacion: DateTime.parse(json['fechaActualizacion'] as String),
    );
  }
}

/// Service to fetch exchange rates from DolarApi.com for Venezuela
class DolarApiService {
  static const String _baseUrl = 'https://ve.dolarapi.com/v1';

  static DolarApiService? _instance;
  static DolarApiService get instance => _instance ??= DolarApiService._();

  DolarApiService._();

  /// Cached rates
  DolarApiRate? _oficialRate;
  DolarApiRate? _paraleloRate;
  DateTime? _lastFetch;

  /// Get the official USD rate
  DolarApiRate? get oficialRate => _oficialRate;

  /// Get the parallel USD rate
  DolarApiRate? get paraleloRate => _paraleloRate;

  /// Fetch all USD rates (official and parallel)
  Future<List<DolarApiRate>> fetchAllRates() async {
    try {
      final response = await http
          .get(
            Uri.parse('$_baseUrl/dolares'),
            headers: {'Accept': 'application/json'},
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final List<dynamic> jsonList = json.decode(response.body);
        final rates = jsonList.map((j) => DolarApiRate.fromJson(j)).toList();

        // Cache the rates
        for (final rate in rates) {
          if (rate.fuente == 'oficial') {
            _oficialRate = rate;
          } else if (rate.fuente == 'paralelo') {
            _paraleloRate = rate;
          }
        }
        _lastFetch = DateTime.now();

        Logger.printDebug(
          'DolarApi: Fetched rates - Oficial: ${_oficialRate?.promedio}, '
          'Paralelo: ${_paraleloRate?.promedio}',
        );

        return rates;
      } else {
        Logger.printDebug('DolarApi: Error ${response.statusCode}');
        return [];
      }
    } catch (e) {
      Logger.printDebug('DolarApi: Exception fetching rates: $e');
      return [];
    }
  }

  /// Fetch only the official rate.
  ///
  /// Returns the cached rate if the API call fails (offline fallback).
  Future<DolarApiRate?> fetchOficialRate() async {
    try {
      final response = await http
          .get(
            Uri.parse('$_baseUrl/dolares/oficial'),
            headers: {'Accept': 'application/json'},
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final rate = DolarApiRate.fromJson(json.decode(response.body));
        _oficialRate = rate;
        _lastFetch = DateTime.now();
        return rate;
      }
    } catch (e) {
      Logger.printDebug('DolarApi: Exception fetching oficial rate: $e');
    }
    // Fallback to cached rate if available
    return _oficialRate;
  }

  /// Fetch only the parallel rate
  Future<DolarApiRate?> fetchParaleloRate() async {
    try {
      final response = await http
          .get(
            Uri.parse('$_baseUrl/dolares/paralelo'),
            headers: {'Accept': 'application/json'},
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final rate = DolarApiRate.fromJson(json.decode(response.body));
        _paraleloRate = rate;
        _lastFetch = DateTime.now();
        return rate;
      }
    } catch (e) {
      Logger.printDebug('DolarApi: Exception fetching paralelo rate: $e');
    }
    return _paraleloRate;
  }

  /// When was the last successful fetch?
  DateTime? get lastFetchTime => _lastFetch;

  /// Check if rates are stale (older than 1 hour)
  bool get isStale {
    if (_lastFetch == null) return true;
    return DateTime.now().difference(_lastFetch!) > const Duration(hours: 1);
  }
}
