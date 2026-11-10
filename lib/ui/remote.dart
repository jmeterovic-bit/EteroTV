import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../platform/device.dart';
import 'tv_focus.dart';

/// Keys that mean "OK" on a TV remote, a keyboard or a gamepad.
final _okKeys = {
  LogicalKeyboardKey.select,
  LogicalKeyboardKey.enter,
  LogicalKeyboardKey.numpadEnter,
  LogicalKeyboardKey.gameButtonA,
};

bool isOkKey(LogicalKeyboardKey k) => _okKeys.contains(k);

/// The remote has no long press, so this opens an item's menu by holding OK
/// (about half a second) or with the menu key (≡ on Fire TV). A short OK
/// still runs [onSelect]. The phone keeps its long press on the child.
///
/// Wrap the focusable widget (InkWell, ListTile...) with it: key events go
/// up from the focused widget, so this sees OK before the app does.
class RemoteMenu extends StatefulWidget {
  const RemoteMenu({super.key, required this.onSelect, required this.onMenu, required this.child});
  final VoidCallback onSelect;
  final VoidCallback? onMenu;
  final Widget child;

  static const holdTime = Duration(milliseconds: 550);

  @override
  State<RemoteMenu> createState() => _RemoteMenuState();
}

/// The OK still held after a menu opened would go on to the menu's first
/// option (key repeats and the release press it): this keeps that OK away
/// until it is let go.
void _swallowOkUntilUp() {
  late KeyEventResult Function(KeyEvent) handler;
  handler = (KeyEvent e) {
    if (!isOkKey(e.logicalKey)) return KeyEventResult.ignored;
    if (e is KeyUpEvent) {
      // After this event: removing a handler while it runs is not allowed.
      scheduleMicrotask(() => FocusManager.instance.removeEarlyKeyEventHandler(handler));
    }
    return KeyEventResult.handled;
  };
  FocusManager.instance.addEarlyKeyEventHandler(handler);
}

class _RemoteMenuState extends State<RemoteMenu> {
  Timer? _hold;
  bool _down = false;
  bool _opened = false;

  @override
  void dispose() {
    _hold?.cancel();
    super.dispose();
  }

  KeyEventResult _key(FocusNode node, KeyEvent e) {
    final menu = widget.onMenu;
    if (menu == null) return KeyEventResult.ignored;
    if (e.logicalKey == LogicalKeyboardKey.contextMenu) {
      if (e is KeyDownEvent) menu();
      return KeyEventResult.handled;
    }
    if (!isOkKey(e.logicalKey)) return KeyEventResult.ignored;
    switch (e) {
      case KeyDownEvent():
        _down = true;
        _opened = false;
        _hold?.cancel();
        _hold = Timer(RemoteMenu.holdTime, () {
          if (!_down || !mounted) return;
          _opened = true;
          _swallowOkUntilUp();
          menu();
        });
      case KeyUpEvent():
        if (!_down) return KeyEventResult.ignored;
        _down = false;
        _hold?.cancel();
        if (!_opened) widget.onSelect();
      default:
        // Key repeats while holding: the timer decides.
        break;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) =>
      Focus(canRequestFocus: false, skipTraversal: true, onKeyEvent: _key, child: widget.child);
}

/// A text field that behaves on TV: moving through it with the arrows
/// does not open the keyboard, OK opens it, and the arrows always lead out
/// of it. On phone and PC it is a normal text field.
class RemoteTextField extends StatefulWidget {
  const RemoteTextField({
    super.key,
    this.typeNow,
    this.onChanged,
    this.onSubmitted,
    this.controller,
    this.decoration = const InputDecoration(),
    this.autofocus = false,
    this.textInputAction,
    this.keyboardType,
    this.obscureText = false,
    this.autofillHints,
    this.maxLength,
    this.style,
    this.textAlign = TextAlign.start,
    this.tv,
  });
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final TextEditingController? controller;
  final InputDecoration decoration;
  final bool autofocus;
  final TextInputAction? textInputAction;
  final TextInputType? keyboardType;
  final bool obscureText;
  final Iterable<String>? autofillHints;
  final int? maxLength;
  final TextStyle? style;
  final TextAlign textAlign;

