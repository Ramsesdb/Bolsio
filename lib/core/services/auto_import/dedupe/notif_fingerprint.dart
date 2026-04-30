import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:bolsio/core/models/auto_import/raw_capture_event.dart';

/// Stable identifier for a native notification so we can detect reposts and
/// user-removed events even when the underlying parser fails or the bank
/// reference is missing.
///
/// There are two flavors of the key:
///
/// * [stable] — package + nativeId + postTime + contentHash. Matches an
///   EXACT repost (same Android notification, same text).
/// * [contentOnly] — package + contentHash. Matches the same logical
///   notification when Android re-dispatches it with a different id
///   (common on MIUI when the OS re-creates the notification after a reboot,
///   or when the banking app updates the notification to append a balance).
@immutable
class NotifFingerprint {
  final String packageName;
  final String? nativeId;
  final int? postTimeMs;

  /// sha256(title + '\n' + content), truncated to 16 hex chars.
  final String contentHash;

  const NotifFingerprint({
    required this.packageName,
    required this.nativeId,
    required this.postTimeMs,
    required this.contentHash,
  });

  /// Build a fingerprint from a [RawCaptureEvent].
  ///
  /// The event carries the raw title + content already concatenated in
  /// [RawCaptureEvent.rawText]; we hash that verbatim so two notifs with
  /// identical text produce the same [contentHash].
  factory NotifFingerprint.from(RawCaptureEvent event) {
    return NotifFingerprint(
      packageName: event.sender,
      nativeId: event.nativeNotifId,
      postTimeMs: event.nativeNotifPostTime,
      contentHash: _hashContent(event.rawText),
    );
  }

  /// Full stable key — changes whenever ANY of the four components differ.
  String get stable =>
      '$packageName|${nativeId ?? 'noid'}|${postTimeMs ?? 0}|$contentHash';

  /// Weaker key that ignores [nativeId] and [postTimeMs] — used to detect
  /// reposts of the SAME text with a different native id (update notifs).
  String get contentOnly => '$packageName|$contentHash';

  static String _hashContent(String raw) {
    final bytes = utf8.encode(raw);
    final digest = sha256.convert(bytes);
    final hex = digest.toString();
    return hex.length <= 16 ? hex : hex.substring(0, 16);
  }

  @override
  String toString() => 'NotifFingerprint(stable=$stable)';
}
