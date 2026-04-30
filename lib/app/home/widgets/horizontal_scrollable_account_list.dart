import 'package:flutter/material.dart';
import 'package:kilatex/app/accounts/account_form.dart';
import 'package:kilatex/app/accounts/details/account_details.dart';
import 'package:kilatex/core/database/services/account/account_service.dart';
import 'package:kilatex/core/models/account/account.dart';
import 'package:kilatex/core/models/date-utils/date_period_state.dart';
import 'package:kilatex/core/presentation/responsive/breakpoints.dart';
import 'package:kilatex/core/presentation/responsive/responsive_row_column.dart';
import 'package:kilatex/core/presentation/styles/borders.dart';
import 'package:kilatex/core/presentation/theme.dart';
import 'package:kilatex/core/presentation/widgets/number_ui_formatters/currency_displayer.dart';
import 'package:kilatex/core/presentation/widgets/tappable.dart';
import 'package:kilatex/core/presentation/widgets/trending_value.dart';
import 'package:kilatex/core/routes/route_utils.dart';
import 'package:kilatex/i18n/generated/translations.g.dart';

bool _useSmallLayout(BuildContext context) =>
    BreakPoint.of(context).isSmallerThan(BreakpointID.lg);

class HorizontalScrollableAccountList extends StatelessWidget {
  const HorizontalScrollableAccountList({
    required this.dateRangeService,
    this.visibleAccountIds,
  });

  final DatePeriodState dateRangeService;

  /// When non-null, only the accounts whose id is contained in this list are
  /// rendered. Passed by the dashboard so Hidden Mode can remove savings
  /// accounts from the carousel without having to touch the internal stream.
  final List<String>? visibleAccountIds;

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final borderRadius = BorderRadius.circular(getCardBorderRadius());

    return Align(
      alignment: Alignment.centerLeft,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
        child: StreamBuilder(
          stream: AccountService.instance.getAccounts(
            predicate: (acc, curr) => acc.closingDate.isNull(),
          ),
          builder: (context, snapshot) {
            final allAccounts = snapshot.data ?? const <Account>[];
            final visibleIds = visibleAccountIds;
            // null = Hidden Mode stream not ready yet. Render nothing rather
            // than falling back to `allAccounts`, which would leak saving
            // accounts for the first frame before the lock state resolves.
            final accounts = visibleIds == null
                ? const <Account>[]
                : allAccounts
                      .where((a) => visibleIds.contains(a.id))
                      .toList(growable: false);

            return Row(
              children: [
                ...List.generate(accounts.length, (index) {
                  final account = accounts.elementAt(index);

                  return _buildAccountCard(
                    context,
                    account,
                    borderRadius: borderRadius,
                  );
                }),
                // Add account card
                Opacity(
                  opacity: 0.6,
                  child: SizedBox(
                    width: 200,
                    // Height of a normal account card minus the border width of this card
                    height: (_useSmallLayout(context) ? 127.3 : 76) - 2,
                    child: Tappable(
                      onTap: () {
                        RouteUtils.pushRoute(const AccountFormPage());
                      },
                      shape: RoundedRectangleBorder(
                        borderRadius: borderRadius,
                        side: BorderSide(
                          width: 2,
                          color: Theme.of(context).dividerColor,
                        ),
                      ),
                      child: Card(
                        elevation: 0,
                        color: Colors.transparent,
                        margin: const EdgeInsets.all(0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          mainAxisAlignment: MainAxisAlignment.center,
                          spacing: 4,
                          children: [
                            Text(t.account.form.create),
                            const Icon(Icons.add),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildAccountCard(
    BuildContext context,
    Account account, {
    required BorderRadius borderRadius,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = Theme.of(context).colorScheme.primary;

    final cardContent = Tappable(
      onTap: () => RouteUtils.pushRoute(
        AccountDetailsPage(
          account: account,
          accountIconHeroTag: 'dashboard-page__account-icon-${account.id}',
        ),
      ),
      bgColor: isDark ? Colors.transparent : Theme.of(context).cardColor,
      borderRadius: borderRadius,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: ResponsiveRowColumn(
          direction: _useSmallLayout(context)
              ? Axis.vertical
              : Axis.horizontal,
          columnCrossAxisAlignment: CrossAxisAlignment.start,
          columnSpacing: 8,
          rowSpacing: 16,
          children: [
            ResponsiveRowColumnItem(
              child: Hero(
                tag: 'dashboard-page__account-icon-${account.id}',
                child: account.displayIcon(context, size: 28),
              ),
            ),
            ResponsiveRowColumnItem(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    account.name,
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  Row(
                    children: [
                      StreamBuilder(
                        initialData: 0.0,
                        stream: AccountService.instance.getAccountMoney(
                          account: account,
                        ),
                        builder: (context, snapshot) {
                          return CurrencyDisplayer(
                            amountToConvert: snapshot.data!,
                            currency: account.currency,
                            compactView: snapshot.data! >= 10000000,
                            integerStyle: Theme.of(context)
                                .textTheme
                                .titleMedium!
                                .copyWith(fontWeight: FontWeight.w600),
                          );
                        },
                      ),
                      const SizedBox(width: 8),
                      StreamBuilder(
                        initialData: 0.0,
                        stream: AccountService.instance
                            .getAccountsMoneyVariation(
                              accounts: [account],
                              startDate: dateRangeService.startDate,
                              endDate: dateRangeService.endDate,
                              convertToPreferredCurrency: false,
                            ),
                        builder: (context, snapshot) {
                          return TrendingValue(
                            percentage: snapshot.data!,
                            decimalDigits: 0,
                          );
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    if (isDark) {
      return Container(
        margin: const EdgeInsets.only(right: 12),
        decoration: BoxDecoration(
          color: primary.withValues(alpha: 0.08),
          borderRadius: borderRadius,
          border: Border.all(
            color: primary.withValues(alpha: 0.1),
            width: 0.5,
          ),
        ),
        child: cardContent,
      );
    } else {
      return DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: borderRadius,
          boxShadow: boxShadowGeneral(context),
        ),
        child: Card(
          margin: const EdgeInsets.only(right: 12),
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: borderRadius),
          child: cardContent,
        ),
      );
    }
  }
}
