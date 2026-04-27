import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:drift/drift.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wallex/core/database/app_db.dart';
import 'package:wallex/core/database/services/account/account_service.dart';
import 'package:wallex/core/database/services/category/category_service.dart';
import 'package:wallex/core/database/services/exchange-rate/exchange_rate_service.dart';
import 'package:wallex/core/database/services/transaction/transaction_service.dart';
import 'package:wallex/core/database/services/user-setting/hidden_mode_service.dart';
import 'package:wallex/core/database/services/shared/key_value_service.dart'
    show onGlobalAppStateRefresh;
import 'package:wallex/core/database/services/user-setting/user_setting_service.dart';
import 'package:wallex/core/models/account/account.dart';
import 'package:wallex/core/models/category/category.dart';
import 'package:wallex/core/models/transaction/transaction_status.enum.dart';
import 'package:wallex/core/models/transaction/transaction_type.enum.dart';
import 'package:wallex/core/services/ai/ai_credentials.dart';
import 'package:wallex/core/services/ai/ai_credentials_store.dart';
import 'package:wallex/core/services/ai/ai_provider_type.dart';
import 'package:wallex/core/services/attachments/attachment_model.dart';
import 'package:wallex/core/services/attachments/attachments_service.dart';
import 'package:wallex/core/services/auto_import/binance/binance_credentials_store.dart';
import 'package:wallex/core/services/firebase_credentials_cipher.dart';
import 'package:wallex/core/utils/logger.dart';
import 'package:wallex/core/utils/uuid.dart';

/// Service that syncs local data to Firestore for multi-device sharing.
///
/// Gated behind [SettingKey.firebaseSyncEnabled]. When disabled (default),
/// all sync operations are no-ops and the app works fully offline.
/// Uses per-user Firestore paths: `users/{uid}/...`
class FirebaseSyncService {
  FirebaseSyncService._();
  static final FirebaseSyncService instance = FirebaseSyncService._();

