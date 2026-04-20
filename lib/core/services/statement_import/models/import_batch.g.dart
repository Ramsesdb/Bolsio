// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'import_batch.dart';

// **************************************************************************
// CopyWithGenerator
// **************************************************************************

abstract class _$ImportBatchCWProxy {
  ImportBatch id(String id);

  ImportBatch accountId(String accountId);

  ImportBatch createdAt(DateTime createdAt);

  ImportBatch modes(List<String> modes);

  ImportBatch transactionIds(List<String> transactionIds);

  /// Creates a new instance with the provided field values.
  /// Passing `null` to a nullable field nullifies it, while `null` for a non-nullable field is ignored. To update a single field use `ImportBatch(...).copyWith.fieldName(value)`.
  ///
  /// Example:
  /// ```dart
  /// ImportBatch(...).copyWith(id: 12, name: "My name")
  /// ```
  ImportBatch call({
    String id,
    String accountId,
    DateTime createdAt,
    List<String> modes,
    List<String> transactionIds,
  });
}

/// Callable proxy for `copyWith` functionality.
/// Use as `instanceOfImportBatch.copyWith(...)` or call `instanceOfImportBatch.copyWith.fieldName(value)` for a single field.
class _$ImportBatchCWProxyImpl implements _$ImportBatchCWProxy {
  const _$ImportBatchCWProxyImpl(this._value);

  final ImportBatch _value;

  @override
  ImportBatch id(String id) => call(id: id);

  @override
  ImportBatch accountId(String accountId) => call(accountId: accountId);

  @override
  ImportBatch createdAt(DateTime createdAt) => call(createdAt: createdAt);

  @override
  ImportBatch modes(List<String> modes) => call(modes: modes);

  @override
  ImportBatch transactionIds(List<String> transactionIds) =>
      call(transactionIds: transactionIds);

  @override
  /// Creates a new instance with the provided field values.
  /// Passing `null` to a nullable field nullifies it, while `null` for a non-nullable field is ignored. To update a single field use `ImportBatch(...).copyWith.fieldName(value)`.
  ///
  /// Example:
  /// ```dart
  /// ImportBatch(...).copyWith(id: 12, name: "My name")
  /// ```
  ImportBatch call({
    Object? id = const $CopyWithPlaceholder(),
    Object? accountId = const $CopyWithPlaceholder(),
    Object? createdAt = const $CopyWithPlaceholder(),
    Object? modes = const $CopyWithPlaceholder(),
    Object? transactionIds = const $CopyWithPlaceholder(),
  }) {
    return ImportBatch(
      id: id == const $CopyWithPlaceholder() || id == null
          ? _value.id
          // ignore: cast_nullable_to_non_nullable
          : id as String,
      accountId: accountId == const $CopyWithPlaceholder() || accountId == null
          ? _value.accountId
          // ignore: cast_nullable_to_non_nullable
          : accountId as String,
      createdAt: createdAt == const $CopyWithPlaceholder() || createdAt == null
          ? _value.createdAt
          // ignore: cast_nullable_to_non_nullable
          : createdAt as DateTime,
      modes: modes == const $CopyWithPlaceholder() || modes == null
          ? _value.modes
          // ignore: cast_nullable_to_non_nullable
          : modes as List<String>,
      transactionIds:
          transactionIds == const $CopyWithPlaceholder() ||
              transactionIds == null
          ? _value.transactionIds
          // ignore: cast_nullable_to_non_nullable
          : transactionIds as List<String>,
    );
  }
}

extension $ImportBatchCopyWith on ImportBatch {
  /// Returns a callable class used to build a new instance with modified fields.
  /// Example: `instanceOfImportBatch.copyWith(...)` or `instanceOfImportBatch.copyWith.fieldName(...)`.
  // ignore: library_private_types_in_public_api
  _$ImportBatchCWProxy get copyWith => _$ImportBatchCWProxyImpl(this);
}
