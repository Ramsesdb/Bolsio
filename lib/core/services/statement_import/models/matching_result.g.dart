// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'matching_result.dart';

// **************************************************************************
// CopyWithGenerator
// **************************************************************************

abstract class _$MatchingResultCWProxy {
  MatchingResult row(ExtractedRow row);

  MatchingResult existsInApp(bool existsInApp);

  MatchingResult isPreFresh(bool isPreFresh);

  MatchingResult matchedTransactionId(String? matchedTransactionId);

  /// Creates a new instance with the provided field values.
  /// Passing `null` to a nullable field nullifies it, while `null` for a non-nullable field is ignored. To update a single field use `MatchingResult(...).copyWith.fieldName(value)`.
  ///
  /// Example:
  /// ```dart
  /// MatchingResult(...).copyWith(id: 12, name: "My name")
  /// ```
  MatchingResult call({
    ExtractedRow row,
    bool existsInApp,
    bool isPreFresh,
    String? matchedTransactionId,
  });
}

/// Callable proxy for `copyWith` functionality.
/// Use as `instanceOfMatchingResult.copyWith(...)` or call `instanceOfMatchingResult.copyWith.fieldName(value)` for a single field.
class _$MatchingResultCWProxyImpl implements _$MatchingResultCWProxy {
  const _$MatchingResultCWProxyImpl(this._value);

  final MatchingResult _value;

  @override
  MatchingResult row(ExtractedRow row) => call(row: row);

  @override
  MatchingResult existsInApp(bool existsInApp) =>
      call(existsInApp: existsInApp);

  @override
  MatchingResult isPreFresh(bool isPreFresh) => call(isPreFresh: isPreFresh);

  @override
  MatchingResult matchedTransactionId(String? matchedTransactionId) =>
      call(matchedTransactionId: matchedTransactionId);

  @override
  /// Creates a new instance with the provided field values.
  /// Passing `null` to a nullable field nullifies it, while `null` for a non-nullable field is ignored. To update a single field use `MatchingResult(...).copyWith.fieldName(value)`.
  ///
  /// Example:
  /// ```dart
  /// MatchingResult(...).copyWith(id: 12, name: "My name")
  /// ```
  MatchingResult call({
    Object? row = const $CopyWithPlaceholder(),
    Object? existsInApp = const $CopyWithPlaceholder(),
    Object? isPreFresh = const $CopyWithPlaceholder(),
    Object? matchedTransactionId = const $CopyWithPlaceholder(),
  }) {
    return MatchingResult(
      row: row == const $CopyWithPlaceholder() || row == null
          ? _value.row
          // ignore: cast_nullable_to_non_nullable
          : row as ExtractedRow,
      existsInApp:
          existsInApp == const $CopyWithPlaceholder() || existsInApp == null
          ? _value.existsInApp
          // ignore: cast_nullable_to_non_nullable
          : existsInApp as bool,
      isPreFresh:
          isPreFresh == const $CopyWithPlaceholder() || isPreFresh == null
          ? _value.isPreFresh
          // ignore: cast_nullable_to_non_nullable
          : isPreFresh as bool,
      matchedTransactionId: matchedTransactionId == const $CopyWithPlaceholder()
          ? _value.matchedTransactionId
          // ignore: cast_nullable_to_non_nullable
          : matchedTransactionId as String?,
    );
  }
}

extension $MatchingResultCopyWith on MatchingResult {
  /// Returns a callable class used to build a new instance with modified fields.
  /// Example: `instanceOfMatchingResult.copyWith(...)` or `instanceOfMatchingResult.copyWith.fieldName(...)`.
  // ignore: library_private_types_in_public_api
  _$MatchingResultCWProxy get copyWith => _$MatchingResultCWProxyImpl(this);

  /// Returns a copy of the object with the selected fields set to `null`.
  /// A flag set to `false` leaves the field unchanged. Prefer `copyWith(field: null)` or `copyWith.fieldName(null)` for single-field updates.
  ///
  /// Example:
  /// ```dart
  /// MatchingResult(...).copyWithNull(firstField: true, secondField: true)
  /// ```
  MatchingResult copyWithNull({bool matchedTransactionId = false}) {
    return MatchingResult(
      row: row,
      existsInApp: existsInApp,
      isPreFresh: isPreFresh,
      matchedTransactionId: matchedTransactionId == true
          ? null
          : this.matchedTransactionId,
    );
  }
}
