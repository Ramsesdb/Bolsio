import 'dart:async';
import 'dart:io';

import 'package:another_telephony/telephony.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:kilatex/core/models/auto_import/capture_channel.dart';
import 'package:kilatex/core/models/auto_import/raw_capture_event.dart';

import 'capture_source.dart';

/// SMS-based capture source using the `another_telephony` plugin.
///
/// Only functional on Android. On iOS, [isAvailable] returns `false`
/// and [start] is a no-op.
///
/// Filters incoming SMS by [allowlistSenders] (e.g. `['2661']` for BDV)
/// before emitting events. Messages from unknown senders are silently discarded.
class SmsCaptureSource implements CaptureSource {
  /// SMS shortcodes or phone numbers that are allowed through.
  final List<String> allowlistSenders;

  final Telephony _telephony;
  final StreamController<RawCaptureEvent> _controller =
      StreamController<RawCaptureEvent>.broadcast();

  bool _listening = false;

  SmsCaptureSource({
    required this.allowlistSenders,
    Telephony? telephony,
  }) : _telephony = telephony ?? Telephony.instance;

  @override
  CaptureChannel get channel => CaptureChannel.sms;

  @override
  Stream<RawCaptureEvent> get events => _controller.stream;

  @override
  Future<bool> isAvailable() async {
    if (!Platform.isAndroid) return false;

    try {
      final capable = await _telephony.isSmsCapable;
      return capable ?? false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> hasPermission() async {
    final status = await Permission.sms.status;
    return status.isGranted;
  }

  @override
  Future<bool> requestPermission() async {
    final status = await Permission.sms.request();
    return status.isGranted;
  }

  @override
  Future<void> start() async {
    if (!Platform.isAndroid) return;
    if (_listening) return;

    _listening = true;

    _telephony.listenIncomingSms(
      onNewMessage: _onMessage,
      listenInBackground: false,
    );
  }

  @override
  Future<void> stop() async {
    _listening = false;
    // another_telephony does not expose a way to cancel the listener,
    // but setting _listening = false prevents events from being emitted.
  }

  void _onMessage(SmsMessage message) {
    if (!_listening) return;

    final sender = message.address;
    final body = message.body;

    if (sender == null || body == null) return;

    // Only allow messages from known bank shortcodes
    if (!allowlistSenders.contains(sender)) return;

    _controller.add(RawCaptureEvent(
      rawText: body,
      sender: sender,
      receivedAt: DateTime.now(),
      channel: CaptureChannel.sms,
    ));
  }

  /// Clean up the stream controller.
  void dispose() {
    _controller.close();
  }
}
