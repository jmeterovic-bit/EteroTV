import 'dart:io';

import 'package:flutter/services.dart';

/// Android: the play/pause button of headphones (wired or Bluetooth) goes
/// to the app's media session, not to the screen as a key (2.5.0, Jose).
/// The player says while it is open and whether it plays; the activity
/// keeps the session (MainActivity.kt) and tells back what was pressed.
class MediaKeys {
  static const _channel = MethodChannel('eterotv/media');

  /// 'play', 'pause' or 'toggle'.
  static void Function(String action)? onAction;

  static bool _listening = false;
  static (bool, bool, String)? _last;

  static Future<void> update({required bool open, bool playing = false, String title = ''}) async {
    if (!Platform.isAndroid) return;
    final now = (open, playing, title);
    if (now == _last) return;
    _last = now;
    if (!_listening) {
      _listening = true;
      _channel.setMethodCallHandler((call) async {
        if (call.method == 'action' && call.arguments is String) onAction?.call(call.arguments as String);
      });
    }
    try {
      await _channel.invokeMethod<void>('update', {'open': open, 'playing': playing, 'title': title});
    } catch (_) {
      // An older APK without it: nothing happens.
    }
  }
}
