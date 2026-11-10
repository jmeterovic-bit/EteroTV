import 'package:flutter/material.dart';

const accent = Color(0xFFE5A00D);

/// A white frame around the focused button, so the remote's position is
/// always clear (Material's own focus tint is too faint on a TV).
WidgetStateProperty<BorderSide?> _focusSide([BorderSide? normal]) => WidgetStateProperty.resolveWith(
  (s) => s.contains(WidgetState.focused) ? const BorderSide(color: Colors.white, width: 2.5) : normal,
);

ThemeData eteroTheme() {
  final scheme = ColorScheme.fromSeed(seedColor: accent, brightness: Brightness.dark, surface: const Color(0xFF141414));
  return ThemeData(
    colorScheme: scheme,
    scaffoldBackgroundColor: const Color(0xFF141414),
    useMaterial3: true,
    // Big, clear focus for the TV remote.
    focusColor: accent.withValues(alpha: 0.35),
    visualDensity: VisualDensity.standard,
    filledButtonTheme: FilledButtonThemeData(style: ButtonStyle(side: _focusSide())),
    textButtonTheme: TextButtonThemeData(style: ButtonStyle(side: _focusSide())),
    elevatedButtonTheme: ElevatedButtonThemeData(style: ButtonStyle(side: _focusSide())),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: ButtonStyle(side: _focusSide(BorderSide(color: scheme.outline))),
    ),
    iconButtonTheme: IconButtonThemeData(style: ButtonStyle(side: _focusSide())),
  );
}
