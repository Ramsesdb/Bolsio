import 'package:copy_with_extension/copy_with_extension.dart';

part 'extracted_row.g.dart';

@CopyWith()
class ExtractedRow {
  final String id;
  final double amount;
  final String kind;
  final DateTime date;
  final String description;
  final double? confidence;

  const ExtractedRow({
    required this.id,
    required this.amount,
    required this.kind,
    required this.date,
    required this.description,
    this.confidence,
  });
}
