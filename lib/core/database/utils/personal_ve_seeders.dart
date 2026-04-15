import 'package:wallex/core/database/app_db.dart';
import 'package:wallex/core/database/services/account/account_service.dart';
import 'package:wallex/core/database/services/category/category_service.dart';
import 'package:wallex/core/database/services/tags/tags_service.dart';
import 'package:wallex/core/models/account/account.dart';
import 'package:wallex/core/models/category/category.dart';
import 'package:wallex/core/utils/logger.dart';
import 'package:wallex/core/utils/uuid.dart';

/// Seeds Ramses's personal Venezuelan bank accounts, custom income/expense
/// categories (hierarchical), and useful tags.
///
/// Idempotent: skips entirely if any accounts already exist in the database.
class PersonalVESeeder {
  /// Run the full seed: accounts, categories, and tags.
  ///
  /// Safe to call multiple times — if accounts already exist the method
  /// returns immediately without inserting anything.
  static Future<void> seedAll() async {
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

    await _seedAccounts();
    await _seedCategories();
    await _seedTags();

    Logger.printDebug('[PersonalVESeeder] Seed completed successfully.');
  }

  // ====================================================================
  // Accounts
  // ====================================================================

  static Future<void> _seedAccounts() async {
    final now = DateTime.now();

    // iconId values come from the supported_icons list (SVG assets).
    // 'account_balance' → generic bank icon (scope: money)
    // 'wallet'          → cash/wallet icon  (scope: money)
    // 'savings'         → piggy-bank icon   (scope: money)
    // 'universal_currency_alt' → multi-currency icon (scope: money)
    final accounts = <AccountInDB>[
      AccountInDB(
        id: generateUUID(),
        name: 'Banco de Venezuela',
        displayOrder: 1,
        type: AccountType.normal,
        currencyId: 'VES',
        iniValue: 0,
        date: now,
        iconId: 'account_balance',
        color: '1A237E', // dark blue – BDV brand
      ),
      AccountInDB(
        id: generateUUID(),
        name: 'Banco Nacional de Credito #1',
        displayOrder: 2,
        type: AccountType.normal,
        currencyId: 'VES',
        iniValue: 0,
        date: now,
        iconId: 'account_balance',
        color: '00838F', // teal – BNC brand
      ),
      AccountInDB(
        id: generateUUID(),
        name: 'Banco Nacional de Credito #2',
        displayOrder: 3,
        type: AccountType.normal,
        currencyId: 'VES',
        iniValue: 0,
        date: now,
        iconId: 'account_balance',
        color: '00695C', // dark teal
      ),
      AccountInDB(
        id: generateUUID(),
        name: 'Banplus',
        displayOrder: 4,
        type: AccountType.normal,
        currencyId: 'VES',
        iniValue: 0,
        date: now,
        iconId: 'account_balance',
        color: 'EF6C00', // orange – Banplus brand
      ),
      AccountInDB(
        id: generateUUID(),
        name: 'Provincial',
        displayOrder: 5,
        type: AccountType.normal,
        currencyId: 'VES',
        iniValue: 0,
        date: now,
        iconId: 'account_balance',
        color: '2E7D32', // green – Provincial brand
      ),
      AccountInDB(
        id: generateUUID(),
        name: 'Binance',
        displayOrder: 6,
        type: AccountType.normal,
        currencyId: 'USD',
        iniValue: 0,
        date: now,
        iconId: 'universal_currency_alt',
        color: 'F9A825', // Binance yellow
      ),
      AccountInDB(
        id: generateUUID(),
        name: 'Zinli',
        displayOrder: 7,
        type: AccountType.normal,
        currencyId: 'USD',
        iniValue: 0,
        date: now,
        iconId: 'credit_card',
        color: '6A1B9A', // purple – Zinli brand
      ),
      AccountInDB(
        id: generateUUID(),
        name: 'Efectivo Bs',
        displayOrder: 8,
        type: AccountType.normal,
        currencyId: 'VES',
        iniValue: 0,
        date: now,
        iconId: 'wallet',
        color: '795548', // brown
      ),
      AccountInDB(
        id: generateUUID(),
        name: 'Efectivo USD',
        displayOrder: 9,
        type: AccountType.normal,
        currencyId: 'USD',
        iniValue: 0,
        date: now,
        iconId: 'wallet',
        color: '388E3C', // green
      ),
      AccountInDB(
        id: generateUUID(),
        name: 'Ahorro USD',
        displayOrder: 10,
        type: AccountType.saving,
        currencyId: 'USD',
        iniValue: 0,
        date: now,
        iconId: 'savings',
        color: '0277BD', // light blue
      ),
    ];

    for (final acc in accounts) {
      await AccountService.instance.insertAccount(acc);
    }

    Logger.printDebug(
      '[PersonalVESeeder] Inserted ${accounts.length} accounts.',
    );
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
      // 11. Otros Gastos
      _SeedCategory(
        id: 'pve_e11',
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
