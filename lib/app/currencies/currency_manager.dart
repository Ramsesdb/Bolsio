import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:wallex/app/calculator/calculator.page.dart';
import 'package:wallex/app/currencies/edit_currency_page.dart';
import 'package:wallex/app/currencies/exchange_rate_details.dart';
import 'package:wallex/app/currencies/exchange_rate_form.dart';
import 'package:wallex/app/layout/page_framework.dart';
import 'package:wallex/app/settings/widgets/settings_list_utils.dart';
import 'package:wallex/core/database/services/currency/currency_service.dart';
import 'package:wallex/core/database/services/exchange-rate/exchange_rate_service.dart';
import 'package:wallex/core/database/services/user-setting/user_setting_service.dart';
import 'package:wallex/core/extensions/padding.extension.dart';
import 'package:wallex/core/models/currency/currency.dart';
import 'package:wallex/core/presentation/animations/animated_expanded.dart';
import 'package:wallex/core/presentation/widgets/confirm_dialog.dart';
import 'package:wallex/core/presentation/widgets/currency_selector_modal.dart';
import 'package:wallex/core/routes/route_utils.dart';
import 'package:wallex/i18n/generated/translations.g.dart';
import 'package:skeletonizer/skeletonizer.dart' hide Skeleton;

import '../../core/presentation/widgets/no_results.dart';
import 'package:wallex/core/services/dolar_api_service.dart';
import 'package:wallex/core/services/rate_providers/rate_refresh_service.dart';
import 'package:wallex/core/presentation/helpers/snackbar.dart';
import 'package:wallex/core/database/app_db.dart';
import 'package:wallex/core/utils/uuid.dart';

class CurrencyManagerPage extends StatelessWidget {
  const CurrencyManagerPage({super.key});

  Future<void> forceRefreshRates(BuildContext context) async {
    WallexSnackbar.success(
      SnackbarParams('Actualizando tasas...'),
    );
    try {
      final result = await RateRefreshService.instance.refreshNow();
      if (!context.mounted) return;
      final total = result.totalSuccess + result.totalFailure;
      if (result.totalFailure == 0 && result.totalSuccess > 0) {
        WallexSnackbar.success(
          SnackbarParams(
            'Tasas actualizadas: ${result.totalSuccess}/$total '
            '(USD ok=${result.usdSuccessCount}, EUR ok=${result.eurSuccessCount})',
          ),
        );
      } else {
        WallexSnackbar.error(
          SnackbarParams(
            'Actualización parcial: ok=${result.totalSuccess} fallos=${result.totalFailure} '
            '(USD ok=${result.usdSuccessCount}/${result.usdSuccessCount + result.usdFailureCount}, '
            'EUR ok=${result.eurSuccessCount}/${result.eurSuccessCount + result.eurFailureCount})',
          ),
        );
      }
    } catch (e) {
      if (!context.mounted) return;
      WallexSnackbar.error(SnackbarParams('Error al actualizar tasas: $e'));
    }
  }

  void changePreferredCurrency(BuildContext context, Currency newCurrency) {
    final t = Translations.of(context);

    confirmDialog(
      context,
      dialogTitle: t.currencies.change_preferred_currency_title,
      contentParagraphs: [Text(t.currencies.change_preferred_currency_msg)],
    ).then((isConfirmed) {
      if (isConfirmed != true) return;

      UserSettingService.instance
          .setItem(SettingKey.preferredCurrency, newCurrency.code)
          .then((value) {
            ExchangeRateService.instance.deleteExchangeRates();
          });
    });
  }

