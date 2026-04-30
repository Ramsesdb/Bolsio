import 'package:bolsio/core/database/app_db.dart';

class ExchangeRate extends ExchangeRateInDB {
  CurrencyInDB currency;

  ExchangeRate({
    required super.id,
    required super.date,
    required this.currency,
    required super.exchangeRate,
    super.source,
  }) : super(currencyCode: currency.code);
}
