import 'package:flutter/foundation.dart';

/// Source channel for a diagnostic [CaptureEvent].
///
/// Intentionally separate from [CaptureChannel] so the diagnostic surface
/// stays decoupled from storage enums used by the persistence layer.
enum CaptureEventSource {
  notification,
  sms;

  String get name {
    switch (this) {
      case CaptureEventSource.notification:
        return 'notification';
      case CaptureEventSource.sms:
        return 'sms';
    }
  }

  static CaptureEventSource fromName(String value) {
    switch (value) {
      case 'notification':
        return CaptureEventSource.notification;
      case 'sms':
        return CaptureEventSource.sms;
      default:
        return CaptureEventSource.notification;
    }
  }
}

/// Final outcome of a captured event after going through the orchestrator pipeline.
enum CaptureEventStatus {
  received,
  parsedSuccess,
  parsedFailed,
  filteredOut,
  duplicate,

  /// Synthetic event describing an internal lifecycle transition (e.g. the
  /// health monitor re-subscribing the native stream, permission changes).
  /// Not tied to an actual SMS/notification payload.
  systemEvent;

  String get name {
    switch (this) {
      case CaptureEventStatus.received:
        return 'received';
      case CaptureEventStatus.parsedSuccess:
        return 'parsedSuccess';
      case CaptureEventStatus.parsedFailed:
        return 'parsedFailed';
      case CaptureEventStatus.filteredOut:
        return 'filteredOut';
      case CaptureEventStatus.duplicate:
        return 'duplicate';
      case CaptureEventStatus.systemEvent:
        return 'systemEvent';
    }
  }

  static CaptureEventStatus fromName(String value) {
    switch (value) {
      case 'received':
        return CaptureEventStatus.received;
      case 'parsedSuccess':
        return CaptureEventStatus.parsedSuccess;
      case 'parsedFailed':
        return CaptureEventStatus.parsedFailed;
      case 'filteredOut':
        return CaptureEventStatus.filteredOut;
      case 'duplicate':
        return CaptureEventStatus.duplicate;
      case 'systemEvent':
        return CaptureEventStatus.systemEvent;
      default:
        return CaptureEventStatus.received;
    }
  }
}

/// A diagnostic record of a single captured event from SMS or a push
/// notification as it moves through the auto-import pipeline.
///
/// This is the data surface shown in the Capture Diagnostics screen so the
/// user can see exactly why a notification was (or was not) turned into a
/// pending import.
@immutable
class CaptureEvent {
  final String id;
  final DateTime timestamp;
  final CaptureEventSource source;

  /// Package name (notification only).
  final String? packageName;

  /// SMS sender / short-code (sms only).
  final String? sender;

  final String? title;
  final String content;

  final CaptureEventStatus status;

  /// Human-readable reason describing the outcome — shown in the UI.
  final String? reason;

  /// Name of the bank profile that matched (or was tried last) for this event.
  final String? matchedProfile;

  /// Parsed transaction amount, if any.
  final double? parsedAmount;

  /// Parsed transaction currency, if any (ISO code, e.g. 'VES', 'USD').
  final String? parsedCurrency;

  const CaptureEvent({
    required this.id,
    required this.timestamp,
    required this.source,
    this.packageName,
    this.sender,
    this.title,
    required this.content,
    required this.status,
    this.reason,
    this.matchedProfile,
    this.parsedAmount,
    this.parsedCurrency,
  });

  CaptureEvent copyWith({
    String? id,
    DateTime? timestamp,
    CaptureEventSource? source,
    String? packageName,
    String? sender,
    String? title,
    String? content,
    CaptureEventStatus? status,
    String? reason,
    String? matchedProfile,
    double? parsedAmount,
    String? parsedCurrency,
  }) {
    return CaptureEvent(
      id: id ?? this.id,
      timestamp: timestamp ?? this.timestamp,
      source: source ?? this.source,
      packageName: packageName ?? this.packageName,
      sender: sender ?? this.sender,
      title: title ?? this.title,
      content: content ?? this.content,
      status: status ?? this.status,
      reason: reason ?? this.reason,
      matchedProfile: matchedProfile ?? this.matchedProfile,
      parsedAmount: parsedAmount ?? this.parsedAmount,
      parsedCurrency: parsedCurrency ?? this.parsedCurrency,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'timestamp': timestamp.toIso8601String(),
        'source': source.name,
        'packageName': packageName,
        'sender': sender,
        'title': title,
        'content': content,
        'status': status.name,
        'reason': reason,
        'matchedProfile': matchedProfile,
        'parsedAmount': parsedAmount,
        'parsedCurrency': parsedCurrency,
      };

  static CaptureEvent fromJson(Map<String, dynamic> json) {
    return CaptureEvent(
      id: json['id'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      source: CaptureEventSource.fromName(json['source'] as String),
      packageName: json['packageName'] as String?,
      sender: json['sender'] as String?,
      title: json['title'] as String?,
      content: (json['content'] as String?) ?? '',
      status: CaptureEventStatus.fromName(json['status'] as String),
      reason: json['reason'] as String?,
      matchedProfile: json['matchedProfile'] as String?,
      parsedAmount: (json['parsedAmount'] as num?)?.toDouble(),
      parsedCurrency: json['parsedCurrency'] as String?,
    );
  }
}
