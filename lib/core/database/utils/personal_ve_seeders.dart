import 'package:flutter/material.dart';
import 'package:bolsio/app/onboarding/bank_options.dart';
import 'package:bolsio/core/database/app_db.dart';
import 'package:bolsio/core/database/services/account/account_service.dart';
import 'package:bolsio/core/database/services/category/category_service.dart';
import 'package:bolsio/core/database/services/tags/tags_service.dart';
import 'package:bolsio/core/models/account/account.dart';
import 'package:bolsio/core/models/category/category.dart';
import 'package:bolsio/core/utils/logger.dart';
import 'package:bolsio/core/utils/uuid.dart';

/// Seeds Ramses's personal Venezuelan bank accounts, custom income/expense
/// categories (hierarchical), and useful tags.
///
/// Idempotent: skips entirely if any accounts already exist in the database.
class PersonalVESeeder {
  /// Run the full seed: accounts, categories, and tags.
  ///
  /// [selectedBankIds] controls which optional bank accounts are created.
  /// Accounts for "Efectivo Bs" and "Efectivo USD" are always created.
  /// Pass an empty list to create only the always-on accounts.
  ///
  /// [alsoUsdForBank] (key = bank id) marks banks for which the user — in
  /// DUAL currency mode — also wants a second USD account in addition to
  /// the native VES one. Only honoured for banks with `supportsBoth =
  /// true`. Ignored for non-VES banks and for keys not in
  /// [selectedBankIds].
  ///
  /// [currencyMode] is the raw s02 selection (`'USD'`, `'VES'` or
  /// `'DUAL'`). When the user picked `'USD'` and the bank has
  /// `supportsBoth = true`, both VES and USD accounts are created
  /// automatically (in Venezuela a USD account requires the underlying
  /// VES account).
  ///
  /// Safe to call multiple times — if accounts already exist the method
  /// returns immediately without inserting anything.
  static Future<void> seedAll({
    List<String> selectedBankIds = const [],
    Map<String, bool> alsoUsdForBank = const <String, bool>{},
    String currencyMode = 'USD',
  }) async {
    final db = AppDB.instance;

    // ── Idempotency guard ───────────────────────────────────────────────
    final existingAccounts = await db.select(db.accounts).get();
    if (existingAccounts.isNotEmpty) {
      Logger.printDebug(
        '[PersonalVESeeder] ${existingAccounts.length} accounts already exist, '
        'skipping seed.',
      );
      return;
    }

    Logger.printDebug('[PersonalVESeeder] Starting personal VE seed...');

    await _seedAccounts(
      selectedBankIds: selectedBankIds,
      alsoUsdForBank: alsoUsdForBank,
      currencyMode: currencyMode,
    );
    await _seedCategories();
    await _seedTags();

    Logger.printDebug('[PersonalVESeeder] Seed completed successfully.');
  }

  // ====================================================================
  // Accounts
  // ====================================================================

