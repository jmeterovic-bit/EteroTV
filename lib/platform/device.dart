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
