import 'package:copy_with_extension/copy_with_extension.dart';

part 'import_batch.g.dart';

@CopyWith()
class ImportBatch {
  final String id;
  final String accountId;
  final DateTime createdAt;
  final List<String> modes;
  final List<String> transactionIds;

  const ImportBatch({
    required this.id,
    required this.accountId,
    required this.createdAt,
    required this.modes,
    required this.transactionIds,
  });
}