  /// Legacy account names preserved so that historical bank IDs override the
  /// generic naming convention and emit fixed names.
  static const Map<String, List<_LegacyAccountSpec>> _legacyAccountSpecs = {
    'bdv': [
      _LegacyAccountSpec(
        name: 'Banco de Venezuela',
        currencyId: 'VES',
        iconId: 'account_balance',
        color: '1A237E',
        order: 1,
      ),
    ],
    'banesco': [
      _LegacyAccountSpec(
        name: 'Banesco',
        currencyId: 'VES',
        iconId: 'account_balance',
        color: '003087',
        order: 3,
      ),
    ],
    'mercantil': [
      _LegacyAccountSpec(
        name: 'Mercantil',
        currencyId: 'VES',
        iconId: 'account_balance',
        color: 'B71C1C',
        order: 4,
      ),
    ],
    'provincial': [
      _LegacyAccountSpec(
        name: 'Provincial',
        currencyId: 'VES',
        iconId: 'account_balance',
        color: '2E7D32',
        order: 5,
      ),
    ],
    // BNC historically seeded two VES accounts (#1, #2). Preserve that for
    // the balance-restoration path; the alsoUsd flag still adds a third
    // USD account on top when DUAL.
    'bnc': [
      _LegacyAccountSpec(
        name: 'Banco Nacional de Credito #1',
        currencyId: 'VES',
        iconId: 'account_balance',
        color: '00838F',
        order: 6,
      ),
      _LegacyAccountSpec(
        name: 'Banco Nacional de Credito #2',
        currencyId: 'VES',
        iconId: 'account_balance',
        color: '00695C',
        order: 7,
      ),
    ],
    'banplus': [
      _LegacyAccountSpec(
        name: 'Banplus',
        currencyId: 'VES',
        iconId: 'account_balance',
        color: 'EF6C00',
        order: 8,
      ),
    ],
    'bicentenario': [
      _LegacyAccountSpec(
        name: 'Bicentenario',
        currencyId: 'VES',
        iconId: 'account_balance',
        color: 'C62828',
        order: 9,
      ),
    ],
    'bancamiga': [
      _LegacyAccountSpec(
        name: 'Bancamiga',
        currencyId: 'VES',
        iconId: 'account_balance',
        color: '6A1B9A',
        order: 10,
      ),
    ],
    'binance': [
      _LegacyAccountSpec(
        name: 'Binance',
        currencyId: 'USD',
        iconId: 'universal_currency_alt',
        color: 'F3BA2F',
        order: 11,
      ),
    ],
    'zinli': [
      _LegacyAccountSpec(
        name: 'Zinli',
        currencyId: 'USD',
        iconId: 'credit_card',
        color: '6A1B9A',
        order: 12,
      ),
    ],
    'reserve': [
      _LegacyAccountSpec(
        name: 'Reserve',
        currencyId: 'USD',
        iconId: 'wallet',
        color: '1565C0',
        order: 13,
      ),
    ],
    'paypal': [
      _LegacyAccountSpec(
        name: 'PayPal',
        currencyId: 'USD',
        iconId: 'payment',
        color: '003087',
        order: 14,
      ),
    ],
  };

