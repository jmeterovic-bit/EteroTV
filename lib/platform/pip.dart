import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Picture in picture (2.3.0, Jose): on Android, going to another app (Home,
/// or the recent apps) while a video plays keeps it playing in a small
/// window over everything. The player says when that may happen; the
/// activity does it (MainActivity.kt). Devices without it (some TVs) ignore
/// the call.
class Pip {
  static const _channel = MethodChannel('eterotv/pip');

  /// The video is in the small window right now.
  static final active = ValueNotifier<bool>(false);

  /// The user closed the small window (its ✕, or swiped it away).
  static VoidCallback? onClosed;

  static bool _listening = false;
  static (bool, int, int)? _last;

  /// Whether leaving the app should shrink the video (only while it plays),
  /// and the shape of the window (the video's width and height).
  static Future<void> allow(bool on, {int width = 16, int height = 9}) async {
    if (!Platform.isAndroid) return;
    final now = (on, width, height);
    if (now == _last) return;
    _last = now;
    if (!_listening) {
      _listening = true;
      _channel.setMethodCallHandler((call) async {
        switch (call.method) {
          case 'changed':
            active.value = call.arguments == true;
          case 'closed':
            active.value = false;
            onClosed?.call();
        }
      });
    }
    try {
      await _channel.invokeMethod<bool>('allow', {'on': on, 'width': width, 'height': height});
    } catch (_) {
      // An older APK without it: nothing happens.
    }
  }
}
