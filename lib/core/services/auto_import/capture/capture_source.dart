import 'package:bolsio/core/models/auto_import/capture_channel.dart';
import 'package:bolsio/core/models/auto_import/raw_capture_event.dart';

/// Abstract interface for a capture source that listens for bank events.
///
/// Each implementation wraps a platform-specific plugin (SMS, notification listener, etc.)
/// and emits [RawCaptureEvent]s that are then dispatched to the bank profile registry.
abstract class CaptureSource {
  /// Which channel this source captures from.
  CaptureChannel get channel;

  /// Stream of raw capture events emitted by this source.
  Stream<RawCaptureEvent> get events;

  /// Whether this capture source is available on the current platform/device.
  ///
  /// Returns `false` on iOS or if the underlying plugin is not supported.
  Future<bool> isAvailable();

  /// Whether the app currently has the necessary permissions for this source.
  Future<bool> hasPermission();

  /// Request the necessary runtime permissions from the user.
  ///
  /// Returns `true` if permissions were granted.
  Future<bool> requestPermission();

  /// Begin listening for events from this source.
  Future<void> start();

  /// Stop listening and clean up resources.
  Future<void> stop();
}