  /// Build the optional bank accounts for the given selection. Banks are
  /// resolved against [_legacyAccountSpecs] first (preserving legacy names
  /// for the balance-restoration path); banks without a legacy spec fall
  /// back to a generic 1-account-per-bank scheme using `BankOption.name`,
  /// `defaultCurrency`, color and icon.
  ///
  /// When [alsoUsdForBank] marks a VES bank with `supportsBoth = true`, a
  /// second USD account named "${bank.name} USD" is created. When that
  /// happens, the primary VES account is renamed to "${bank.name} Bs" to
  /// avoid ambiguity. Bank icons are kept lowercase Material names.
  ///
  /// When [currencyMode] is `'USD'` and the bank has `supportsBoth = true`,
  /// both VES and USD accounts are created automatically — in Venezuelan
  /// banking a USD account requires the underlying VES account.
  static Future<void> _seedAccounts({
    required List<String> selectedBankIds,
    required Map<String, bool> alsoUsdForBank,
    required String currencyMode,
  }) async {
    final now = DateTime.now();
    final selected = selectedBankIds.toSet();
    int displayOrderCounter = 100; // generic banks start after legacy slots

    final optionalAccounts = <AccountInDB>[];

    for (final bank in kBanks) {
      if (!selected.contains(bank.id)) continue;

      // Create both VES+USD when:
      //  1. DUAL mode and user explicitly toggled "also USD", OR
      //  2. USD mode and the bank supports both currencies (VE banks
      //     require the VES account to hold a USD sub-account).
      final wantsAlsoUsd = bank.supportsBoth &&
          bank.defaultCurrency == 'VES' &&
          ((alsoUsdForBank[bank.id] ?? false) ||
              currencyMode == 'USD');

      final legacySpecs = _legacyAccountSpecs[bank.id];
      if (legacySpecs != null) {
        // Legacy path: emit each pre-defined spec verbatim, keeping the
        // historical names and orders. BDV historically also emitted a
        // "Banco de Venezuela USD" tile; we now drive that off
        // `wantsAlsoUsd`.
        for (final spec in legacySpecs) {
          optionalAccounts.add(
            AccountInDB(
              id: generateUUID(),
              name: spec.name,
              displayOrder: spec.order,
              type: AccountType.normal,
              currencyId: spec.currencyId,
              iniValue: 0,
              date: now,
              iconId: spec.iconId,
              color: spec.color,
            ),
          );
        }
        if (wantsAlsoUsd) {
          // The legacy USD twin uses the bank's display name + " USD".
          // The first legacy spec drives the icon/color so the twin looks
          // like the primary tile.
          final primary = legacySpecs.first;
          optionalAccounts.add(
            AccountInDB(
              id: generateUUID(),
              name: '${bank.name} USD',
              displayOrder: primary.order + 1,
              type: AccountType.normal,
              currencyId: 'USD',
              iniValue: 0,
              date: now,
              iconId: primary.iconId,
              color: primary.color,
            ),
          );
        }
        continue;
      }

      // Generic path: one account in the bank's native currency. If the
      // user asked for both currencies, suffix the VES account with " Bs"
      // and add a second " USD" account.
      final colorHex = _hexFromColor(bank.color);
      final iconId = _iconIdFromBank(bank);
      final baseOrder = displayOrderCounter;
      displayOrderCounter += 2;

      if (wantsAlsoUsd) {
        optionalAccounts.add(
          AccountInDB(
            id: generateUUID(),
            name: '${bank.name} Bs',
            displayOrder: baseOrder,
            type: AccountType.normal,
            currencyId: 'VES',
            iniValue: 0,
            date: now,
            iconId: iconId,
            color: colorHex,
          ),
        );
        optionalAccounts.add(
          AccountInDB(
            id: generateUUID(),
            name: '${bank.name} USD',
            displayOrder: baseOrder + 1,
            type: AccountType.normal,
            currencyId: 'USD',
            iniValue: 0,
            date: now,
            iconId: iconId,
            color: colorHex,
          ),
        );
      } else {
        optionalAccounts.add(
          AccountInDB(
            id: generateUUID(),
            name: bank.name,
            displayOrder: baseOrder,
            type: AccountType.normal,
            currencyId: bank.defaultCurrency,
            iniValue: 0,
            date: now,
            iconId: iconId,
            color: colorHex,
          ),
        );
      }
    }

    // ── Always-on accounts ──────────────────────────────────────────────
    final alwaysOnAccounts = <AccountInDB>[
      AccountInDB(
        id: generateUUID(),
        name: 'Efectivo USD',
        displayOrder: 20,
        type: AccountType.normal,
        currencyId: 'USD',
        iniValue: 0,
        date: now,
        iconId: 'wallet',
        color: '388E3C',
      ),
      AccountInDB(
        id: generateUUID(),
        name: 'Efectivo Bs',
        displayOrder: 21,
        type: AccountType.normal,
        currencyId: 'VES',
        iniValue: 0,
        date: now,
        iconId: 'wallet',
        color: '795548',
      ),
    ];

    final accounts = [...optionalAccounts, ...alwaysOnAccounts];

    for (final acc in accounts) {
      await AccountService.instance.insertAccount(acc);
    }

    Logger.printDebug(
      '[PersonalVESeeder] Inserted ${accounts.length} accounts.',
    );
  }

  /// Convert a Flutter [Color] to the 6-character hex string the DB stores
  /// (no leading `#`, no alpha component).
  static String _hexFromColor(Color color) {
    // Use the deprecated-free 8-bit channel accessors; mask out alpha.
    final int rgb = color.toARGB32() & 0x00FFFFFF;
    return rgb.toRadixString(16).padLeft(6, '0').toUpperCase();
  }

