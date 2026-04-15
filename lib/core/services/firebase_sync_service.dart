import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:drift/drift.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:wallex/core/database/app_db.dart';
import 'package:wallex/core/database/services/account/account_service.dart';
import 'package:wallex/core/database/services/category/category_service.dart';
import 'package:wallex/core/database/services/exchange-rate/exchange_rate_service.dart';
import 'package:wallex/core/database/services/transaction/transaction_service.dart';
import 'package:wallex/core/database/services/user-setting/user_setting_service.dart';
import 'package:wallex/core/models/account/account.dart';
import 'package:wallex/core/models/category/category.dart';
import 'package:wallex/core/models/transaction/transaction_status.enum.dart';
import 'package:wallex/core/models/transaction/transaction_type.enum.dart';
import 'package:wallex/core/utils/logger.dart';

/// Service that syncs local data to Firestore for multi-device sharing.
///
/// Gated behind [SettingKey.firebaseSyncEnabled]. When disabled (default),
/// all sync operations are no-ops and the app works fully offline.
/// Uses per-user Firestore paths: `users/{uid}/...`
class FirebaseSyncService {
  FirebaseSyncService._();
  static final FirebaseSyncService instance = FirebaseSyncService._();

  FirebaseFirestore? _firestore;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  bool _initialized = false;

  /// Whether Firebase is initialized AND sync is enabled.
  bool get isFirebaseAvailable => _initialized;