  FirebaseFirestore? _firestore;
  FirebaseAuth? _auth;
  FirebaseAuth get auth {
    _auth ??= FirebaseAuth.instance;
    return _auth!;
  }

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
  /// Always initializes if Firebase core is ready (no opt-in flag).
  Future<void> initialize() async {
    if (_initialized) return;

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
    } else {
      await initialize();
    }
    Logger.printDebug('FirebaseSyncService: sync ${enabled ? "enabled" : "disabled"}');
  }

  /// Get the current user's UID, or null if not logged in.
  String? get currentUserId => _isFirebaseCoreReady ? auth.currentUser?.uid : null;

  /// Get the current user's email.
  String? get currentUserEmail => _isFirebaseCoreReady ? auth.currentUser?.email : null;

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
    await auth.signOut();
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

  /// Delete an account from Firestore
  Future<void> deleteAccount(String accountId) async {
    if (!_initialized || _firestore == null) return;
    try {
      if (currentUserId == null) return;

      await _firestore!
          .collection('$_userBasePath/accounts')
          .doc(accountId)
          .delete();

      Logger.printDebug(
        'FirebaseSyncService: Deleted account $accountId',
      );
    } catch (e) {
      Logger.printDebug('FirebaseSyncService: Error deleting account: $e');
    }
  }

  /// Push a category to Firestore.
  ///
  /// Defensive normalization: the DB CHECK constraint enforces XOR between
  /// `parentCategoryID` and (`color`, `type`). Subcategories MUST have
  /// null color/type. We normalize here so no buggy caller (e.g. a caller
  /// that accidentally passed a [Category] whose getters fall back to the
  /// parent's values) can poison Firestore with bad data.
  Future<void> pushCategory(CategoryInDB category) async {
    if (!_initialized || _firestore == null) return;
    try {
      if (currentUserId == null) return;

      final docRef = _firestore!
          .collection('$_userBasePath/categories')
          .doc(category.id);

      final isSubcategory = category.parentCategoryID != null;
      // Force subcategory color/type to null no matter what was passed in.
      final effectiveColor = isSubcategory ? null : category.color;
      final effectiveType = isSubcategory ? null : category.type?.name;

      await docRef.set({
        'id': category.id,
        'name': category.name,
        'iconId': category.iconId,
        'color': effectiveColor,
        'displayOrder': category.displayOrder,
        'type': effectiveType,
        'parentCategoryID': category.parentCategoryID,
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': currentUserEmail,
      });

      Logger.printDebug('FirebaseSyncService: Pushed category ${category.id}');
    } catch (e) {
      Logger.printDebug('FirebaseSyncService: Error pushing category: $e');
    }
  }

  /// Delete a category from Firestore
  Future<void> deleteCategory(String categoryId) async {
    if (!_initialized || _firestore == null) return;
    try {
      if (currentUserId == null) return;

      await _firestore!
          .collection('$_userBasePath/categories')
          .doc(categoryId)
          .delete();

      Logger.printDebug(
        'FirebaseSyncService: Deleted category $categoryId',
      );
    } catch (e) {
      Logger.printDebug('FirebaseSyncService: Error deleting category: $e');
    }
  }

  // ============================================================
  // USER SETTINGS - whole-table sync (last-write-wins)
  // ============================================================

  /// Keys excluded from sync. `firebaseSyncEnabled` is device-specific
  /// (otherwise disabling sync on one device would disable it on all).
  /// Any key name containing secret-ish substrings is also filtered
  /// defensively, though real credentials live in FlutterSecureStorage.
  static const Set<SettingKey> _userSettingsSyncExclusions = {
    SettingKey.firebaseSyncEnabled,
  };

  bool _isSensitiveSettingKey(String keyName) {
    final lower = keyName.toLowerCase();
    return lower.contains('apikey') ||
        lower.contains('secret') ||
        lower.contains('token') ||
        lower.contains('password');
  }

  /// Push the whole `userSettings` table to Firestore as a single doc.
  /// Path: `users/{uid}/userSettings/all`, shape: `{ values: {key: value} }`.
  Future<void> pushUserSettings() async {
    if (!_initialized || _firestore == null) return;
    try {
      if (currentUserId == null) return;

      final db = AppDB.instance;
      final rows = await db.select(db.userSettings).get();

      final values = <String, String?>{};
      for (final row in rows) {
        if (_userSettingsSyncExclusions.contains(row.settingKey)) continue;
        if (_isSensitiveSettingKey(row.settingKey.name)) continue;
        values[row.settingKey.name] = row.settingValue;
      }

      await _firestore!
          .collection('$_userBasePath/userSettings')
          .doc('all')
          .set({
            'values': values,
            'updatedAt': FieldValue.serverTimestamp(),
            'updatedBy': currentUserEmail,
          });

      Logger.printDebug(
        'FirebaseSyncService: Pushed ${values.length} user settings',
      );
    } catch (e) {
      Logger.printDebug('FirebaseSyncService: Error pushing user settings: $e');
    }
  }

  /// Pull the whole `userSettings` doc from Firestore and merge into local DB.
  /// Keys that exist only locally (not in Firestore) are preserved — useful
  /// for first-time pulls where Firestore has nothing yet.
  /// Returns the number of keys written locally.
  Future<int> _pullUserSettings() async {
    final doc = await _firestore!
        .collection('$_userBasePath/userSettings')
        .doc('all')
        .get();

    if (!doc.exists) {
      Logger.printDebug(
        'FirebaseSyncService: No user settings doc in Firebase, skipping',
      );
      return 0;
    }

    final data = doc.data();
    if (data == null) return 0;

    final raw = data['values'];
    if (raw is! Map) {
      Logger.printDebug(
        'FirebaseSyncService: user settings doc has no `values` map',
      );
      return 0;
    }

    int writeCount = 0;
    for (final entry in raw.entries) {
      try {
        final keyName = entry.key.toString();
        if (_isSensitiveSettingKey(keyName)) continue;

        final key = SettingKey.values
            .where((e) => e.name == keyName)
            .firstOrNull;
        if (key == null) continue; // unknown key (older/newer app version)
        if (_userSettingsSyncExclusions.contains(key)) continue;

        final value = entry.value?.toString();

        await UserSettingService.instance.setItem(key, value);
        writeCount++;
      } catch (e) {
        Logger.printDebug(
          'FirebaseSyncService: Error pulling user setting ${entry.key}: $e',
        );
      }
      await Future.delayed(Duration.zero); // yield to UI
    }

    // One-shot rebuild after all settings are applied — avoids N setState
    // calls while still making theme/accent/etc. take effect without restart.
    if (writeCount > 0) {
      onGlobalAppStateRefresh?.call();
    }

    Logger.printDebug(
      'FirebaseSyncService: Pulled $writeCount user settings',
    );
    return writeCount;
  }

  // ============================================================
  // USER AVATAR - sync profile image as base64 inside a Firestore doc
  // ============================================================

  /// Owner ID used for the user's avatar attachment. Keep in sync with the
  /// value used in `edit_profile_modal.dart` / `user_avatar_display.dart`.
  static const String _avatarOwnerId = 'current';
  static const String _avatarRole = 'avatar';

  // Firestore single-doc limit is 1 MiB; base64 inflates by ~33%, so we aim
  // to keep the raw bytes well below ~700 KB. 400 KB is a comfortable
  // threshold and 512x512 @ JPEG q80 virtually always fits.
  static const int _avatarCompressThresholdBytes = 400 * 1000;
  static const int _avatarMaxDimension = 512;
  static const int _avatarJpegQuality = 80;

  Future<Attachment?> _getLocalAvatarAttachment() {
    return AttachmentsService.instance.firstByOwner(
      ownerType: AttachmentOwnerType.userProfile,
      ownerId: _avatarOwnerId,
      role: _avatarRole,
    );
  }

  /// Push the current user's avatar image to Firestore at
  /// `users/{uid}/profile/avatar` as a base64-encoded blob inside the
  /// document itself (Spark plan friendly — no Firebase Storage).
  ///
  /// Conservative: if there is no local avatar, we do NOTHING (we don't
  /// delete the remote one). A failure here does not propagate — the caller
  /// can ignore the exception so sync can continue with other data.
  Future<void> pushUserAvatar() async {
    if (!_initialized || _firestore == null) return;
    try {
      final uid = currentUserId;
      if (uid == null) return;

      final attachment = await _getLocalAvatarAttachment();
      if (attachment == null) {
        Logger.printDebug(
          'FirebaseSyncService: No local avatar attachment, skipping push',
        );
        return;
      }

      final file = await AttachmentsService.instance.resolveFile(attachment);
      if (!await file.exists()) {
        Logger.printDebug(
          'FirebaseSyncService: Local avatar file does not exist at '
          '${file.path}, skipping push',
        );
        return;
      }

      Uint8List bytes = await file.readAsBytes();
      final originalSize = bytes.length;
      String mimeType = attachment.mimeType;
      int? width;
      int? height;
      bool resized = false;

      if (originalSize > _avatarCompressThresholdBytes) {
        final decoded = img.decodeImage(bytes);
        if (decoded != null) {
          final needsResize = decoded.width > _avatarMaxDimension ||
              decoded.height > _avatarMaxDimension;
          final processed = needsResize
              ? img.copyResize(
                  decoded,
                  width: decoded.width >= decoded.height
                      ? _avatarMaxDimension
                      : null,
                  height: decoded.height > decoded.width
                      ? _avatarMaxDimension
                      : null,
                )
              : decoded;
          bytes = Uint8List.fromList(
            img.encodeJpg(processed, quality: _avatarJpegQuality),
          );
          mimeType = 'image/jpeg';
          width = processed.width;
          height = processed.height;
          resized = true;
        } else {
          Logger.printDebug(
            'FirebaseSyncService: Could not decode avatar for compression, '
            'uploading original $originalSize bytes',
          );
        }
      }

      final docRef = _firestore!
          .collection('$_userBasePath/profile')
          .doc('avatar');

      // Dedupe: skip if remote doc already has same size + mimeType.
      try {
        final remoteSnap = await docRef.get();
        if (remoteSnap.exists) {
          final remoteData = remoteSnap.data();
          final remoteSize = (remoteData?['size'] as num?)?.toInt();
          final remoteMime = remoteData?['mimeType'] as String?;
          if (remoteSize == bytes.length && remoteMime == mimeType) {
            Logger.printDebug(
              'FirebaseSyncService: Remote avatar matches local '
              '(${bytes.length} bytes, $mimeType), skipping push',
            );
            return;
          }
        }
      } catch (e) {
        Logger.printDebug(
          'FirebaseSyncService: Avatar dedupe read failed, continuing: $e',
        );
      }

      final encoded = base64Encode(bytes);
      Logger.printDebug(
        'FirebaseSyncService: Pushing avatar: original $originalSize bytes '
        '-> encoded ${encoded.length} bytes (resized: ${resized ? "yes" : "no"})',
      );

      await docRef.set({
        'data': encoded,
        'mimeType': mimeType,
        'size': bytes.length,
        'width': ?width,
        'height': ?height,
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': currentUserEmail,
      });

      Logger.printDebug(
        'FirebaseSyncService: Avatar push successful '
        '(${bytes.length} bytes, $mimeType)',
      );
    } catch (e) {
      Logger.printDebug('FirebaseSyncService: Error pushing avatar: $e');
    }
  }

  /// Pull the user's avatar from Firestore. The avatar payload lives as a
  /// base64-encoded string inside `users/{uid}/profile/avatar` itself
  /// (no Firebase Storage — Spark plan compatible).
  ///
  /// Steps:
  /// 1. Read `users/{uid}/profile/avatar` for data + size + mimeType.
  /// 2. If local DB already has an avatar with the same size, skip.
  /// 3. Otherwise decode base64 into
  ///    `{docsDir}/attachments/userProfile/{uuid}{ext}` and upsert an
  ///    `attachments` row pointing at it. Any previous local avatar row
  ///    (and its file) is removed first so only one avatar exists.
  Future<void> _pullUserAvatar() async {
    try {
      final uid = currentUserId;
      if (uid == null) return;

      final doc = await _firestore!
          .collection('$_userBasePath/profile')
          .doc('avatar')
          .get();
      if (!doc.exists) {
        Logger.printDebug(
          'FirebaseSyncService: No remote avatar doc in Firestore, '
          'skipping pull',
        );
        return;
      }
      final data = doc.data();
      if (data == null) return;

      final encoded = data['data'] as String?;
      if (encoded == null || encoded.isEmpty) {
        Logger.printDebug(
          'FirebaseSyncService: Remote avatar doc has no `data` field, '
          'skipping pull',
        );
        return;
      }

      final remoteSize = (data['size'] as num?)?.toInt();
      final remoteMime = (data['mimeType'] as String?) ?? 'image/jpeg';

      final existing = await _getLocalAvatarAttachment();
      if (existing != null &&
          remoteSize != null &&
          existing.sizeBytes == remoteSize) {
        final existingFile = await AttachmentsService.instance.resolveFile(
          existing,
        );
        if (await existingFile.exists()) {
          Logger.printDebug(
            'FirebaseSyncService: Remote avatar size matches local '
            '($remoteSize bytes), skipping download',
          );
          return;
        }
      }

      final Uint8List bytes;
      try {
        bytes = base64Decode(encoded);
      } catch (e) {
        Logger.printDebug(
          'FirebaseSyncService: Failed to base64-decode avatar: $e',
        );
        return;
      }

      final docsDir = await getApplicationDocumentsDirectory();
      final ownerFolder = Directory(
        p.join(docsDir.path, 'attachments', AttachmentOwnerType.userProfile.dbValue),
      );
      await ownerFolder.create(recursive: true);

      final ext = _extensionFromMime(remoteMime);
      final newId = generateUUID();
      final targetPath = p.join(ownerFolder.path, '$newId$ext');
      final targetFile = File(targetPath);

      await targetFile.writeAsBytes(bytes, flush: true);

      // Remove the previous local avatar (row + file) so only one remains.
      if (existing != null) {
        try {
          await AttachmentsService.instance.deleteById(existing.id);
        } catch (e) {
          Logger.printDebug(
            'FirebaseSyncService: Could not delete previous avatar row ${existing.id}: $e',
          );
        }
      }

      final db = AppDB.instance;
      final localPath = p.relative(targetFile.path, from: docsDir.path);
      await db.into(db.attachments).insert(
            AttachmentsCompanion.insert(
              id: newId,
              ownerType: AttachmentOwnerType.userProfile.dbValue,
              ownerId: _avatarOwnerId,
              localPath: localPath,
              mimeType: remoteMime,
              sizeBytes: bytes.length,
              role: const Value(_avatarRole),
              createdAt: Value(DateTime.now()),
            ),
          );

      Logger.printDebug(
        'FirebaseSyncService: Avatar pull successful, wrote ${bytes.length} '
        'bytes to $targetPath',
      );
    } catch (e) {
      Logger.printDebug('FirebaseSyncService: Error pulling avatar: $e');
    }
  }

  String _extensionFromMime(String mime) {
    switch (mime.toLowerCase()) {
      case 'image/jpeg':
        return '.jpg';
      case 'image/png':
        return '.png';
      case 'image/webp':
        return '.webp';
      case 'image/gif':
        return '.gif';
      default:
        return '.jpg';
    }
  }

  // ============================================================
  // TAGS - master table sync (pattern similar to categories)
  // ============================================================

  /// Push all local tags to Firestore at `users/{uid}/tags/{tagId}`.
  Future<void> pushTags() async {
    if (!_initialized || _firestore == null) return;
    try {
      if (currentUserId == null) return;

      final db = AppDB.instance;
      final rows = await db.select(db.tags).get();

      for (final tag in rows) {
        try {
          await _firestore!
              .collection('$_userBasePath/tags')
              .doc(tag.id)
              .set({
                'id': tag.id,
                'name': tag.name,
                'color': tag.color,
                'displayOrder': tag.displayOrder,
                'description': tag.description,
                'updatedAt': FieldValue.serverTimestamp(),
                'updatedBy': currentUserEmail,
              });
        } catch (e) {
          Logger.printDebug(
            'FirebaseSyncService: Error pushing tag ${tag.id}: $e',
          );
        }
      }

      Logger.printDebug('FirebaseSyncService: Pushed ${rows.length} tags');
    } catch (e) {
      Logger.printDebug('FirebaseSyncService: Error pushing tags: $e');
    }
  }

  /// Push a single tag to Firestore (matches the doc shape written by
  /// [pushTags]).
  Future<void> pushTag(TagInDB tag) async {
    if (!_initialized || _firestore == null) return;
    try {
      if (currentUserId == null) return;

      await _firestore!
          .collection('$_userBasePath/tags')
          .doc(tag.id)
          .set({
            'id': tag.id,
            'name': tag.name,
            'color': tag.color,
            'displayOrder': tag.displayOrder,
            'description': tag.description,
            'updatedAt': FieldValue.serverTimestamp(),
            'updatedBy': currentUserEmail,
          });

      Logger.printDebug('FirebaseSyncService: Pushed tag ${tag.id}');
    } catch (e) {
      Logger.printDebug('FirebaseSyncService: Error pushing tag: $e');
    }
  }

  /// Delete a tag from Firestore
  Future<void> deleteTag(String tagId) async {
    if (!_initialized || _firestore == null) return;
    try {
      if (currentUserId == null) return;

      await _firestore!
          .collection('$_userBasePath/tags')
          .doc(tagId)
          .delete();

      Logger.printDebug('FirebaseSyncService: Deleted tag $tagId');
    } catch (e) {
      Logger.printDebug('FirebaseSyncService: Error deleting tag: $e');
    }
  }

  Future<int> _pullTags() async {
    final snapshot =
        await _firestore!.collection('$_userBasePath/tags').get();

    final db = AppDB.instance;
    int successCount = 0;

    for (final doc in snapshot.docs) {
      try {
        final data = doc.data();

        final tag = TagInDB(
          id: data['id'] as String,
          name: data['name'] as String,
          color: data['color'] as String,
          displayOrder: (data['displayOrder'] as num?)?.toInt() ?? 0,
          description: data['description'] as String?,
        );

        await db.into(db.tags).insertOnConflictUpdate(tag);
        successCount++;
      } catch (e) {
        Logger.printDebug(
          'FirebaseSyncService: Error pulling tag ${doc.id}: $e',
        );
      }
      await Future.delayed(Duration.zero); // yield to UI
    }

    Logger.printDebug('FirebaseSyncService: Pulled $successCount tags');
    return successCount;
  }

  /// Push all `transactionTags` rows. Doc id is deterministic
  /// `${transactionID}_${tagID}` so upserts are idempotent and the
  /// server-side set is a simple mirror of the local set.
  Future<void> pushTransactionTags() async {
    if (!_initialized || _firestore == null) return;
    try {
      if (currentUserId == null) return;

      final db = AppDB.instance;
      final rows = await db.select(db.transactionTags).get();

      for (final link in rows) {
        try {
          final docId = '${link.transactionID}_${link.tagID}';
          await _firestore!
              .collection('$_userBasePath/transactionTags')
              .doc(docId)
              .set({
                'transactionID': link.transactionID,
                'tagID': link.tagID,
                'updatedAt': FieldValue.serverTimestamp(),
                'updatedBy': currentUserEmail,
              });
        } catch (e) {
          Logger.printDebug(
            'FirebaseSyncService: Error pushing transactionTag '
            '${link.transactionID}/${link.tagID}: $e',
          );
        }
      }

      Logger.printDebug(
        'FirebaseSyncService: Pushed ${rows.length} transactionTag links',
      );
    } catch (e) {
      Logger.printDebug(
        'FirebaseSyncService: Error pushing transactionTags: $e',
      );
    }
  }

  Future<int> _pullTransactionTags() async {
    final snapshot = await _firestore!
        .collection('$_userBasePath/transactionTags')
        .get();

    final db = AppDB.instance;
    int successCount = 0;
    int skippedCount = 0;

    for (final doc in snapshot.docs) {
      try {
        final data = doc.data();
        final transactionID = data['transactionID'] as String;
        final tagID = data['tagID'] as String;

        // FK guard: CASCADE FKs require both parent rows to exist locally.
        final txExists = await (db.select(
          db.transactions,
        )..where((t) => t.id.equals(transactionID))).getSingleOrNull();
        if (txExists == null) {
          skippedCount++;
          Logger.printDebug(
            'FirebaseSyncService: Skipping transactionTag ${doc.id}: '
            'transaction $transactionID missing locally',
          );
          continue;
        }
        final tagExists = await (db.select(
          db.tags,
        )..where((t) => t.id.equals(tagID))).getSingleOrNull();
        if (tagExists == null) {
          skippedCount++;
          Logger.printDebug(
            'FirebaseSyncService: Skipping transactionTag ${doc.id}: '
            'tag $tagID missing locally',
          );
          continue;
        }

        await db
            .into(db.transactionTags)
            .insert(
              TransactionTag(transactionID: transactionID, tagID: tagID),
              mode: InsertMode.insertOrIgnore,
            );
        successCount++;
      } catch (e) {
        Logger.printDebug(
          'FirebaseSyncService: Error pulling transactionTag ${doc.id}: $e',
        );
      }
      await Future.delayed(Duration.zero); // yield to UI
    }

    Logger.printDebug(
      'FirebaseSyncService: Pulled $successCount transactionTags '
      '(skipped $skippedCount orphans)',
    );
    return successCount;
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
  // BUDGETS & GOALS - per-entity sync (push + delete only for now)
  // ============================================================

  /// Push a budget to Firestore. The referenced [TransactionFilterSetInDB]
  /// is denormalized into `trFilters` so the doc is self-contained — the
  /// transaction_filter_sets table is an internal join table and is not
  /// synced on its own.
  Future<void> pushBudget(
    BudgetInDB budget, {
    TransactionFilterSetInDB? trFilters,
  }) async {
    if (!_initialized || _firestore == null) return;
    try {
      if (currentUserId == null) return;

      final docRef = _firestore!
          .collection('$_userBasePath/budgets')
          .doc(budget.id);

      await docRef.set({
        'id': budget.id,
        'name': budget.name,
        'limitAmount': budget.limitAmount,
        'intervalPeriod': budget.intervalPeriod?.name,
        'startDate': budget.startDate?.toIso8601String(),
        'endDate': budget.endDate?.toIso8601String(),
        'filterID': budget.filterID,
        if (trFilters != null) 'trFilters': trFilters.toJson(),
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': currentUserEmail,
      });

      Logger.printDebug('FirebaseSyncService: Pushed budget ${budget.id}');
    } catch (e) {
      Logger.printDebug('FirebaseSyncService: Error pushing budget: $e');
    }
  }

  /// Delete a budget from Firestore
  Future<void> deleteBudget(String budgetId) async {
    if (!_initialized || _firestore == null) return;
    try {
      if (currentUserId == null) return;

      await _firestore!
          .collection('$_userBasePath/budgets')
          .doc(budgetId)
          .delete();

      Logger.printDebug('FirebaseSyncService: Deleted budget $budgetId');
    } catch (e) {
      Logger.printDebug('FirebaseSyncService: Error deleting budget: $e');
    }
  }

  /// Push a goal to Firestore. See [pushBudget] for the filter-set
  /// denormalization rationale.
  Future<void> pushGoal(
    GoalInDB goal, {
    TransactionFilterSetInDB? trFilters,
  }) async {
    if (!_initialized || _firestore == null) return;
    try {
      if (currentUserId == null) return;

      final docRef = _firestore!
          .collection('$_userBasePath/goals')
          .doc(goal.id);

      await docRef.set({
        'id': goal.id,
        'name': goal.name,
        'amount': goal.amount,
        'initialAmount': goal.initialAmount,
        'startDate': goal.startDate.toIso8601String(),
        'endDate': goal.endDate?.toIso8601String(),
        'type': goal.type.name,
        'filterID': goal.filterID,
        if (trFilters != null) 'trFilters': trFilters.toJson(),
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': currentUserEmail,
      });

      Logger.printDebug('FirebaseSyncService: Pushed goal ${goal.id}');
    } catch (e) {
      Logger.printDebug('FirebaseSyncService: Error pushing goal: $e');
    }
  }

  /// Delete a goal from Firestore
  Future<void> deleteGoal(String goalId) async {
    if (!_initialized || _firestore == null) return;
    try {
      if (currentUserId == null) return;

      await _firestore!
          .collection('$_userBasePath/goals')
          .doc(goalId)
          .delete();

      Logger.printDebug('FirebaseSyncService: Deleted goal $goalId');
    } catch (e) {
      Logger.printDebug('FirebaseSyncService: Error deleting goal: $e');
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
      'tags': 0,
      'transactionTags': 0,
      'userSettings': 0,
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

      // Pull tags BEFORE transactionTags (FK dependency). transactionTags
      // also needs the transactions table populated, so the link pull
      // is scheduled right after _pullTransactions below.
      try {
        result['tags'] = await _pullTags();
      } catch (e) {
        Logger.printDebug('FirebaseSyncService: Error in _pullTags: $e');
      }

      // Pull exchange rates
      result['exchangeRates'] = await _pullExchangeRates();

      // Pull transactions
      final txResult = await _pullTransactions();
      result['transactions'] = txResult['success'] ?? 0;
      totalErrors += (txResult['errors'] as int?) ?? 0;
      if (firstError.isEmpty) {
        firstError = 'Tx: ${txResult['firstError'] ?? ''}';
      }

      // Pull transactionTags AFTER both tags and transactions are in place.
      try {
        result['transactionTags'] = await _pullTransactionTags();
      } catch (e) {
        Logger.printDebug(
          'FirebaseSyncService: Error in _pullTransactionTags: $e',
        );
      }

      // Pull user settings (theme, SMS prefs, language, etc.)
      result['userSettings'] = await _pullUserSettings();

      // Pull user avatar (optional, failures are swallowed inside)
      await _pullUserAvatar();

      // Pull encrypted third-party credentials (optional, failures swallowed)
      await _pullCredentials();

      // Re-initialize Hidden Mode so the in-memory lock state reflects the
      // freshly-pulled PIN (secure storage) and `hiddenModeEnabled` flag (DB).
      // Without this, widgets subscribed to `isLockedStream` keep the boot-time
      // value (usually `false` on fresh installs) until the user restarts the
      // app, causing saving accounts to leak into the dashboard.
      //
      // Safe to call multiple times: `_isLockedController` is a
      // `BehaviorSubject` and `isLockedStream` applies `.distinct()`, so
      // repeated calls with the same resolved state do not produce duplicate
      // downstream emissions.
      try {
        Logger.printDebug(
          'FirebaseSyncService: re-initializing HiddenModeService after pull',
        );
        await HiddenModeService.instance.init();
      } catch (e) {
        Logger.printDebug(
          'FirebaseSyncService: HiddenModeService re-init failed: $e',
        );
      }

      result['errors'] = totalErrors;
      result['firstError'] = firstError;

      Logger.printDebug(
        'FirebaseSyncService: Data pull completed! '
        'Accounts: ${result['accounts']}, '
        'Categories: ${result['categories']}, '
        'Tags: ${result['tags']}, '
        'Transactions: ${result['transactions']}, '
        'TransactionTags: ${result['transactionTags']}, '
        'UserSettings: ${result['userSettings']}, '
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
      await Future.delayed(Duration.zero); // yield to UI
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
          type: data['type'] != null
              ? CategoryType.values
                    .where((e) => e.name == data['type'])
                    .firstOrNull
              : null,
          parentCategoryID: data['parentCategoryID'] as String?,
        );

        // Defensive normalization: the DB CHECK constraint requires XOR
        // between `parentCategoryID` and (`color`, `type`). Firebase may
        // contain bad data pushed by an older buggy code path (e.g. a
        // Category whose color/type getters fell back to the parent's
        // values). If this is a subcategory, force color/type to null
        // so the insert does not fail the CHECK.
        final CategoryInDB normalized;
        if (category.parentCategoryID != null) {
          normalized = category.copyWith(
            color: const Value<String?>(null),
            type: const Value<CategoryType?>(null),
          );
        } else {
          normalized = category;
          // Inverse check: a main category MUST have non-null color AND type.
          // If we see one without them, the insert will throw due to the
          // CHECK constraint — log a clear warning first so we can fix
          // the source doc in Firebase.
          if (category.color == null || category.type == null) {
            Logger.printDebug(
              'FirebaseSyncService: WARNING main category ${doc.id} has '
              'null color or type (color=${category.color}, '
              'type=${category.type}). Insert will likely fail the XOR '
              'CHECK constraint. Fix this doc in Firestore.',
            );
          }
        }

        await db.into(db.categories).insertOnConflictUpdate(normalized);
        successCount++;
      } catch (e) {
        Logger.printDebug(
          'FirebaseSyncService: Error pulling category ${doc.id}: $e',
        );
      }
      await Future.delayed(Duration.zero); // yield to UI
    }

    Logger.printDebug('FirebaseSyncService: Pulled $successCount categories');
    return successCount;
  }

  Future<int> _pullExchangeRates() async {
    final snapshot = await _firestore!
        .collection('$_userBasePath/exchangeRates')
        .get();

    final db = AppDB.instance;
    final preferredCurrency =
        appStateSettings[SettingKey.preferredCurrency] ?? 'USD';
    int successCount = 0;
    int skippedCount = 0;

    for (final doc in snapshot.docs) {
      try {
        final data = doc.data();

        String currencyCode = data['currencyCode'] as String;
        double exchangeRate = (data['exchangeRate'] as num).toDouble();

        // --- Fix bad rates from Firebase cloud data ---
        // When preferred currency is USD:
        //   - Skip currencyCode='USD' rows (USD doesn't need a rate to itself)
        //   - Convert currencyCode='USD' with rate ~479 to currencyCode='VES'
        //     with rate ~0.00208
        if (preferredCurrency == 'USD' && currencyCode == 'USD') {
          // These are wrong-direction rates from old bad data.
          // Convert: the cloud has "1 USD = 479.78 VES" stored as
          // currencyCode='USD', rate=479.78. Fix it to currencyCode='VES',
          // rate=1/479.78 (~0.00208).
          if (exchangeRate > 1.0) {
            currencyCode = 'VES';
            exchangeRate = 1.0 / exchangeRate;
            Logger.printDebug(
              'FirebaseSyncService: Fixed bad cloud rate ${doc.id}: '
              'USD@$exchangeRate -> VES@$exchangeRate',
            );
          } else {
            // currencyCode='USD' with a small rate — just skip it entirely
            skippedCount++;
            Logger.printDebug(
              'FirebaseSyncService: Skipping currencyCode=USD rate ${doc.id} '
              '(preferred currency is already USD)',
            );
            continue;
          }
        }

        // When preferred currency is USD: if we get a VES rate > 1.0 from the
        // cloud, it's in the wrong direction (should be < 1.0). Invert it.
        if (preferredCurrency == 'USD' &&
            currencyCode == 'VES' &&
            exchangeRate > 1.0) {
          exchangeRate = 1.0 / exchangeRate;
          Logger.printDebug(
            'FirebaseSyncService: Inverted bad VES rate ${doc.id}: '
            'now $exchangeRate',
          );
        }

        final rate = ExchangeRateInDB(
          id: data['id'] as String,
          date: DateTime.parse(data['date'] as String),
          currencyCode: currencyCode,
          exchangeRate: exchangeRate,
          source: data['source'] as String?,
        );

        await db.into(db.exchangeRates).insertOnConflictUpdate(rate);
        successCount++;
      } catch (e) {
        Logger.printDebug(
          'FirebaseSyncService: Error pulling exchange rate ${doc.id}: $e',
        );
      }
      await Future.delayed(Duration.zero); // yield to UI
    }

    Logger.printDebug(
      'FirebaseSyncService: Pulled $successCount exchange rates '
      '(skipped $skippedCount)',
    );
    return successCount;
  }

  Future<Map<String, dynamic>> _pullTransactions() async {
    final snapshot = await _firestore!
        .collection('$_userBasePath/transactions')
        .get();

    final db = AppDB.instance;
    final preferredCurrency =
        appStateSettings[SettingKey.preferredCurrency] ?? 'USD';
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

        // Fix bad exchangeRateApplied values from cloud data.
        // When preferred currency is USD, rates should be < 1.0 (e.g. 0.00208).
        // Cloud may have old bad values like 479.78 — invert them.
        double? exchangeRateApplied = data['exchangeRateApplied'] != null
            ? (data['exchangeRateApplied'] as num).toDouble()
            : null;
        if (exchangeRateApplied != null &&
            preferredCurrency != 'VES' &&
            exchangeRateApplied > 1.0) {
          Logger.printDebug(
            'FirebaseSyncService: Inverting bad exchangeRateApplied '
            '${doc.id}: $exchangeRateApplied -> ${1.0 / exchangeRateApplied}',
          );
          exchangeRateApplied = 1.0 / exchangeRateApplied;
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
          exchangeRateApplied: exchangeRateApplied,
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
      await Future.delayed(Duration.zero); // yield to UI
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
  // CREDENTIALS - encrypted sync of FlutterSecureStorage secrets
  // ============================================================

  /// Push the user's third-party API credentials (Nexus AI, Binance) to
  /// Firestore, AES-GCM encrypted with a key derived from the user's UID
  /// + a hardcoded pepper. See [FirebaseCredentialsCipher] for the threat
  /// model. Only fields that actually exist locally are pushed.
  Future<void> pushCredentials() async {
    if (!_initialized || _firestore == null) return;
    try {
      final uid = currentUserId;
      if (uid == null) return;

      final cipher = FirebaseCredentialsCipher.instance;
      final payload = <String, dynamic>{};

      // Push every configured BYOK provider. Each provider keeps its own
      // payload field so users can keep multiple keys in sync (one per
      // provider). The active-provider id is non-secret and rides along in
      // user_settings via the standard settings sync path.
      for (final providerType in AiProviderType.values) {
        final creds = await AiCredentialsStore.instance
            .loadCredentials(providerType);
        if (creds == null) continue;
        if (creds.apiKey.isNotEmpty) {
          payload['ai_${providerType.storageId}_apiKey'] =
              await cipher.encryptForUser(creds.apiKey, uid);
        }
        final model = creds.model;
        if (model != null && model.isNotEmpty) {
          payload['ai_${providerType.storageId}_model'] =
              await cipher.encryptForUser(model, uid);
        }
        final baseUrl = creds.baseUrl;
        if (baseUrl != null && baseUrl.isNotEmpty) {
          payload['ai_${providerType.storageId}_baseUrl'] =
              await cipher.encryptForUser(baseUrl, uid);
        }
      }

      final binance = await BinanceCredentialsStore.instance.load();
      if (binance != null) {
        payload['binanceApiKey'] =
            await cipher.encryptForUser(binance.apiKey, uid);
        payload['binanceSecret'] =
            await cipher.encryptForUser(binance.apiSecret, uid);
      }

      // Hidden Mode PIN: hash + salt must travel together, or not at all.
      final hiddenHash = await HiddenModeService.instance.readPinHash();
      final hiddenSalt = await HiddenModeService.instance.readPinSalt();
      if (hiddenHash != null &&
          hiddenHash.isNotEmpty &&
          hiddenSalt != null &&
          hiddenSalt.isNotEmpty) {
        payload['hiddenModePinHash'] =
            await cipher.encryptForUser(hiddenHash, uid);
        payload['hiddenModePinSalt'] =
            await cipher.encryptForUser(hiddenSalt, uid);
      }

      if (payload.isEmpty) {
        Logger.printDebug(
          'FirebaseSyncService: No local credentials to push, skipping',
        );
        return;
      }

      payload['updatedAt'] = FieldValue.serverTimestamp();
      payload['updatedBy'] = currentUserEmail;

      await _firestore!
          .collection('$_userBasePath/credentials')
          .doc('encrypted')
          .set(payload, SetOptions(merge: true));

      Logger.printDebug(
        'FirebaseSyncService: Pushed ${payload.length - 2} encrypted credential(s)',
      );
    } catch (e) {
      Logger.printDebug('FirebaseSyncService: Error pushing credentials: $e');
    }
  }

  /// Pull encrypted credentials from Firestore, decrypt, and write into the
  /// local secure stores. Missing or undecryptable fields are silently
  /// skipped so one bad field cannot block the whole pull.
  Future<void> _pullCredentials() async {
    try {
      final uid = currentUserId;
      if (uid == null) return;

      final doc = await _firestore!
          .collection('$_userBasePath/credentials')
          .doc('encrypted')
          .get();
      if (!doc.exists) {
        Logger.printDebug(
          'FirebaseSyncService: No remote credentials doc, skipping pull',
        );
        return;
      }
      final data = doc.data();
      if (data == null) return;

      final cipher = FirebaseCredentialsCipher.instance;

      Future<String?> decryptField(String key) async {
        final raw = data[key];
        if (raw is! String || raw.isEmpty) return null;
        try {
          return await cipher.decryptForUser(raw, uid);
        } catch (e) {
          Logger.printDebug(
            'FirebaseSyncService: Failed to decrypt credential $key: $e',
          );
          return null;
        }
      }

      int written = 0;

      // Pull every BYOK provider. Each entry is restored independently so a
      // single decryption failure for one provider does not block the rest.
      for (final providerType in AiProviderType.values) {
        final apiKey =
            await decryptField('ai_${providerType.storageId}_apiKey');
        if (apiKey == null || apiKey.isEmpty) continue;
        final model = await decryptField('ai_${providerType.storageId}_model');
        final baseUrl =
            await decryptField('ai_${providerType.storageId}_baseUrl');
        await AiCredentialsStore.instance.saveCredentials(AiCredentials(
          providerType: providerType,
          apiKey: apiKey,
          model: (model != null && model.isNotEmpty) ? model : null,
          baseUrl: (baseUrl != null && baseUrl.isNotEmpty) ? baseUrl : null,
        ));
        written++;
      }

      // Backwards-compatibility: legacy docs only carried `nexusApiKey` /
      // `nexusModel`. Honour them when present and the new shape did not
      // already restore Nexus credentials.
      final legacyNexusApiKey = await decryptField('nexusApiKey');
      if (legacyNexusApiKey != null && legacyNexusApiKey.isNotEmpty) {
        final existing = await AiCredentialsStore.instance
            .loadCredentials(AiProviderType.nexus);
        if (existing == null) {
          final legacyModel = await decryptField('nexusModel');
          await AiCredentialsStore.instance.saveCredentials(AiCredentials(
            providerType: AiProviderType.nexus,
            apiKey: legacyNexusApiKey,
            model: (legacyModel != null && legacyModel.isNotEmpty)
                ? legacyModel
                : null,
          ));
          written++;
        }
      }

      final binanceApiKey = await decryptField('binanceApiKey');
      final binanceSecret = await decryptField('binanceSecret');
      if (binanceApiKey != null && binanceSecret != null) {
        await BinanceCredentialsStore.instance.save(
          apiKey: binanceApiKey,
          apiSecret: binanceSecret,
        );
        written += 2;
      }

      // Hidden Mode PIN must be restored as a pair. If either side failed to
      // decrypt or is missing, skip entirely — writing only one would leave
      // the service in a broken half-provisioned state.
      final hiddenHash = await decryptField('hiddenModePinHash');
      final hiddenSalt = await decryptField('hiddenModePinSalt');
      if (hiddenHash != null && hiddenSalt != null) {
        await HiddenModeService.instance
            .writePinHashAndSalt(hiddenHash, hiddenSalt);
        written += 2;
      } else if (hiddenHash != null || hiddenSalt != null) {
        Logger.printDebug(
          'FirebaseSyncService: Hidden Mode PIN incomplete '
          '(hash=${hiddenHash != null}, salt=${hiddenSalt != null}), skipping',
        );
      }

      Logger.printDebug(
        'FirebaseSyncService: Pulled $written encrypted credential(s)',
      );
    } catch (e) {
      Logger.printDebug('FirebaseSyncService: Error pulling credentials: $e');
    }
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
      // NOTE: `Category.color` and `Category.type` are GETTERS that fall
      // back to the parent category's values when the subcategory's own
      // fields are null. Reading them here would push bogus non-null
      // color/type on subcategories, violating the XOR CHECK constraint
      // on pull. `pushCategory` also normalizes defensively, but we pass
      // nulls explicitly for subcategories to avoid ever depending on
      // the getter fallback.
      final categories = await CategoryService.instance.getCategories().first;
      for (final category in categories) {
        final isSub = category.parentCategory != null;
        await pushCategory(
          CategoryInDB(
            id: category.id,
            name: category.name,
            iconId: category.iconId,
            color: isSub ? null : category.color,
            displayOrder: category.displayOrder,
            type: isSub ? null : category.type,
            parentCategoryID: category.parentCategory?.id,
          ),
        );
      }
      // Existing Firestore docs from prior buggy pushes may still contain
      // non-null color/type on subcategories. The one-time cleanup runs at
      // app startup via [cleanupLegacySubcategoryFields]; we invoke it here
      // again (idempotent — SharedPreferences flag short-circuits after the
      // first run) so that a full-push right after enabling sync cannot leave
      // the collection in a dirty state.
      try {
        await cleanupLegacySubcategoryFields();
      } catch (e) {
        Logger.printDebug(
          'FirebaseSyncService: Error in cleanupLegacySubcategoryFields: $e',
        );
      }

      // Push tags BEFORE transactions/transactionTags. Failures here must
      // not tumble the rest of the sync — mirror the avatar/credentials
      // isolation pattern.
      try {
        await pushTags();
      } catch (e) {
        Logger.printDebug('FirebaseSyncService: Error in pushTags: $e');
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

      // Push transactionTags AFTER both tags and transactions.
      try {
        await pushTransactionTags();
      } catch (e) {
        Logger.printDebug(
          'FirebaseSyncService: Error in pushTransactionTags: $e',
        );
      }

      // Push exchange rates
      final rates = await ExchangeRateService.instance.getExchangeRates().first;
      for (final rate in rates) {
        await pushExchangeRate(rate);
      }

      // Push user settings (theme, SMS prefs, language, etc.)
      await pushUserSettings();

      // Push user avatar (optional, failures are swallowed inside)
      await pushUserAvatar();

      // Push encrypted third-party credentials (Nexus AI, Binance).
      // Failures are swallowed inside.
      await pushCredentials();

      Logger.printDebug('FirebaseSyncService: Full data push completed!');
    } catch (e) {
      Logger.printDebug('FirebaseSyncService: Error in full push: $e');
    }
  }

  // ============================================================
  // ONE-TIME MIGRATIONS
  // ============================================================

  /// SharedPreferences flag key for the subcategory-cleanup migration.
  /// Bump the `v1` suffix if the migration logic ever needs to re-run.
  static const String _legacySubcategoryCleanupKey =
      'migration_firebase_cleanup_subcategory_color_type_v1';

  /// One-time migration: remove `color` and `type` fields from Firestore
  /// category docs that represent subcategories (i.e. `parentCategoryID`
  /// is non-null).
  ///
  /// ### Why this exists
  /// An earlier version of [pushCategory]/[_pushFullData] pushed
  /// [Category] objects whose `color`/`type` getters fell back to the
  /// parent category's values when the subcategory's own columns were
  /// null. As a result, subcategory docs in Firestore ended up with
  /// non-null `color` and `type`, violating the XOR CHECK constraint
  /// (`parentCategoryID` XOR (`color`, `type`)) on the local DB when
  /// those docs were pulled back down.
  ///
  /// [pushCategory] and [_pullCategories] already normalize defensively
  /// so new writes and new pulls are safe, but the stale docs sitting
  /// in Firestore continue to be bad data. This migration reaches into
  /// the user's `users/{uid}/categories` collection and unsets the two
  /// fields on every subcategory doc.
  ///
  /// ### Guarantees
  /// - Runs at most once per device (tracked via SharedPreferences flag
  ///   [_legacySubcategoryCleanupKey]).
  /// - No-op when sync is not initialized or the user is signed out.
  /// - Never throws: all errors are swallowed and logged.
  /// - Idempotent: calling it after a successful run is a cheap flag
  ///   check that returns immediately.
  Future<void> cleanupLegacySubcategoryFields() async {
    if (!_initialized || _firestore == null) return;

    final uid = currentUserId;
    if (uid == null) return;

    SharedPreferences? prefs;
    try {
      prefs = await SharedPreferences.getInstance();
    } catch (e) {
      Logger.printDebug(
        'FirebaseSyncService: cleanupLegacySubcategoryFields: '
        'SharedPreferences unavailable: $e',
      );
      return;
    }

    if (prefs.getBool(_legacySubcategoryCleanupKey) == true) {
      return; // Already migrated on this device.
    }

    try {
      final snapshot = await _firestore!
          .collection('$_userBasePath/categories')
          .get();

      int cleaned = 0;
      int skipped = 0;

      for (final doc in snapshot.docs) {
        final data = doc.data();

        final parentId = data['parentCategoryID'];
        final hasParent = parentId != null && (parentId as String).isNotEmpty;
        if (!hasParent) {
          skipped++;
          continue; // Main category — color/type MUST stay.
        }

        final hasColor = data.containsKey('color') && data['color'] != null;
        final hasType = data.containsKey('type') && data['type'] != null;
        if (!hasColor && !hasType) {
          skipped++;
          continue; // Already clean.
        }

        try {
          await doc.reference.update({
            if (hasColor) 'color': FieldValue.delete(),
            if (hasType) 'type': FieldValue.delete(),
            'updatedAt': FieldValue.serverTimestamp(),
            'updatedBy': currentUserEmail,
          });
          cleaned++;
        } catch (e) {
          Logger.printDebug(
            'FirebaseSyncService: cleanupLegacySubcategoryFields: '
            'failed to clean ${doc.id}: $e',
          );
        }

        await Future.delayed(Duration.zero); // yield to UI
      }

      await prefs.setBool(_legacySubcategoryCleanupKey, true);
      Logger.printDebug(
        'FirebaseSyncService: cleanupLegacySubcategoryFields done '
        '(cleaned=$cleaned, skipped=$skipped)',
      );
    } catch (e) {
      // Do NOT set the flag — let the next startup retry.
      Logger.printDebug(
        'FirebaseSyncService: cleanupLegacySubcategoryFields failed: $e',
      );
    }
  }
}