  /// Map a [BankOption.icon] to the lowercase Material icon name the DB
  /// stores. Falls back to `'account_balance'` for unrecognised icons.
  static String _iconIdFromBank(BankOption bank) {
    final icon = bank.icon;
    if (icon == Icons.wallet) return 'wallet';
    if (icon == Icons.payment) return 'payment';
    if (icon == Icons.currency_bitcoin) return 'universal_currency_alt';
    if (icon == Icons.account_balance_wallet) return 'wallet';
    return 'account_balance';
  }

  // ====================================================================
  // Categories  (income + hierarchical expense)
  // ====================================================================

  static Future<void> _seedCategories() async {
    // We use custom SQL insert (same pattern as CategoryService.initializeCategories)
    // to avoid issues with Drift companion types.
    final db = AppDB.instance;

    // ── Income categories ──────────────────────────────────────────────
    final incomeCategories = <_SeedCategory>[
      _SeedCategory(
        id: 'pve_i01',
        name: 'Salario BIGWISE',
        iconId: 'work',
        color: '1976D2',
        type: CategoryType.I,
        order: 1,
      ),
      _SeedCategory(
        id: 'pve_i02',
        name: 'Freelance Upwork',
        iconId: 'laptop_mac',
        color: '43A047',
        type: CategoryType.I,
        order: 2,
      ),
      _SeedCategory(
        id: 'pve_i03',
        name: 'Venta de USD',
        iconId: 'universal_currency_alt',
        color: 'FB8C00',
        type: CategoryType.I,
        order: 3,
      ),
      _SeedCategory(
        id: 'pve_i04',
        name: 'Otros Ingresos',
        iconId: 'payments',
        color: '757575',
        type: CategoryType.I,
        order: 4,
      ),
    ];

    // ── Expense categories (parent + children) ─────────────────────────
    final expenseCategories = <_SeedCategory>[
      // 1. Alimentacion
      _SeedCategory(
        id: 'pve_e01',
        name: 'Alimentacion',
        iconId: 'restaurant',
        color: '7CB342',
        type: CategoryType.E,
        order: 10,
        children: [
          _SeedCategory(
            id: 'pve_e01_1',
            name: 'Mercado',
            iconId: 'grocery',
            order: 1,
          ),
          _SeedCategory(
            id: 'pve_e01_2',
            name: 'Restaurantes',
            iconId: 'dinner_dining',
            order: 2,
          ),
          _SeedCategory(
            id: 'pve_e01_3',
            name: 'Delivery',
            iconId: 'fastfood',
            order: 3,
          ),
        ],
      ),
      // 2. Transporte
      _SeedCategory(
        id: 'pve_e02',
        name: 'Transporte',
        iconId: 'transportation',
        color: '1976D2',
        type: CategoryType.E,
        order: 20,
        children: [
          _SeedCategory(
            id: 'pve_e02_1',
            name: 'Gasolina',
            iconId: 'ev_station',
            order: 1,
          ),
          _SeedCategory(
            id: 'pve_e02_2',
            name: 'Uber/Taxi',
            iconId: 'local_taxi',
            order: 2,
          ),
          _SeedCategory(
            id: 'pve_e02_3',
            name: 'Transporte publico',
            iconId: 'tram',
            order: 3,
          ),
        ],
      ),
      // 3. Vivienda
      _SeedCategory(
        id: 'pve_e03',
        name: 'Vivienda',
        iconId: 'home',
        color: '6D4C41',
        type: CategoryType.E,
        order: 30,
        children: [
          _SeedCategory(
            id: 'pve_e03_1',
            name: 'Alquiler',
            iconId: 'home_work',
            order: 1,
          ),
          _SeedCategory(
            id: 'pve_e03_2',
            name: 'Servicios',
            iconId: 'bolt',
            order: 2,
          ),
          _SeedCategory(
            id: 'pve_e03_3',
            name: 'Mantenimiento',
            iconId: 'sprinkler',
            order: 3,
          ),
        ],
      ),
      // 4. Salud
      _SeedCategory(
        id: 'pve_e04',
        name: 'Salud',
        iconId: 'ecg_heart',
        color: 'E53935',
        type: CategoryType.E,
        order: 40,
        children: [
          _SeedCategory(
            id: 'pve_e04_1',
            name: 'Consultas',
            iconId: 'cardiology',
            order: 1,
          ),
          _SeedCategory(
            id: 'pve_e04_2',
            name: 'Medicinas',
            iconId: 'medication',
            order: 2,
          ),
          _SeedCategory(
            id: 'pve_e04_3',
            name: 'Seguro',
            iconId: 'prescriptions',
            order: 3,
          ),
        ],
      ),
      // 5. Entretenimiento
      _SeedCategory(
        id: 'pve_e05',
        name: 'Entretenimiento',
        iconId: 'movie',
        color: '8E24AA',
        type: CategoryType.E,
        order: 50,
        children: [
          _SeedCategory(
            id: 'pve_e05_1',
            name: 'Suscripciones',
            iconId: 'confirmation_number',
            order: 1,
          ),
          _SeedCategory(
            id: 'pve_e05_2',
            name: 'Salidas',
            iconId: 'celebration',
            order: 2,
          ),
          _SeedCategory(
            id: 'pve_e05_3',
            name: 'Hobbies',
            iconId: 'brush',
            order: 3,
          ),
        ],
      ),
      // 6. Educacion
      _SeedCategory(
        id: 'pve_e06',
        name: 'Educacion',
        iconId: 'school',
        color: '283593',
        type: CategoryType.E,
        order: 60,
        children: [
          _SeedCategory(
            id: 'pve_e06_1',
            name: 'Cursos',
            iconId: 'cast_for_education',
            order: 1,
          ),
          _SeedCategory(
            id: 'pve_e06_2',
            name: 'Libros',
            iconId: 'menu_book',
            order: 2,
          ),
        ],
      ),
      // 7. Ropa
      _SeedCategory(
        id: 'pve_e07',
        name: 'Ropa',
        iconId: 'checkroom',
        color: 'AD1457',
        type: CategoryType.E,
        order: 70,
      ),
      // 8. Tecnologia
      _SeedCategory(
        id: 'pve_e08',
        name: 'Tecnologia',
        iconId: 'devices',
        color: '00ACC1',
        type: CategoryType.E,
        order: 80,
        children: [
          _SeedCategory(
            id: 'pve_e08_1',
            name: 'Hardware',
            iconId: 'computer',
            order: 1,
          ),
          _SeedCategory(
            id: 'pve_e08_2',
            name: 'Software',
            iconId: 'laptop_windows',
            order: 2,
          ),
          _SeedCategory(
            id: 'pve_e08_3',
            name: 'Cloud',
            iconId: 'desktop_cloud_stack',
            order: 3,
          ),
        ],
      ),
      // 9. Familia/Regalos
      _SeedCategory(
        id: 'pve_e09',
        name: 'Familia/Regalos',
        iconId: 'redeem',
        color: 'FDD835',
        type: CategoryType.E,
        order: 90,
      ),
      // 10. Comisiones bancarias
      _SeedCategory(
        id: 'pve_e10',
        name: 'Comisiones bancarias',
        iconId: 'account_balance',
        color: '546E7A',
        type: CategoryType.E,
        order: 100,
      ),
      // 11. Ahorros
      _SeedCategory(
        id: 'pve_e11',
        name: 'Ahorros',
        iconId: 'savings',
        color: '0277BD',
        type: CategoryType.E,
        order: 105,
      ),
      // 12. Otros Gastos
      _SeedCategory(
        id: 'pve_e12',
        name: 'Otros Gastos',
        iconId: 'question_mark',
        color: '9E9E9E',
        type: CategoryType.E,
        order: 110,
      ),
    ];

    int insertedCount = 0;

    // Insert income categories
    for (final cat in incomeCategories) {
      await _insertCategory(db, cat);
      insertedCount++;
    }

    // Insert expense categories (with children)
    for (final cat in expenseCategories) {
      await _insertCategory(db, cat);
      insertedCount++;

      if (cat.children != null) {
        for (final child in cat.children!) {
          await _insertCategory(db, child, parentId: cat.id);
          insertedCount++;
        }
      }
    }

    Logger.printDebug(
      '[PersonalVESeeder] Inserted $insertedCount categories.',
    );
  }

