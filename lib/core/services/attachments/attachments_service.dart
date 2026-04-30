import 'dart:io';

import 'package:drift/drift.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:kilatex/core/database/app_db.dart';
import 'package:kilatex/core/services/attachments/attachment_model.dart';
import 'package:kilatex/core/utils/uuid.dart';

class AttachmentsService {
  AttachmentsService._(this.db);

  final AppDB db;

  static final AttachmentsService instance = AttachmentsService._(AppDB.instance);

  AttachmentsService.forTesting(this.db);

  Future<Attachment> attach({
    required AttachmentOwnerType ownerType,
    required String ownerId,
    required File sourceFile,
    String? role,
  }) async {
    final docsDir = await getApplicationDocumentsDirectory();
    final ownerFolder = Directory(
      p.join(docsDir.path, 'attachments', ownerType.dbValue),
    );
    await ownerFolder.create(recursive: true);

    final attachmentId = generateUUID();
    final extension = await _targetExtensionFor(sourceFile);
    final targetAbsolutePath = p.join(ownerFolder.path, '$attachmentId$extension');

    final persistedFile = await _persistWithCompression(
      sourceFile,
      targetAbsolutePath,
    );

    final localPath = p.relative(persistedFile.path, from: docsDir.path);
    final mimeType = _guessMimeType(persistedFile.path);
    final sizeBytes = await persistedFile.length();
    final now = DateTime.now();

    await db.into(db.attachments).insert(
          AttachmentsCompanion.insert(
            id: attachmentId,
            ownerType: ownerType.dbValue,
            ownerId: ownerId,
            localPath: localPath,
            mimeType: mimeType,
            sizeBytes: sizeBytes,
            role: Value(role),
            createdAt: Value(now),
          ),
        );

    return Attachment(
      id: attachmentId,
      ownerType: ownerType,
      ownerId: ownerId,
      localPath: localPath,
      mimeType: mimeType,
      sizeBytes: sizeBytes,
      role: role,
      createdAt: now,
    );
  }

  Future<List<Attachment>> listByOwner({
    required AttachmentOwnerType ownerType,
    required String ownerId,
  }) async {
    final query = db.select(db.attachments)
      ..where(
        (tbl) =>
            tbl.ownerType.equals(ownerType.dbValue) & tbl.ownerId.equals(ownerId),
      )
      ..orderBy([
        (tbl) => OrderingTerm.desc(tbl.createdAt),
      ]);

    final rows = await query.get();
    return rows.map(_toModel).toList(growable: false);
  }

  Future<Attachment?> firstByOwner({
    required AttachmentOwnerType ownerType,
    required String ownerId,
    String? role,
  }) async {
    final query = db.select(db.attachments)
      ..where(
        (tbl) =>
            tbl.ownerType.equals(ownerType.dbValue) & tbl.ownerId.equals(ownerId),
      )
      ..orderBy([
        (tbl) => OrderingTerm.desc(tbl.createdAt),
      ])
      ..limit(1);

    if (role != null) {
      query.where((tbl) => tbl.role.equals(role));
    }

    final row = await query.getSingleOrNull();
    if (row == null) return null;
    return _toModel(row);
  }

  Future<void> deleteById(String id) async {
    final query = db.select(db.attachments)..where((tbl) => tbl.id.equals(id));
    final row = await query.getSingleOrNull();

    if (row == null) return;

    final file = await resolveFile(_toModel(row));
    if (await file.exists()) {
      await file.delete();
    }

    await (db.delete(db.attachments)..where((tbl) => tbl.id.equals(id))).go();
  }

  Future<void> deleteByOwner({
    required AttachmentOwnerType ownerType,
    required String ownerId,
  }) async {
    final owned = await listByOwner(ownerType: ownerType, ownerId: ownerId);

    for (final attachment in owned) {
      final file = await resolveFile(attachment);
      if (await file.exists()) {
        await file.delete();
      }
    }

    await (db.delete(db.attachments)
          ..where(
            (tbl) =>
                tbl.ownerType.equals(ownerType.dbValue) &
                tbl.ownerId.equals(ownerId),
          ))
        .go();
  }

  Future<int> purgeOrphans() async {
    final docsDir = await getApplicationDocumentsDirectory();
    final rootPath = p.join(docsDir.path, 'attachments');
    final rootDir = Directory(rootPath);

    final rows = await db.select(db.attachments).get();
    final expectedFiles = <String>{};
    var removedItems = 0;

    for (final row in rows) {
      final absolutePath = p.normalize(p.join(docsDir.path, row.localPath));
      expectedFiles.add(absolutePath);

      final file = File(absolutePath);
      if (!await file.exists()) {
        await (db.delete(db.attachments)..where((tbl) => tbl.id.equals(row.id))).go();
        removedItems++;
      }
    }

    if (await rootDir.exists()) {
      await for (final entity in rootDir.list(recursive: true, followLinks: false)) {
        if (entity is! File) continue;

        final candidate = p.normalize(entity.path);
        if (!expectedFiles.contains(candidate)) {
          await entity.delete();
          removedItems++;
        }
      }
    }

    return removedItems;
  }

  Future<File> resolveFile(Attachment attachment) async {
    final docsDir = await getApplicationDocumentsDirectory();
    return File(p.normalize(p.join(docsDir.path, attachment.localPath)));
  }

  Attachment _toModel(AttachmentInDB row) {
    return Attachment(
      id: row.id,
      ownerType: AttachmentOwnerType.fromDbValue(row.ownerType),
      ownerId: row.ownerId,
      localPath: row.localPath,
      mimeType: row.mimeType,
      sizeBytes: row.sizeBytes,
      role: row.role,
      createdAt: row.createdAt,
    );
  }

  Future<File> _persistWithCompression(File sourceFile, String targetPath) async {
    final sourceBytes = await sourceFile.readAsBytes();
    final decoded = img.decodeImage(sourceBytes);

    // Non-image files are copied as-is.
    if (decoded == null) {
      return sourceFile.copy(targetPath);
    }

    final resized = img.copyResize(
      decoded,
      width: decoded.width >= decoded.height ? 1600 : null,
      height: decoded.height > decoded.width ? 1600 : null,
      interpolation: img.Interpolation.cubic,
    );

    final jpg = img.encodeJpg(resized, quality: 82);
    final targetFile = File(targetPath);
    await targetFile.writeAsBytes(jpg, flush: true);
    return targetFile;
  }

  Future<String> _targetExtensionFor(File sourceFile) async {
    final bytes = await sourceFile.readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded != null) return '.jpg';

    final ext = p.extension(sourceFile.path).toLowerCase();
    if (ext.isEmpty) return '.bin';
    return ext;
  }

  String _guessMimeType(String filePath) {
    final ext = p.extension(filePath).toLowerCase();
    switch (ext) {
      case '.jpg':
      case '.jpeg':
        return 'image/jpeg';
      case '.png':
        return 'image/png';
      case '.webp':
        return 'image/webp';
      case '.gif':
        return 'image/gif';
      default:
        return 'application/octet-stream';
    }
  }
}