  /// Check if Firebase core has been initialized (app-level).
  bool get _isFirebaseCoreReady {
    try {
      Firebase.app();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Initialize the sync service.
  /// Call this after Firebase.initializeApp() in main.dart.
  /// Checks [SettingKey.firebaseSyncEnabled] — if '0' or absent, returns early.
  Future<void> initialize() async {
    if (_initialized) return;

    // Check the opt-in flag
    final syncFlag = appStateSettings[SettingKey.firebaseSyncEnabled];
    if (syncFlag != '1') {
      Logger.printDebug(
        'FirebaseSyncService: sync disabled (flag=$syncFlag), skipping init',
      );
      return;
    }

    // Check that Firebase core is actually available
    if (!_isFirebaseCoreReady) {
      Logger.printDebug(
        'FirebaseSyncService: Firebase core not initialized, skipping',
      );
      return;
    }

    _firestore = FirebaseFirestore.instance;
    _initialized = true;
    Logger.printDebug('FirebaseSyncService initialized');
  }

  /// Enable or disable sync at runtime. Writes the setting and updates
  /// internal state. Does NOT call Firebase.initializeApp() — that requires
  /// an app restart.
  Future<void> setSyncEnabled(bool enabled) async {
    await UserSettingService.instance.setItem(
      SettingKey.firebaseSyncEnabled,
      enabled ? '1' : '0',
    );
    if (!enabled) {
      _initialized = false;
      _firestore = null;
    }
    Logger.printDebug('FirebaseSyncService: sync ${enabled ? "enabled" : "disabled"}');
  }

  /// Get the current user's UID, or null if not logged in.
  String? get currentUserId => _auth.currentUser?.uid;

  /// Get the current user's email.
  String? get currentUserEmail => _auth.currentUser?.email;

  /// Base Firestore path for the current user: `users/{uid}`
  String get _userBasePath {
    final uid = currentUserId;
    if (uid == null) throw StateError('No user logged in');
    return 'users/$uid';
  }

  // ============================================================
  // SECURITY - Whitelist Verification
  // ============================================================

  /// Check if the current user is allowed to use sync.
  /// In the personal edition, any authenticated user is whitelisted.
  Future<bool> isUserWhitelisted() async {
    // Personal edition: if user is logged in, they are whitelisted
    return currentUserId != null;
  }

  /// Sign out the current user
  Future<void> signOut() async {
    await _auth.signOut();
    Logger.printDebug('FirebaseSyncService: User signed out');
  }

  // ============================================================
  // PUSH METHODS - Send local data to Firestore
  // ============================================================

  /// Push a transaction to Firestore (create or update)
  Future<void> pushTransaction(TransactionInDB transaction) async {
    if (!_initialized || _firestore == null) return;
    try {
      if (currentUserId == null) return;

      final docRef = _firestore!
          .collection('$_userBasePath/transactions')
          .doc(transaction.id);

      await docRef.set({
        'id': transaction.id,
        'date': transaction.date.toIso8601String(),
        'accountID': transaction.accountID,
        'receivingAccountID': transaction.receivingAccountID,
        'value': transaction.value,
        'valueInDestiny': transaction.valueInDestiny,
        'title': transaction.title,
        'notes': transaction.notes,
        'type': transaction.type.name,
        'status': transaction.status?.name,
        'categoryID': transaction.categoryID,
        'isHidden': transaction.isHidden,
        'exchangeRateApplied': transaction.exchangeRateApplied,
        'exchangeRateSource': transaction.exchangeRateSource,
        'intervalEach': transaction.intervalEach,
        'intervalPeriod': transaction.intervalPeriod?.name,
        'endDate': transaction.endDate?.toIso8601String(),
        'remainingTransactions': transaction.remainingTransactions,
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': currentUserEmail,
      });

      Logger.printDebug(
        'FirebaseSyncService: Pushed transaction ${transaction.id}',
      );
    } catch (e) {
      Logger.printDebug('FirebaseSyncService: Error pushing transaction: $e');
    }
  }

  /// Delete a transaction from Firestore
  Future<void> deleteTransaction(String transactionId) async {
    if (!_initialized || _firestore == null) return;
    try {
      if (currentUserId == null) return;

      await _firestore!
          .collection('$_userBasePath/transactions')
          .doc(transactionId)
          .delete();

      Logger.printDebug(
        'FirebaseSyncService: Deleted transaction $transactionId',
      );
    } catch (e) {
      Logger.printDebug('FirebaseSyncService: Error deleting transaction: $e');
    }
  }

  /// Push an account to Firestore
  Future<void> pushAccount(AccountInDB account) async {
    if (!_initialized || _firestore == null) return;
    try {
      if (currentUserId == null) return;

      final docRef = _firestore!
          .collection('$_userBasePath/accounts')
          .doc(account.id);

      await docRef.set({
        'id': account.id,
        'name': account.name,
        'iniValue': account.iniValue,
        'date': account.date.toIso8601String(),
        'description': account.description,
        'type': account.type.name,
        'iconId': account.iconId,
        'displayOrder': account.displayOrder,
        'color': account.color,
        'closingDate': account.closingDate?.toIso8601String(),
        'currencyId': account.currencyId,
        'iban': account.iban,
        'swift': account.swift,
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': currentUserEmail,
      });

      Logger.printDebug('FirebaseSyncService: Pushed account ${account.id}');
    } catch (e) {
      Logger.printDebug('FirebaseSyncService: Error pushing account: $e');
    }
  }

  /// Push a category to Firestore
  Future<void> pushCategory(CategoryInDB category) async {
    if (!_initialized || _firestore == null) return;
    try {
      if (currentUserId == null) return;

      final docRef = _firestore!
          .collection('$_userBasePath/categories')
          .doc(category.id);

      await docRef.set({
        'id': category.id,
        'name': category.name,
        'iconId': category.iconId,
        'color': category.color,
        'displayOrder': category.displayOrder,
        'type': category.type?.name,
        'parentCategoryID': category.parentCategoryID,
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': currentUserEmail,
      });

      Logger.printDebug('FirebaseSyncService: Pushed category ${category.id}');
    } catch (e) {
      Logger.printDebug('FirebaseSyncService: Error pushing category: $e');
    }
  }

  /// Push an exchange rate to Firestore
  Future<void> pushExchangeRate(ExchangeRateInDB rate) async {
    if (!_initialized || _firestore == null) return;
    try {
      if (currentUserId == null) return;

      final docRef = _firestore!
          .collection('$_userBasePath/exchangeRates')
          .doc(rate.id);

      await docRef.set({
        'id': rate.id,
        'date': rate.date.toIso8601String(),
        'currencyCode': rate.currencyCode,
        'exchangeRate': rate.exchangeRate,
        'source': rate.source,
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': currentUserEmail,
      });

      Logger.printDebug('FirebaseSyncService: Pushed exchange rate ${rate.id}');
    } catch (e) {
      Logger.printDebug('FirebaseSyncService: Error pushing exchange rate: $e');
    }
  }

  // ============================================================
  // PULL METHODS - Fetch data from Firestore to local DB
  // ============================================================

  /// Pull all user data from Firestore and merge with local DB.
  /// Uses last-write-wins strategy based on updatedAt timestamp.
  /// Returns a map with counts of pulled items and first error message.
  Future<Map<String, dynamic>> pullAllData() async {
    final result = <String, dynamic>{
      'accounts': 0,
      'categories': 0,
      'exchangeRates': 0,
      'transactions': 0,
      'errors': 0,
      'firstError': '',
    };

    if (!_initialized || _firestore == null) return result;

    try {
      if (currentUserId == null) {
        Logger.printDebug(
          'FirebaseSyncService: No user logged in, skipping pull',
        );
        return result;
      }

      Logger.printDebug('FirebaseSyncService: Starting data pull...');

      // Pull accounts first (transactions depend on them)
      final accResult = await _pullAccounts();
      result['accounts'] = accResult['success'] ?? 0;
      int totalErrors = (accResult['errors'] as int?) ?? 0;
      String firstError = (accResult['firstError'] as String?) ?? '';

      // Pull categories (transactions depend on them)
      result['categories'] = await _pullCategories();

      // Pull exchange rates
      result['exchangeRates'] = await _pullExchangeRates();

      // Pull transactions
      final txResult = await _pullTransactions();
      result['transactions'] = txResult['success'] ?? 0;
      totalErrors += (txResult['errors'] as int?) ?? 0;
      if (firstError.isEmpty) {
        firstError = 'Tx: ${txResult['firstError'] ?? ''}';
      }
      result['errors'] = totalErrors;
      result['firstError'] = firstError;

      Logger.printDebug(
        'FirebaseSyncService: Data pull completed! '
        'Accounts: ${result['accounts']}, '
        'Categories: ${result['categories']}, '
        'Transactions: ${result['transactions']}, '
        'Errors: ${result['errors']}',
      );
    } catch (e) {
      Logger.printDebug('FirebaseSyncService: Error pulling data: $e');
      result['errors'] = -1; // Indicate general error
    }

    return result;
  }

  Future<Map<String, dynamic>> _pullAccounts() async {
    final snapshot = await _firestore!
        .collection('$_userBasePath/accounts')
        .get();

    final db = AppDB.instance;

    int successCount = 0;
    int errorCount = 0;
    String firstError = '';

    Logger.printDebug(
      'FirebaseSyncService: Found ${snapshot.docs.length} accounts in Firebase',
    );

    for (final doc in snapshot.docs) {
      try {
        final data = doc.data();
        final accountName = data['name'] as String;
        final accountId = data['id'] as String;

        Logger.printDebug('FirebaseSyncService: Parsing account ${doc.id}');

        // Find any local account with the same NAME but different ID
        final conflictingAccounts =
            await (db.select(db.accounts)
                  ..where((a) => a.name.equals(accountName))
                  ..where((a) => a.id.equals(accountId).not()))
                .get();

        // Migrate transactions from old account ID to new Firebase account ID
        for (final oldAccount in conflictingAccounts) {
          // Update transactions to point to the new Firebase account ID
          await db.customStatement(
            'UPDATE transactions SET accountID = ? WHERE accountID = ?',
            [accountId, oldAccount.id],
          );

          Logger.printDebug(
            'FirebaseSyncService: Migrated transactions from '
            '${oldAccount.id} to $accountId',
          );
        }

        // Now delete the conflicting accounts safely
        await (db.delete(db.accounts)
              ..where((a) => a.name.equals(accountName))
              ..where((a) => a.id.equals(accountId).not()))
            .go();

        final account = AccountInDB(
          id: accountId,
          name: accountName,
          iniValue: (data['iniValue'] as num).toDouble(),
          date: DateTime.parse(data['date'] as String),
          description: data['description'] as String?,
          type: AccountType.values.firstWhere(
            (e) => e.name == data['type'],
            orElse: () => AccountType.normal,
          ),
          iconId: data['iconId'] as String,
          displayOrder: (data['displayOrder'] as num).toInt(),
          color: data['color'] as String?,
          closingDate: data['closingDate'] != null
              ? DateTime.parse(data['closingDate'] as String)
              : null,
          currencyId: data['currencyId'] as String,
          iban: data['iban'] as String?,
          swift: data['swift'] as String?,
        );

        // Insert or update by ID
        await db.into(db.accounts).insertOnConflictUpdate(account);
        successCount++;
      } catch (e, stackTrace) {
        errorCount++;
        if (firstError.isEmpty) {
          firstError = 'Account: $e';
        }
        Logger.printDebug(
          'FirebaseSyncService: Error pulling account ${doc.id}: $e\n$stackTrace',
        );
      }
    }

    Logger.printDebug(
      'FirebaseSyncService: Pulled $successCount accounts ($errorCount errors)',
    );
    return {
      'success': successCount,
      'errors': errorCount,
      'firstError': firstError,
    };
  }

  Future<int> _pullCategories() async {
    final snapshot = await _firestore!
        .collection('$_userBasePath/categories')
        .get();

    final db = AppDB.instance;
    int successCount = 0;

    for (final doc in snapshot.docs) {
      try {
        final data = doc.data();

        final category = CategoryInDB(
          id: data['id'] as String,
          name: data['name'] as String,
          iconId: data['iconId'] as String,
          color: data['color'] as String?,
          displayOrder: data['displayOrder'] as int? ?? 0,
          type: CategoryType.values.firstWhere(
            (e) => e.name == data['type'],
            orElse: () => CategoryType.E,
          ),
          parentCategoryID: data['parentCategoryID'] as String?,
        );

        await db.into(db.categories).insertOnConflictUpdate(category);
        successCount++;
      } catch (e) {
        Logger.printDebug(
          'FirebaseSyncService: Error pulling category ${doc.id}: $e',
        );
      }
    }

    Logger.printDebug('FirebaseSyncService: Pulled $successCount categories');
    return successCount;
  }

  Future<int> _pullExchangeRates() async {
    final snapshot = await _firestore!
        .collection('$_userBasePath/exchangeRates')
        .get();

    final db = AppDB.instance;
    int successCount = 0;

    for (final doc in snapshot.docs) {
      try {
        final data = doc.data();

        final rate = ExchangeRateInDB(
          id: data['id'] as String,
          date: DateTime.parse(data['date'] as String),
          currencyCode: data['currencyCode'] as String,
          exchangeRate: (data['exchangeRate'] as num).toDouble(),
          source: data['source'] as String?,
        );

        await db.into(db.exchangeRates).insertOnConflictUpdate(rate);
        successCount++;
      } catch (e) {
        Logger.printDebug(
          'FirebaseSyncService: Error pulling exchange rate ${doc.id}: $e',
        );
      }
    }

    Logger.printDebug(
      'FirebaseSyncService: Pulled $successCount exchange rates',
    );
    return successCount;
  }

  Future<Map<String, dynamic>> _pullTransactions() async {
    final snapshot = await _firestore!
        .collection('$_userBasePath/transactions')
        .get();

    final db = AppDB.instance;
    int successCount = 0;
    int errorCount = 0;
    String firstError = '';

    for (final doc in snapshot.docs) {
      try {
        final data = doc.data();
        final accountId = data['accountID'] as String;

        // Check if referenced account exists locally
        final accountExists = await (db.select(
          db.accounts,
        )..where((a) => a.id.equals(accountId))).getSingleOrNull();

        // If account doesn't exist (orphan transaction), create a placeholder
        // so the user doesn't lose the transaction data.
        if (accountExists == null) {
          Logger.printDebug(
            'FirebaseSyncService: Orphan transaction $accountId. Creating placeholder.',
          );

          final placeholderAccount = AccountInDB(
            id: accountId,
            name: 'Cuenta Recuperada',
            type: AccountType.normal,
            iconId: 'help_outline',
            iniValue: 0.0,
            date: DateTime.now(),
            displayOrder: 999,
            currencyId: 'USD', // Default fallback
          );

          await db.into(db.accounts).insertOnConflictUpdate(placeholderAccount);
        }

        final transaction = TransactionInDB(
          id: data['id'] as String,
          date: DateTime.parse(data['date'] as String),
          accountID: data['accountID'] as String,
          receivingAccountID: data['receivingAccountID'] as String?,
          value: (data['value'] as num).toDouble(),
          valueInDestiny: data['valueInDestiny'] != null
              ? (data['valueInDestiny'] as num).toDouble()
              : null,
          title: data['title'] as String?,
          notes: data['notes'] as String?,
          type: TransactionType.values.firstWhere(
            (e) => e.name == data['type'],
            orElse: () => TransactionType.expense,
          ),
          status: data['status'] != null
              ? TransactionStatus.values.firstWhere(
                  (e) => e.name == data['status'],
                  orElse: () => TransactionStatus.reconciled,
                )
              : TransactionStatus.reconciled,
          categoryID: data['categoryID'] as String?,
          isHidden: data['isHidden'] as bool? ?? false,
          exchangeRateApplied: data['exchangeRateApplied'] != null
              ? (data['exchangeRateApplied'] as num).toDouble()
              : null,
          exchangeRateSource: data['exchangeRateSource'] as String?,
          createdAt: data['createdAt'] != null
              ? DateTime.parse(data['createdAt'] as String)
              : DateTime.now(),
          intervalEach: data['intervalEach'] as int?,
          intervalPeriod: null, // Simplified for personal use
          endDate: data['endDate'] != null
              ? DateTime.parse(data['endDate'] as String)
              : null,
          remainingTransactions: data['remainingTransactions'] as int?,
        );

        await db.into(db.transactions).insertOnConflictUpdate(transaction);
        successCount++;
      } catch (e) {
        errorCount++;
        if (firstError.isEmpty) {
          firstError = '$e';
        }
        Logger.printDebug(
          'FirebaseSyncService: Error pulling transaction ${doc.id}: $e',
        );
      }
    }

    Logger.printDebug(
      'FirebaseSyncService: Pulled $successCount transactions '
      '($errorCount errors)',
    );
    return {
      'success': successCount,
      'errors': errorCount,
      'firstError': firstError,
    };
  }

  // ============================================================
  // PUSH ALL - Upload all local data to Firestore
  // ============================================================

  /// Push all local data to Firestore (useful for initial sync)
  Future<void> pushAllData() async {
    if (!_initialized || _firestore == null) return;
    try {
      if (currentUserId == null) {
        Logger.printDebug(
          'FirebaseSyncService: No user logged in, skipping push',
        );
        return;
      }

      Logger.printDebug('FirebaseSyncService: Starting full data push...');

      // Push accounts
      final accounts = await AccountService.instance.getAccounts().first;
      for (final account in accounts) {
        await pushAccount(
          AccountInDB(
            id: account.id,
            name: account.name,
            iniValue: account.iniValue,
            date: account.date,
            description: account.description,
            type: account.type,
            iconId: account.iconId,
            displayOrder: account.displayOrder,
            color: account.color,
            closingDate: account.closingDate,
            currencyId: account.currency.code,
            iban: account.iban,
            swift: account.swift,
          ),
        );
      }

      // Push categories
      final categories = await CategoryService.instance.getCategories().first;
      for (final category in categories) {
        await pushCategory(
          CategoryInDB(
            id: category.id,
            name: category.name,
            iconId: category.iconId,
            color: category.color,
            displayOrder: category.displayOrder,
            type: category.type,
            parentCategoryID: category.parentCategory?.id,
          ),
        );
      }

      // Push transactions
      final transactions = await TransactionService.instance
          .getTransactions()
          .first;
      for (final tx in transactions) {
        await pushTransaction(
          TransactionInDB(
            id: tx.id,
            date: tx.date,
            accountID: tx.account.id,
            receivingAccountID: tx.receivingAccount?.id,
            value: tx.value,
            valueInDestiny: tx.valueInDestiny,
            title: tx.title,
            notes: tx.notes,
            type: tx.type,
            status: tx.status,
            categoryID: tx.category?.id,
            isHidden: tx.isHidden,
            exchangeRateApplied: tx.exchangeRateApplied,
            exchangeRateSource: tx.exchangeRateSource,
            createdAt: DateTime.now(),
            intervalEach: tx.recurrentInfo.intervalEach,
            intervalPeriod: tx.recurrentInfo.intervalPeriod,
            endDate: tx.recurrentInfo.ruleRecurrentLimit?.endDate,
            remainingTransactions:
                tx.recurrentInfo.ruleRecurrentLimit?.remainingIterations,
          ),
        );
      }

      // Push exchange rates
      final rates = await ExchangeRateService.instance.getExchangeRates().first;
      for (final rate in rates) {
        await pushExchangeRate(rate);
      }

      Logger.printDebug('FirebaseSyncService: Full data push completed!');
    } catch (e) {
      Logger.printDebug('FirebaseSyncService: Error in full push: $e');
    }
  }
}