  /// Inserts a single category via raw SQL (same pattern as
  /// [CategoryService.initializeCategories]).
  static Future<void> _insertCategory(
    AppDB db,
    _SeedCategory cat, {
    String? parentId,
  }) async {
    final safeName = cat.name.replaceAll("'", "''");
    final typeValue = cat.type?.name;
    final colorValue = cat.color;

    // Build the SQL based on whether we have a parent, type, and color
    if (parentId != null) {
      // Sub-category — inherits type and color from parent
      await db.customStatement("""
        INSERT OR IGNORE INTO categories(id, name, iconId, parentCategoryID, displayOrder)
        VALUES (
          '${cat.id}',
          '$safeName',
          '${cat.iconId}',
          '$parentId',
          ${cat.order}
        )
      """);
    } else {
      // Parent / top-level category
      await db.customStatement("""
        INSERT OR IGNORE INTO categories(id, name, iconId, color, type, displayOrder)
        VALUES (
          '${cat.id}',
          '$safeName',
          '${cat.iconId}',
          ${colorValue != null ? "'$colorValue'" : 'NULL'},
          ${typeValue != null ? "'$typeValue'" : 'NULL'},
          ${cat.order}
        )
      """);
    }
  }

  // ====================================================================
  // Tags
  // ====================================================================

