import 'package:wallex/core/database/app_db.dart';
import 'package:wallex/core/database/services/shared/key_value_pair.dart';
import 'package:wallex/core/database/services/shared/key_value_service.dart';

/// The keys of the avalaible settings of the app
enum SettingKey {
  preferredCurrency,
  userName,
  avatar,

  /// Text font to be used across the entire app. It's a string representing
  /// the font index in the font list, or `null` to use the platform font.
  font,

  /// User preferred language (locale) for the app. It's a string representing the locale languageTag, like "en", "zh-TW"...
  /// If `null`, the app will use the device locale, or the fallback locale if the device locale is not supported.
  appLanguage,

  /// Key to storage if the user will enter in the "private mode" when the app launches.
  privateModeAtLaunch,

  /// Last persisted state of the "private mode" toggle. '1' = on, '0' or null
  /// = off. This survives app restarts so the runtime toggle state persists
  /// session to session (independent of [privateModeAtLaunch], which is the
  /// user preference for forcing ON at every launch).
  privateMode,

  /// Key to storage the app theme. Could be 'system', 'light' or 'dark'
  themeMode,

  /// Key to storage the app accentColor. It's a string representing the color in HEX format (without the `#`) or the string 'auto' to apply dynamic colors if possible (if not possible will default to the Wallex brand color)
  accentColor,

  /// Key to storage if the user have the AMOLED mode activated. Could be '1' (true) or '0' (false)
  amoledMode,

  transactionSwipeLeftAction,
  transactionSwipeRightAction,

  /// Default transaction type, "E", "I" or "T" as defined in the [TransactionType] enum.
  /// The default is "E" (Expense)
  defaultTransactionType,

  /// Json string representing the default values to be used when creating a new transaction
  /// Each value could be `null` to use no default value for that field
  defaultTransactionValues,

  /// List of fields that should use the last used value when creating a new transaction.
  /// Stored as a JSON list of strings (names of [TransactionFormField] enum).
  fieldsToUseLastUsedValue,

  /// Whether to show all decimals places even if there are trailing zeros
  showAllDecimals,

  /// Whether to show the tags of the transaction in the transaction list tiles
  transactionTileShowTags,

  /// Whether to show the time of the transaction in the transaction list tiles
  transactionTileShowTime,

  /// Whether Firebase sync is enabled. '1' = enabled, '0' or null = disabled.
  /// When disabled, Firebase.initializeApp() is not called and
  /// FirebaseSyncService does not attempt any network operations.
  firebaseSyncEnabled,

  // ──── Auto-import settings ────

  /// Master toggle for the auto-import feature. '1' = enabled, '0' or null = disabled.
  autoImportEnabled,

  /// Whether SMS capture is enabled. '1' = enabled, '0' or null = disabled.
  smsImportEnabled,

  /// Whether notification listener capture is enabled. '1' = enabled, '0' or null = disabled.
  notifListenerEnabled,

  /// Whether the BDV SMS bank profile is active. '1' (default) = enabled, '0' = disabled.
  bdvSmsProfileEnabled,

  /// Whether the BDV notification bank profile is active. '1' (default) = enabled, '0' = disabled.
  bdvNotifProfileEnabled,

  /// Whether the Zinli notification bank profile is active. '1' (default) = enabled, '0' = disabled.
  zinliNotifProfileEnabled,

  /// Whether the Binance API integration is enabled. '1' = enabled, '0' or null = disabled.
  binanceApiEnabled,

  /// Whether the Binance API bank profile is active. '1' (default) = enabled, '0' = disabled.
  binanceApiProfileEnabled,

  /// Last poll timestamp (ms since epoch) for SMS capture. '0' or null = never polled.
  autoImportLastPollSms,

  /// Last poll timestamp (ms since epoch) for notification capture. '0' or null = never polled.
  autoImportLastPollNotif,