  Future<void> addExchangeRate(BuildContext context) async {
    final newRate = await showExchangeRateFormDialog(
      context,
      const ExchangeRateFormDialog(),
    );

    if (newRate != null) {
      await ExchangeRateService.instance.insertOrUpdateExchangeRate(newRate);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);

    return PageFramework(
      title: Translations.of(context).currencies.currency_manager,
      appBarActions: [
        // Entry point a la Calculadora FX (calculadora-fx Tanda 1, task 1.6).
        // Solo navegación; no modifica el resto de la página.
        IconButton(
          icon: const Icon(Icons.calculate_outlined),
          tooltip: t.home.quick_actions.go_to_calculator,
          onPressed: () => RouteUtils.pushRoute(const CalculatorPage()),
        ),
        IconButton(
          icon: const Icon(Icons.refresh_rounded),
          tooltip: 'Refrescar tasas',
          onPressed: () => forceRefreshRates(context),
        ),
      ],
      body: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 12).withSafeBottom(context),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            createListSeparator(context, t.currencies.preferred_currency),
            StreamBuilder(
              stream: CurrencyService.instance.ensureAndGetPreferredCurrency(),
              builder: (context, snapshot) {
                final userCurrency = snapshot.data;

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Skeletonizer(
                      enabled: userCurrency == null,
                      child: ListTile(
                        leading: ClipRRect(
                          borderRadius: BorderRadius.circular(100),
                          child: userCurrency != null
                              ? userCurrency.displayFlagIcon(size: 42)
                              : Container(
                                  height: 42,
                                  width: 42,
                                  color: Colors.red,
                                ),
                        ),
                        title: Text(
                          userCurrency == null
                              ? 'PLA - Placeholder'
                              : ('${userCurrency.name} - ${userCurrency.code}'),
                        ),
                        subtitle: Text(
                          t.currencies.tap_to_change_preferred_currency,
                        ),
                        onTap: () {
                          if (userCurrency == null) return;

                          showCurrencySelectorModal(
                            context,
                            CurrencySelectorModal(
                              preselectedCurrency: userCurrency,
                              onCurrencySelected: (newCurrency) async {
                                await Future.delayed(
                                  const Duration(milliseconds: 250),
                                );
                                if (!context.mounted) return;
                                changePreferredCurrency(context, newCurrency);
                              },
                            ),
                          );
                        },
                      ),
                    ),
                    ListTile(
                      title: Text(t.currencies.currency_settings),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      enabled: userCurrency != null,
                      onTap: () {
                        if (userCurrency != null) {
                          RouteUtils.pushRoute(
                            EditCurrencyPage(currency: userCurrency),
                          );
                        }
                      },
                    ),
                  ],
                );
              },
            ),
            createListSeparator(context, t.currencies.exchange_rates),

            StreamBuilder(
              stream: ExchangeRateService.instance.getExchangeRates(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const LinearProgressIndicator();
                }

                final exchangeRates = snapshot.data!;

                if (exchangeRates.isEmpty) {
                  // Data has loaded but is empty:
                  return NoResults(
                    title: t.general.empty_warn,
                    description: t.currencies.empty,
                    bottom: FilledButton.tonalIcon(
                      onPressed: () => addExchangeRate(context),
                      icon: const Icon(Icons.add_rounded),
                      label: Text(t.currencies.exchange_rate_form.add),
                    ),
                  );
                }

                return ListView.separated(
                  itemCount: exchangeRates.length,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: EdgeInsets.zero,
                  itemBuilder: (context, index) {
                    final item = exchangeRates[index];

                    return ListTile(
                      leading: ClipRRect(
                        borderRadius: BorderRadius.circular(100),
                        child: StreamBuilder(
                          stream: CurrencyService.instance.getCurrencyByCode(
                            item.currencyCode,
                          ),
                          builder: (context, snapshot) {
                            if (!snapshot.hasData) {
                              return Bone.square(size: 42);
                            }

                            return snapshot.data!.displayFlagIcon(size: 42);
                          },
                        ),
                      ),
                      title: Text(item.currency.code),
                      subtitle: StreamBuilder(
                        stream: CurrencyService.instance.getCurrencyByCode(
                          item.currencyCode,
                        ),
                        builder: (context, snapshot) {
                          return Skeletonizer(
                            enabled: !snapshot.hasData,
                            child: Text(snapshot.data?.name ?? BoneMock.name),
                          );
                        },
                      ),
                      trailing: Text(
                        item.exchangeRate.toStringAsFixed(
                          max(4, item.currency.decimalPlaces),
                        ),
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      onTap: () async {
                        final currency = await CurrencyService.instance
                            .getCurrencyByCode(item.currencyCode)
                            .first;

                        if (currency == null) return;

                        unawaited(RouteUtils.pushRoute(
                          ExchangeRateDetailsPage(currency: currency),
                        ));
                      },
                    );
                  },
                  separatorBuilder: (context, index) {
                    return const Divider(indent: 68);
                  },
                );
              },
            ),

            StreamBuilder(
              stream: ExchangeRateService.instance.getExchangeRates(),
              builder: (context, asyncSnapshot) {
                return AnimatedExpanded(
                  expand:
                      asyncSnapshot.hasData && asyncSnapshot.data!.isNotEmpty,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.start,
                    children: [
                      const Divider(indent: 68, height: 1, thickness: 1),
                      ListTile(
                        title: Text(t.currencies.exchange_rate_form.add),
                        minVerticalPadding: 16,

                        leading: Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: Theme.of(
                              context,
                            ).colorScheme.primary.withValues(alpha: 0.125),
                            borderRadius: BorderRadius.circular(100),
                          ),
                          alignment: Alignment.center,
                          child: Icon(
                            Icons.add_rounded,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                        onTap: () => addExchangeRate(context),
                      ),
                      const SizedBox(height: 8),
                      // --- Start: Update Rate Button ---
                      const Divider(indent: 16, endIndent: 16),
                      ListTile(
                        title: const Text('Actualizar Tasa (DolarApi)'),
                        subtitle: const Text('Obtener tasa oficial o paralela'),
                        leading: Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: Colors.green.withValues(alpha: 0.125),
                            borderRadius: BorderRadius.circular(100),
                          ),
                          alignment: Alignment.center,
                          child: const Icon(
                            Icons.currency_exchange,
                            color: Colors.green,
                          ),
                        ),
                        onTap: () async {
                          final rates = await DolarApiService.instance
                              .fetchAllRates();
                          if (rates.isEmpty) {
                            if (context.mounted) {
                              WallexSnackbar.error(
                                SnackbarParams(
                                  'Error al obtener tasas de cambio',
                                ),
                              );
                            }
                            return;
                          }

                          final oficial = DolarApiService.instance.oficialRate;
                          final paralelo =
                              DolarApiService.instance.paraleloRate;

                          if (!context.mounted) return;

                          final selectedRate = await showDialog<String>(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text('Seleccionar Tasa'),
                              content: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (oficial != null)
                                    ListTile(
                                      title: Text(
                                        'Oficial (BCV): ${oficial.promedio.toStringAsFixed(2)}',
                                      ),
                                      subtitle: Text(
                                        oficial.fechaActualizacion.toString(),
                                      ),
                                      onTap: () =>
                                          Navigator.pop(context, 'oficial'),
                                    ),
                                  if (paralelo != null)
                                    ListTile(
                                      title: Text(
                                        'Paralelo: ${paralelo.promedio.toStringAsFixed(2)}',
                                      ),
                                      subtitle: Text(paralelo.nombre),
                                      onTap: () =>
                                          Navigator.pop(context, 'paralelo'),
                                    ),
                                ],
                              ),
                            ),
                          );

                          if (selectedRate == null) return;
                          final rate = selectedRate == 'oficial'
                              ? oficial
                              : paralelo;
                          if (rate == null) return;

                          try {
                            final preferredCurrency =
                                appStateSettings[SettingKey.preferredCurrency] ??
                                    'USD';
                            // DolarAPI returns: 1 USD = rate.promedio VES
                            // DB convention: 1 unit of currencyCode = X preferred currency units
                            final String storeCurrencyCode;
                            final double storeRate;
                            if (preferredCurrency == 'VES') {
                              storeCurrencyCode = 'USD';
                              storeRate = rate.promedio;
                            } else {
                              storeCurrencyCode = 'VES';
                              storeRate = 1.0 / rate.promedio;
                            }
                            await ExchangeRateService.instance
                                .insertOrUpdateExchangeRate(
                                  ExchangeRateInDB(
                                    id: generateUUID(),
                                    date: DateTime.now(),
                                    currencyCode: storeCurrencyCode,
                                    exchangeRate: storeRate,
                                  ),
                                );
                            if (context.mounted) {
                              WallexSnackbar.success(
                                SnackbarParams(
                                  'Tasa actualizada: ${rate.promedio} '
                                  '(almacenado: $storeCurrencyCode = $storeRate)',
                                ),
                              );
                            }
                          } catch (e) {
                            if (context.mounted) {
                              WallexSnackbar.error(
                                SnackbarParams('Error: $e'),
                              );
                            }
                          }
                        },
                      ),
                      // --- End: Update Rate Button ---
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
