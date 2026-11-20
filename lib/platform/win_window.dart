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
      } else if (!WinMini.active) {
        // Not while the player is a small window on top: it stays on top.
        pos(hwnd, -2, 0, 0, 0, 0, noMoveNoSizeShow); // HWND_NOTOPMOST
      }
    } catch (_) {
      // Only a convenience: the message still shows in the app.
    }
  }

  static void bringToFront() => _set(top: true);
  static void release() => _set(top: false);
}

final class _Rect extends Struct {
  @Int32()
  external int left;
  @Int32()
  external int top;
  @Int32()
  external int right;
  @Int32()
  external int bottom;
}

final class _MonitorInfo extends Struct {
  @Uint32()
  external int cbSize;
  external _Rect rcMonitor;
  external _Rect rcWork;
  @Uint32()
  external int dwFlags;
}

typedef _RectNative = Int32 Function(IntPtr, Pointer<_Rect>);
typedef _RectDart = int Function(int, Pointer<_Rect>);
typedef _MonNative = IntPtr Function(IntPtr, Uint32);
typedef _MonDart = int Function(int, int);
typedef _MonInfoNative = Int32 Function(IntPtr, Pointer<_MonitorInfo>);
typedef _MonInfoDart = int Function(int, Pointer<_MonitorInfo>);

/// Windows: the player's «small window on top» (2.4.0, Jose: Windows has no
/// picture in picture of its own). The EteroTV window shrinks to a corner of
/// the screen and stays above the other programs; [restore] puts it back
/// where and how big it was.
class WinMini {
  static (int, int, int, int)? _saved;
  static bool _wasMaximized = false;

  /// The window is small and on top right now.
  static bool get active => _saved != null;

  /// Width of the small window's picture; the height follows the video.
  static const width = 480;

  /// Shrinks the window to the bottom right of its screen, [width] wide and
  /// with the shape of the video ([videoW] × [videoH]). False if it could not.
  static bool shrink({int videoW = 16, int videoH = 9}) {
    if (!Platform.isWindows || active) return false;
    final r = calloc<_Rect>();
    final c = calloc<_Rect>();
    final m = calloc<_MonitorInfo>();
    try {
      final hwnd = WinWindow._hwnd();
      if (hwnd == 0) return false;
      final user32 = DynamicLibrary.open('user32.dll');
      final zoomed = user32.lookupFunction<_HwndNative, _HwndDart>('IsZoomed')(hwnd) != 0;
      final show = user32.lookupFunction<_ShowNative, _ShowDart>('ShowWindow');
      if (zoomed) show(hwnd, 9); // SW_RESTORE, so the saved size is the normal one
      user32.lookupFunction<_RectNative, _RectDart>('GetWindowRect')(hwnd, r);
      user32.lookupFunction<_RectNative, _RectDart>('GetClientRect')(hwnd, c);
      final frameW = (r.ref.right - r.ref.left) - (c.ref.right - c.ref.left);
      final frameH = (r.ref.bottom - r.ref.top) - (c.ref.bottom - c.ref.top);
      final mon = user32.lookupFunction<_MonNative, _MonDart>('MonitorFromWindow')(hwnd, 2); // NEAREST
      m.ref.cbSize = sizeOf<_MonitorInfo>();
      user32.lookupFunction<_MonInfoNative, _MonInfoDart>('GetMonitorInfoW')(mon, m);
      final work = m.ref.rcWork;
      final ratio = videoW > 0 && videoH > 0 ? (videoH / videoW).clamp(0.3, 1.5) : 9 / 16;
      final w = width + frameW;
      final h = (width * ratio).round() + frameH;
      const gap = 16;
      _saved = (r.ref.left, r.ref.top, r.ref.right - r.ref.left, r.ref.bottom - r.ref.top);
      _wasMaximized = zoomed;
      final pos = user32.lookupFunction<_PosNative, _PosDart>('SetWindowPos');
      pos(hwnd, -1, work.right - w - gap, work.bottom - h - gap, w, h, 0x0040); // HWND_TOPMOST, SHOWWINDOW
      return true;
    } catch (_) {
      return false;
    } finally {
      calloc
        ..free(r)
        ..free(c)
        ..free(m);
    }
  }

  /// Back to the size and place it had, and no longer above everything.
  static void restore() {
    final s = _saved;
    if (s == null) return;
    _saved = null;
    try {
      final hwnd = WinWindow._hwnd();
      if (hwnd == 0) return;
      final user32 = DynamicLibrary.open('user32.dll');
      final pos = user32.lookupFunction<_PosNative, _PosDart>('SetWindowPos');
      pos(hwnd, -2, s.$1, s.$2, s.$3, s.$4, 0x0040); // HWND_NOTOPMOST
      if (_wasMaximized) user32.lookupFunction<_ShowNative, _ShowDart>('ShowWindow')(hwnd, 3); // SW_MAXIMIZE
    } catch (_) {}
  }
}
