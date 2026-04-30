import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:bolsio/app/calculator/calculator.page.dart';
import 'package:bolsio/app/currencies/edit_currency_page.dart';
import 'package:bolsio/app/currencies/exchange_rate_details.dart';
import 'package:bolsio/app/currencies/exchange_rate_form.dart';
import 'package:bolsio/app/currencies/widgets/currency_mode_picker.dart';
import 'package:bolsio/app/currencies/widgets/manual_override_dialog.dart';
import 'package:bolsio/app/currencies/widgets/rate_source_badge.dart';
import 'package:bolsio/app/layout/page_framework.dart';
import 'package:bolsio/app/settings/widgets/settings_list_utils.dart';
import 'package:bolsio/core/database/services/currency/currency_service.dart';
import 'package:bolsio/core/database/services/exchange-rate/exchange_rate_service.dart';
import 'package:bolsio/core/database/services/user-setting/user_setting_service.dart';
import 'package:bolsio/core/extensions/padding.extension.dart';
import 'package:bolsio/core/models/currency/currency.dart';
import 'package:bolsio/core/models/currency/currency_mode.dart';
import 'package:bolsio/core/presentation/animations/animated_expanded.dart';
import 'package:bolsio/core/presentation/widgets/confirm_dialog.dart';
import 'package:bolsio/core/presentation/widgets/currency_selector_modal.dart';
import 'package:bolsio/core/routes/route_utils.dart';
import 'package:bolsio/i18n/generated/translations.g.dart';
import 'package:skeletonizer/skeletonizer.dart' hide Skeleton;

import '../../core/presentation/widgets/no_results.dart';
import 'package:bolsio/core/services/dolar_api_service.dart';
import 'package:bolsio/core/services/rate_providers/rate_refresh_service.dart';
import 'package:bolsio/core/presentation/helpers/snackbar.dart';
import 'package:bolsio/core/database/app_db.dart';
import 'package:bolsio/core/utils/uuid.dart';

class CurrencyManagerPage extends StatelessWidget {
  const CurrencyManagerPage({super.key});

  /// Open the 4-mode currency-mode picker and persist the result.
  ///
  /// Phase 5 task 5.1 + 5.2 + 5.3:
  ///   - Tile opens [showCurrencyModePicker] (4 options, Dual exposes
  ///     primary/secondary sub-pickers via [CurrencySelectorModal]).
  ///   - On confirm we call [computeModeWrites] + [persistCurrencyModeChange]
  ///     which writes ONLY [SettingKey.currencyMode],
  ///     [SettingKey.preferredCurrency], (conditionally)
  ///     [SettingKey.secondaryCurrency] and [SettingKey.preferredRateSource].
  ///   - The handler MUST NOT touch accounts or transactions tables — see
  ///     the spec invariant in `computeModeWrites` and the unit test in
  ///     `test/app/currencies/currency_mode_writes_test.dart`.
  ///   - Resolved decision #2: on Dual → Single switch we deliberately
  ///     omit [SettingKey.secondaryCurrency] from the write set so the
  ///     existing on-disk row is preserved.
  Future<void> changeCurrencyMode(BuildContext context) async {
    final currentMode = CurrencyMode.fromDb(
      appStateSettings[SettingKey.currencyMode],
    );
    final currentPrimary =
        appStateSettings[SettingKey.preferredCurrency] ?? 'USD';
    final currentSecondary = appStateSettings[SettingKey.secondaryCurrency];
    final currentRateSource =
        appStateSettings[SettingKey.preferredRateSource] ?? 'bcv';

    final choice = await showCurrencyModePicker(
      context: context,
      currentMode: currentMode,
      currentPrimary: currentPrimary,
      currentSecondary: currentSecondary,
    );
    if (choice == null) return;

    final writes = computeModeWrites(
      newMode: choice.mode,
      primary: choice.primary,
      secondary: choice.secondary,
      selectedRateSource: currentRateSource,
    );
    await persistCurrencyModeChange(writes);

    if (!context.mounted) return;
    BolsioSnackbar.success(
      SnackbarParams(_modeChangeMessage(choice.mode)),
    );
  }

  /// Open the manual-override dialog (Phase 5 task 5.4). Returns once the
  /// user dismisses or saves.
  Future<void> openManualOverride(
    BuildContext context, {
    Currency? initialCurrency,
  }) async {
    final saved = await showManualOverrideDialog(
      context,
      initialCurrency: initialCurrency,
    );
    if (!context.mounted) return;
    if (saved) {
      BolsioSnackbar.success(
        SnackbarParams('Tasa manual guardada.'),
      );
    }
  }