  /// Overrides [runningOnTv] (tests).
  final bool? tv;

  /// Each time it ticks, the field takes the focus ready to type (the
  /// keyboard opens, also on TV).
  final Listenable? typeNow;

  @override
  State<RemoteTextField> createState() => _RemoteTextFieldState();
}

class _RemoteTextFieldState extends State<RemoteTextField> {
  // The keys go to the field's own node first: the text field's inner
  // shortcuts would take the arrows before a widget around it sees them.
  late final _focus = FocusNode(onKeyEvent: _key);
  bool _typing = false;

  bool get _tv => widget.tv ?? runningOnTv;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus && _typing) setState(() => _typing = false);
    });
    widget.typeNow?.addListener(_typeNow);
  }

  @override
  void didUpdateWidget(RemoteTextField old) {
    super.didUpdateWidget(old);
    if (old.typeNow != widget.typeNow) {
      old.typeNow?.removeListener(_typeNow);
      widget.typeNow?.addListener(_typeNow);
    }
  }

  void _typeNow() {
    if (!mounted) return;
    setState(() => _typing = true);
    _focus.requestFocus();
    // Once the field is editable (next frame), ask for the keyboard.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _focus.hasFocus) SystemChannels.textInput.invokeMethod<void>('TextInput.show');
    });
  }

  @override
  void dispose() {
    widget.typeNow?.removeListener(_typeNow);
    _focus.dispose();
    super.dispose();
  }

  KeyEventResult _key(FocusNode node, KeyEvent e) {
    if (!_tv || e is KeyUpEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    if (!_typing && isOkKey(k)) {
      if (e is KeyDownEvent) setState(() => _typing = true);
      return KeyEventResult.handled;
    }
    final dir = switch (k) {
      LogicalKeyboardKey.arrowUp => TraversalDirection.up,
      LogicalKeyboardKey.arrowDown => TraversalDirection.down,
      // While typing, left and right move the cursor.
      LogicalKeyboardKey.arrowLeft when !_typing => TraversalDirection.left,
      LogicalKeyboardKey.arrowRight when !_typing => TraversalDirection.right,
      _ => null,
    };
    if (dir == null) return KeyEventResult.ignored;
    tvFocusInDirection(_focus, dir);
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final field = TextField(
      focusNode: _focus,
      controller: widget.controller,
      autofocus: widget.autofocus,
      readOnly: _tv && !_typing,
      onChanged: widget.onChanged,
      textInputAction: widget.textInputAction,
      keyboardType: widget.keyboardType,
      obscureText: widget.obscureText,
      autofillHints: widget.autofillHints,
      maxLength: widget.maxLength,
      style: widget.style,
      textAlign: widget.textAlign,
      // On TV the focus stays on the field after «Buscar» / «Listo», so
      // the arrows go on from here (by default the field lets go of it).
      onEditingComplete: _tv ? () {} : null,
      onSubmitted: (v) {
        if (_typing) setState(() => _typing = false);
        widget.onSubmitted?.call(v);
      },
      decoration: _tv && !_typing
          ? widget.decoration.copyWith(hintText: [?widget.decoration.hintText, '(OK para escribir)'].join(' '))
          : widget.decoration,
    );
    return field;
  }
}

/// Keeps the app away from the edges that some TVs cut off (overscan).
class TvSafeArea extends StatelessWidget {
  const TvSafeArea({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: const Color(0xFF141414),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 18),
      child: MediaQuery.removePadding(
        context: context,
        removeLeft: true,
        removeRight: true,
        removeTop: true,
        removeBottom: true,
        child: child,
      ),
    ),
  );
}
