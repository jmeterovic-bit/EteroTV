import 'dart:io';

import 'package:flutter/services.dart';

/// True on Google TV, Android TV and Fire TV.
Future<bool> isTv() async {
  if (!Platform.isAndroid) return false;
  try {
    return await const MethodChannel('eterotv/vlc').invokeMethod<bool>('isTv') ?? false;
  } catch (_) {
    return false;
  }
}

/// Set once at start-up (see main): true on Google TV, Android TV and Fire TV.
/// The UI uses it for the remote: no keyboard popping up while moving
/// through a search field, and margins for TVs that cut the edges.
bool runningOnTv = false;

/// The name people gave this device (Android "device name"), to tell TVs apart.
Future<String> deviceName() async {
  if (Platform.isAndroid) {
    try {
      final n = await const MethodChannel('eterotv/vlc').invokeMethod<String>('deviceName');
      if (n != null && n.trim().isNotEmpty) return n.trim();
    } catch (_) {}
  }
  return Platform.localHostname;
}
