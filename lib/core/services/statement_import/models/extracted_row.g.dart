// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'extracted_row.dart';

// **************************************************************************
// CopyWithGenerator
// **************************************************************************

abstract class _$ExtractedRowCWProxy {
  ExtractedRow id(String id);

  ExtractedRow amount(double amount);

  ExtractedRow kind(String kind);

  ExtractedRow date(DateTime date);

  ExtractedRow description(String description);

  ExtractedRow confidence(double? confidence);

  /// Creates a new instance with the provided field values.
  /// Passing `null` to a nullable field nullifies it, while `null` for a non-nullable field is ignored. To update a single field use `ExtractedRow(...).copyWith.fieldName(value)`.
  ///
  /// Example:
  /// ```dart
  /// ExtractedRow(...).copyWith(id: 12, name: "My name")
  /// ```
  ExtractedRow call({
    String id,
    double amount,
    String kind,
    DateTime date,
    String description,
    double? confidence,
  });
}

/// Callable proxy for `copyWith` functionality.
/// Use as `instanceOfExtractedRow.copyWith(...)` or call `instanceOfExtractedRow.copyWith.fieldName(value)` for a single field.
class _$ExtractedRowCWProxyImpl implements _$ExtractedRowCWProxy {
  const _$ExtractedRowCWProxyImpl(this._value);

  final ExtractedRow _value;

  @override
  ExtractedRow id(String id) => call(id: id);

  @override
  ExtractedRow amount(double amount) => call(amount: amount);

  @override
  ExtractedRow kind(String kind) => call(kind: kind);

  @override
  ExtractedRow date(DateTime date) => call(date: date);

  @override
  ExtractedRow description(String description) =>
      call(description: description);

  @override
  ExtractedRow confidence(double? confidence) => call(confidence: confidence);

  @override
  /// Creates a new instance with the provided field values.
  /// Passing `null` to a nullable field nullifies it, while `null` for a non-nullable field is ignored. To update a single field use `ExtractedRow(...).copyWith.fieldName(value)`.
  ///
  /// Example:
  /// ```dart
  /// ExtractedRow(...).copyWith(id: 12, name: "My name")
  /// ```
  ExtractedRow call({
    Object? id = const $CopyWithPlaceholder(),
    Object? amount = const $CopyWithPlaceholder(),
    Object? kind = const $CopyWithPlaceholder(),
    Object? date = const $CopyWithPlaceholder(),
    Object? description = const $CopyWithPlaceholder(),
    Object? confidence = const $CopyWithPlaceholder(),
  }) {
    return ExtractedRow(
      id: id == const $CopyWithPlaceholder() || id == null
          ? _value.id
          // ignore: cast_nullable_to_non_nullable
          : id as String,
      amount: amount == const $CopyWithPlaceholder() || amount == null
          ? _value.amount
          // ignore: cast_nullable_to_non_nullable
          : amount as double,
      kind: kind == const $CopyWithPlaceholder() || kind == null
          ? _value.kind
          // ignore: cast_nullable_to_non_nullable
          : kind as String,
      date: date == const $CopyWithPlaceholder() || date == null
          ? _value.date
          // ignore: cast_nullable_to_non_nullable
          : date as DateTime,
      description:
          description == const $CopyWithPlaceholder() || description == null
          ? _value.description
          // ignore: cast_nullable_to_non_nullable
          : description as String,
      confidence: confidence == const $CopyWithPlaceholder()
          ? _value.confidence
          // ignore: cast_nullable_to_non_nullable
          : confidence as double?,
    );
  }
}

extension $ExtractedRowCopyWith on ExtractedRow {
  /// Returns a callable class used to build a new instance with modified fields.
  /// Example: `instanceOfExtractedRow.copyWith(...)` or `instanceOfExtractedRow.copyWith.fieldName(...)`.
  // ignore: library_private_types_in_public_api
  _$ExtractedRowCWProxy get copyWith => _$ExtractedRowCWProxyImpl(this);

  /// Returns a copy of the object with the selected fields set to `null`.
  /// A flag set to `false` leaves the field unchanged. Prefer `copyWith(field: null)` or `copyWith.fieldName(null)` for single-field updates.
  ///
  /// Example:
  /// ```dart
  /// ExtractedRow(...).copyWithNull(firstField: true, secondField: true)
  /// ```
  ExtractedRow copyWithNull({bool confidence = false}) {
    return ExtractedRow(
      id: id,
      amount: amount,
      kind: kind,
      date: date,
      description: description,
      confidence: confidence == true ? null : this.confidence,
    );
  }
}
