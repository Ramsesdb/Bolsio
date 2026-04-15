import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:wallex/core/database/app_db.dart';
import 'package:wallex/core/database/services/app-data/app_data_service.dart';
import 'package:wallex/core/models/transaction/transaction.dart';
import 'package:wallex/core/models/transaction/transaction_type.enum.dart';
import 'package:wallex/core/utils/logger.dart';
import 'package:path/path.dart' as path;

class BackupDatabaseService {
  AppDB db = AppDB.instance;

  File createAndReturnFile({
    required String exportPath,
    required String fileName,
  }) {
    String downloadPath = path.join(exportPath, fileName);

    File downloadFile = File(downloadPath);

    if (!downloadFile.existsSync()) {
      downloadFile.createSync(recursive: true);
    }

    return downloadFile;
  }

  Future<File> exportDatabaseFile(String exportPath) async {
    List<int> dbFileInBytes = await getDbFileInBytes();

    final file = createAndReturnFile(
      exportPath: exportPath,
      fileName:
          "monekin-${DateFormat('yyyyMMdd-Hms').format(DateTime.now())}.db",
    );

    return file.writeAsBytes(dbFileInBytes, mode: FileMode.write);
  }

  Future<Uint8List> getDbFileInBytes() async =>
      File(await db.databasePath).readAsBytes();

  String createCsvFromTransactions(List<MoneyTransaction> data) {
    // UTF-8 BOM for Excel compatibility with accented chars
    const bom = '\uFEFF';

    final headers = [
      'Fecha',
      'Donante / Nota',
      'Categoría',
      'Tipo',
      'Monto',
      'Moneda',
      'Cuenta',
      'Título',
    ];

    final rows = <List<dynamic>>[];
    rows.add(headers);

    final dateFormatter = DateFormat('dd/MM/yyyy HH:mm');

    for (final tx in data) {
      final categoryName = tx.category?.name ?? '';
      final parentCategoryName = tx.category?.parentCategory?.name;
      final fullCategory = parentCategoryName != null
          ? '$parentCategoryName > $categoryName'
          : categoryName;

      // Sign the amount: positive for income, negative for expense
      final isExpense = tx.type == TransactionType.expense;
      final signedValue = isExpense ? -tx.value.abs() : tx.value.abs();

      // Human-readable type
      String typeLabel;
      switch (tx.type) {
        case TransactionType.income:
          typeLabel = 'Ingreso';
          break;
        case TransactionType.expense:
          typeLabel = 'Gasto';
          break;
        default:
          typeLabel = 'Transferencia';
      }

      rows.add([
        dateFormatter.format(tx.date),
        tx.notes ?? '',
        fullCategory,
        typeLabel,
        signedValue.toStringAsFixed(2),
        tx.account.currencyId,
        tx.account.name,
        tx.title ?? '',
      ]);
    }

    // Use semicolon separator for Latin American Excel locales
    return bom + const ListToCsvConverter(fieldDelimiter: ';').convert(rows);
  }

  Future<File> exportSpreadsheet(
    String exportPath,
    List<MoneyTransaction> data,
  ) async {
    final csvData = createCsvFromTransactions(data);

    final file = createAndReturnFile(
      exportPath: exportPath,
      fileName:
          "Wallex_Report_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.csv",
    );

    return file.writeAsString(
      csvData,
      mode: FileMode.writeOnly,
      encoding: const Utf8Codec(),
    );
  }

  Future<bool> importDatabase() async {
    FilePickerResult? result;

    try {
      result = await FilePicker.platform.pickFiles(
        type: Platform.isWindows ? FileType.custom : FileType.any,
        allowedExtensions: Platform.isWindows ? ['db'] : null,
        allowMultiple: false,
      );
    } catch (e) {
      throw Exception(e.toString());
    }

    if (result != null) {
      File selectedFile = File(result.files.single.path!);

      // Delete the previous database
      String dbPath = await db.databasePath;

      final currentDBContent = await File(dbPath).readAsBytes();

      // Load the new database
      await File(
        dbPath,
      ).writeAsBytes(await selectedFile.readAsBytes(), mode: FileMode.write);

      try {
        final dbVersion = int.parse(
          (await AppDataService.instance
              .getAppDataItem(AppDataKey.dbVersion)
              .first)!,
        );

        if (dbVersion < db.schemaVersion) {
          await db.migrateDB(dbVersion, db.schemaVersion);
        }

        db.markTablesUpdated(db.allTables);
      } catch (e) {
        // Reset the DB as it was
        await File(dbPath).writeAsBytes(currentDBContent, mode: FileMode.write);
        db.markTablesUpdated(db.allTables);

        Logger.printDebug('Error\n: $e');

        throw Exception('The database is invalid or could not be readed');
      }

      return true;
    }

    return false;
  }

  Future<File?> readFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles();

    if (result != null) {
      return File(result.files.single.path!);
    }

    return null;
  }

  Future<List<List<dynamic>>> processCsv(String csvData) async {
    return const CsvToListConverter().convert(csvData, eol: '\n');
  }
}
