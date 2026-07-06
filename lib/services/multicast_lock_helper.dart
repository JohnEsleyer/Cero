import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class MulticastLockHelper {
  static const _channel = MethodChannel('com.example.pocketdatabase/wifi');

  static Future<void> acquire() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('acquireMulticastLock');
    } catch (e) {
      debugPrint('Failed to acquire MulticastLock: $e');
    }
  }

  static Future<void> release() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('releaseMulticastLock');
    } catch (e) {
      debugPrint('Failed to release MulticastLock: $e');
    }
  }
}