  /// Last poll timestamp (ms since epoch) for Binance API capture. '0' or null = never polled.
  autoImportLastPollBinance,

  // ──── AI settings ────

  /// Master toggle for Nexus AI features. '1' = enabled, '0' or null = disabled.
  nexusAiEnabled,

  /// Whether AI category suggestions are enabled in auto-import review.
  aiCategorizationEnabled,

  /// Whether AI chat is enabled in dashboard.
  aiChatEnabled,

  /// Whether AI spending insights are enabled in dashboard.
  aiInsightsEnabled,

  /// Whether AI budget predictions are enabled in budget cards.
  aiBudgetPredictionEnabled,

  /// Whether receipt OCR can use multimodal AI enrichment.
  /// Defaults to enabled ('1') when unset.
  receiptAiEnabled,

  /// Preferred exchange rate source for currency conversions.
  /// Values: 'bcv', 'paralelo'. Defaults to 'bcv' when null.
  preferredRateSource,

  // ──── Hidden mode settings ────

  /// Whether the "Hidden Mode" feature is active. '1' = enabled, '0' or null = disabled.
  /// When enabled + locked, savings accounts and their transactions are filtered
  /// out of dashboards, stats, and transaction lists. The PIN itself is stored
  /// separately in flutter_secure_storage (NOT in the DB) so it does not travel
  /// in backups. See [HiddenModeService].
  hiddenModeEnabled,

  /// Whether AI-driven voice capture is enabled. '1' (default when
  /// [nexusAiEnabled] is '1') exposes the FAB mic action + chat mic button.
  /// Requires BOTH [nexusAiEnabled] AND this flag to be '1'.
  aiVoiceEnabled,

  /// Goals the user selected during onboarding slide 1. Stored as a
  /// JSON-encoded `List<String>` (e.g. `["save_usd","reduce_debt"]`).
  /// `null` or missing row is interpreted as empty list.
  onboardingGoals,
}

final Map<SettingKey, String?> appStateSettings = {};

class UserSettingService
    extends KeyValueService<SettingKey, UserSettings, UserSetting> {
  UserSettingService._(AppDB db)
    : super(
        db: db,
        table: db.userSettings,
        globalStateMap: appStateSettings,
        rowToKeyPairInstance: (row) => KeyValuePairInDB.fromUserSetting(row),
        toDbRow: (x) => x.toUserSetting(),
      );

  static final UserSettingService _instance = UserSettingService._(
    AppDB.instance,
  );
  static UserSettingService get instance => _instance;

  Stream<String?> getSettingFromDB(SettingKey settingKey) {
    return (db.select(db.userSettings)
          ..where((tbl) => tbl.settingKey.equalsValue(settingKey)))
        .map((e) => e.settingValue)
        .watchSingleOrNull();
  }

  /// Resolve the on/off toggle for the bank profile identified by [profileId].
  ///
  /// Profile IDs are stable, underscore-snake-case identifiers that each
  /// [BankProfile] advertises (e.g. `bdv_sms`, `bdv_notif`, `binance_api`).
  /// Unknown profile IDs are treated as enabled — this is the safer default
  /// for new profiles added to the registry before a matching [SettingKey]
  /// is introduced.
  ///
  /// Toggle default is ON: missing/`null`/anything-other-than `'0'` == true.
  bool isProfileEnabled(String profileId) {
    final SettingKey? key;
    switch (profileId) {
      case 'bdv_sms':
        key = SettingKey.bdvSmsProfileEnabled;
        break;
      case 'bdv_notif':
        key = SettingKey.bdvNotifProfileEnabled;
        break;
      case 'binance_api':
        key = SettingKey.binanceApiProfileEnabled;
        break;
      case 'zinli_notif':
        key = SettingKey.zinliNotifProfileEnabled;
        break;
      default:
        key = null;
    }
    if (key == null) return true;
    return appStateSettings[key] != '0';
  }
}
