import 'dart:convert';

import 'package:kilatex/core/services/ai/ai_provider_type.dart';

/// Per-provider credential bundle persisted in [AiCredentialsStore].
///
/// The shape is intentionally narrow — only the fields the dispatcher needs
/// at request time. `model` is optional: when null/empty the dispatcher
/// falls back to [AiProviderType.defaultModel]. `baseUrl` is only meaningful
/// for the Nexus provider (the others have hardcoded endpoints).
class AiCredentials {
  final AiProviderType providerType;
  final String apiKey;
  final String? model;
  final String? baseUrl;

  const AiCredentials({
    required this.providerType,
    required this.apiKey,
    this.model,
    this.baseUrl,
  });

  AiCredentials copyWith({
    AiProviderType? providerType,
    String? apiKey,
    String? model,
    String? baseUrl,
  }) {
    return AiCredentials(
      providerType: providerType ?? this.providerType,
      apiKey: apiKey ?? this.apiKey,
      model: model ?? this.model,
      baseUrl: baseUrl ?? this.baseUrl,
    );
  }

  /// JSON shape stored in `flutter_secure_storage`. Provider type is implied
  /// by the storage key, so it is NOT serialized inside the payload.
  Map<String, dynamic> toJson() => <String, dynamic>{
        'apiKey': apiKey,
        if (model != null && model!.isNotEmpty) 'model': model,
        if (baseUrl != null && baseUrl!.isNotEmpty) 'baseUrl': baseUrl,
      };

  String toJsonString() => jsonEncode(toJson());

  /// Reconstructs an [AiCredentials] from a stored JSON payload. The
  /// provider type comes from the caller (it is the storage key fragment),
  /// not from the payload itself.
  static AiCredentials? fromJson(
    AiProviderType providerType,
    Map<String, dynamic> json,
  ) {
    final apiKey = json['apiKey'];
    if (apiKey is! String || apiKey.trim().isEmpty) return null;
    final model = json['model'];
    final baseUrl = json['baseUrl'];
    return AiCredentials(
      providerType: providerType,
      apiKey: apiKey,
      model: (model is String && model.isNotEmpty) ? model : null,
      baseUrl: (baseUrl is String && baseUrl.isNotEmpty) ? baseUrl : null,
    );
  }

  static AiCredentials? fromJsonString(
    AiProviderType providerType,
    String raw,
  ) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      return fromJson(providerType, decoded);
    } catch (_) {
      return null;
    }
  }
}