  static Future<void> _seedTags() async {
    final tags = <TagInDB>[
      const TagInDB(
        id: 'pve_tag_bigwise',
        name: 'bigwise',
        color: '1565C0',
        displayOrder: 1,
      ),
      const TagInDB(
        id: 'pve_tag_upwork',
        name: 'upwork',
        color: '43A047',
        displayOrder: 2,
      ),
      const TagInDB(
        id: 'pve_tag_personal',
        name: 'personal',
        color: '7B1FA2',
        displayOrder: 3,
      ),
      const TagInDB(
        id: 'pve_tag_pareja',
        name: 'pareja',
        color: 'E91E63',
        displayOrder: 4,
      ),
      const TagInDB(
        id: 'pve_tag_emergencia',
        name: 'emergencia',
        color: 'D32F2F',
        displayOrder: 5,
      ),
      const TagInDB(
        id: 'pve_tag_inversion',
        name: 'inversion',
        color: 'FF8F00',
        displayOrder: 6,
      ),
      const TagInDB(
        id: 'pve_tag_binance',
        name: 'binance',
        color: 'F9A825',
        displayOrder: 7,
      ),
    ];

    for (final tag in tags) {
      await TagService.instance.insertTag(tag);
    }

    Logger.printDebug('[PersonalVESeeder] Inserted ${tags.length} tags.');
  }
}

// ======================================================================
// Internal helper model for defining seed categories compactly
// ======================================================================

class _SeedCategory {
  final String id;
  final String name;
  final String iconId;
  final String? color;
  final CategoryType? type;
  final int order;
  final List<_SeedCategory>? children;

  const _SeedCategory({
    required this.id,
    required this.name,
    required this.iconId,
    this.color,
    this.type,
    required this.order,
    this.children,
  });
}

/// Snapshot of the historical hardcoded account definitions for banks whose
/// names must be preserved verbatim. New banks added to [kBanks] without a
/// legacy spec fall back to the generic naming scheme.
class _LegacyAccountSpec {
  final String name;
  final String currencyId;
  final String iconId;
  final String color;
  final int order;

  const _LegacyAccountSpec({
    required this.name,
    required this.currencyId,
    required this.iconId,
    required this.color,
    required this.order,
  });
}
