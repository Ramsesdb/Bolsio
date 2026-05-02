import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

class Logger {
  static void printDebug(Object message) {
    if (kDebugMode) {
      print(message);
    }
  }

  static void recordError(Object error, StackTrace? stack, {String? reason}) {
    if (kDebugMode) {
      print('ERROR: $error\n$stack');
    } else {
      FirebaseCrashlytics.instance.recordError(error, stack, reason: reason);
    }
  }
}
