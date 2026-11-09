import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

typedef _FindNative = IntPtr Function(Pointer<Utf16>, Pointer<Utf16>);
typedef _FindDart = int Function(Pointer<Utf16>, Pointer<Utf16>);
typedef _PosNative = Int32 Function(IntPtr, IntPtr, Int32, Int32, Int32, Int32, Uint32);
typedef _PosDart = int Function(int, int, int, int, int, int, int);
typedef _HwndNative = Int32 Function(IntPtr);
typedef _HwndDart = int Function(int);
typedef _ShowNative = Int32 Function(IntPtr, Int32);
typedef _ShowDart = int Function(int, int);

/// Windows: puts the EteroTV window above VLC (even in full screen) while
/// the "next episode" message is up, and back to normal afterwards.
class WinWindow {
  static int _hwnd() {
    final user32 = DynamicLibrary.open('user32.dll');
    final find = user32.lookupFunction<_FindNative, _FindDart>('FindWindowW');
    final cls = 'FLUTTER_RUNNER_WIN32_WINDOW'.toNativeUtf16();
    final title = 'EteroTV'.toNativeUtf16();
    try {
      return find(cls, title);
    } finally {
      malloc.free(cls);
      malloc.free(title);
    }
  }

  static void _set({required bool top}) {
    if (!Platform.isWindows) return;
    try {
      final hwnd = _hwnd();
      if (hwnd == 0) return;
      final user32 = DynamicLibrary.open('user32.dll');
      final pos = user32.lookupFunction<_PosNative, _PosDart>('SetWindowPos');
      const noMoveNoSizeShow = 0x0002 | 0x0001 | 0x0040;
      if (top) {
        user32.lookupFunction<_ShowNative, _ShowDart>('ShowWindow')(hwnd, 9); // SW_RESTORE
        pos(hwnd, -1, 0, 0, 0, 0, noMoveNoSizeShow); // HWND_TOPMOST
        user32.lookupFunction<_HwndNative, _HwndDart>('SetForegroundWindow')(hwnd);
      } else {
        pos(hwnd, -2, 0, 0, 0, 0, noMoveNoSizeShow); // HWND_NOTOPMOST
      }
    } catch (_) {
      // Only a convenience: the message still shows in the app.
    }
  }

  static void bringToFront() => _set(top: true);
  static void release() => _set(top: false);
}