  String _modeChangeMessage(CurrencyMode mode) {
    switch (mode) {
      case CurrencyMode.single_usd:
        return 'Modo actualizado: Solo USD.';
      case CurrencyMode.single_bs:
        return 'Modo actualizado: Solo Bs.';
      case CurrencyMode.single_other:
        return 'Modo actualizado: una sola moneda.';
      case CurrencyMode.dual:
        return 'Modo actualizado: Dual.';
    }
  }

  String _modeSubtitle(CurrencyMode mode, String primary, String? secondary) {
    switch (mode) {
      case CurrencyMode.single_usd:
        return 'Solo USD';
      case CurrencyMode.single_bs:
        return 'Solo Bs';
      case CurrencyMode.single_other:
        return 'Solo $primary';
      case CurrencyMode.dual:
        final s = secondary ?? 'VES';
        return 'Dual ($primary / $s)';
    }
  }

  Future<void> forceRefreshRates(BuildContext context) async {
    BolsioSnackbar.success(
      SnackbarParams('Actualizando tasas...'),
    );
    try {
      final result = await RateRefreshService.instance.refreshNow();
      if (!context.mounted) return;
      final total = result.totalSuccess + result.totalFailure;
      if (result.totalFailure == 0 && result.totalSuccess > 0) {
        BolsioSnackbar.success(
          SnackbarParams(
            'Tasas actualizadas: ${result.totalSuccess}/$total '
            '(USD ok=${result.usdSuccessCount}, EUR ok=${result.eurSuccessCount})',
          ),
        );
      } else {
        BolsioSnackbar.error(
          SnackbarParams(
            'Actualización parcial: ok=${result.totalSuccess} fallos=${result.totalFailure} '
            '(USD ok=${result.usdSuccessCount}/${result.usdSuccessCount + result.usdFailureCount}, '
            'EUR ok=${result.eurSuccessCount}/${result.eurSuccessCount + result.eurFailureCount})',
          ),
        );
      }
    } catch (e) {
      if (!context.mounted) return;
      BolsioSnackbar.error(SnackbarParams('Error al actualizar tasas: $e'));
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
            // ── Modo de moneda (Phase 5 task 5.1) ─────────────────────
            // The mode tile lives at the very top of the page because it
            // is the highest-impact toggle in the screen — every other
            // tile (preferred currency, exchange rates list) is derived
            // from this state. We subscribe to the live setting stream so
            // the subtitle updates without a manual reload after the user
            // returns from the bottom sheet.
            createListSeparator(context, 'Modo de moneda'),
            StreamBuilder<String?>(
              stream: UserSettingService.instance
                  .getSettingFromDB(SettingKey.currencyMode),
              builder: (context, modeSnap) {
                final mode = CurrencyMode.fromDb(modeSnap.data);
                final primary =
                    appStateSettings[SettingKey.preferredCurrency] ?? 'USD';
                final secondary =
                    appStateSettings[SettingKey.secondaryCurrency];
                return ListTile(
                  leading: Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .primary
                          .withValues(alpha: 0.125),
                      borderRadius: BorderRadius.circular(100),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      Icons.tune_rounded,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  title: const Text('Modo de moneda'),
                  subtitle: Text(_modeSubtitle(mode, primary, secondary)),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => changeCurrencyMode(context),
                );
              },
            ),
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
                      title: Row(
                        children: [
                          Text(item.currency.code),
                          const SizedBox(width: 8),
                          // Phase 5 task 5.5 — per-pair source badge.
                          // The `source` value lives on `ExchangeRateInDB`
                          // (inherited via [ExchangeRate]). Pre-v28 rows
                          // may have `null` here; the badge widget
                          // labels those as "Auto" for clarity.
                          RateSourceBadge(rawSource: item.source),
                        ],
                      ),
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
                      // --- Start: Manual override entry (Phase 5 task 5.4) ---
                      const Divider(indent: 16, endIndent: 16),
                      ListTile(
                        title: const Text('Forzar manual por par'),
                        subtitle: const Text(
                          'Establecer una tasa manual que sobrescribe la automática.',
                        ),
                        leading: Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: Colors.blueGrey.withValues(alpha: 0.125),
                            borderRadius: BorderRadius.circular(100),
                          ),
                          alignment: Alignment.center,
                          child: const Icon(
                            Icons.edit_note_rounded,
                            color: Colors.blueGrey,
                          ),
                        ),
                        onTap: () => openManualOverride(context),
                      ),
                      const SizedBox(height: 8),
                      // --- End: Manual override entry ---
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
                              BolsioSnackbar.error(
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
                              BolsioSnackbar.success(
                                SnackbarParams(
                                  'Tasa actualizada: ${rate.promedio} '
                                  '(almacenado: $storeCurrencyCode = $storeRate)',
                                ),
                              );
                            }
                          } catch (e) {
                            if (context.mounted) {
                              BolsioSnackbar.error(
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
