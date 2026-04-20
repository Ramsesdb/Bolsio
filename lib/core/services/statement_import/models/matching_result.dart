import 'package:copy_with_extension/copy_with_extension.dart';
import 'package:wallex/core/services/statement_import/models/extracted_row.dart';

part 'matching_result.g.dart';

@CopyWith()
class MatchingResult {
  final ExtractedRow row;
  final bool existsInApp;
  final bool isPreFresh;
  final String? matchedTransactionId;

  const MatchingResult({
    required this.row,
    required this.existsInApp,
    required this.isPreFresh,
    this.matchedTransactionId,
  });
}
