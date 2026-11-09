import 'package:flutter/material.dart';

const accent = Color(0xFFE5A00D);

ThemeData eteroTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: accent,
    brightness: Brightness.dark,
    surface: const Color(0xFF141414),
  );
  return ThemeData(
    colorScheme: scheme,
    scaffoldBackgroundColor: const Color(0xFF141414),
    useMaterial3: true,
    // Big, clear focus for the TV remote.
    focusColor: accent.withValues(alpha: 0.35),
    visualDensity: VisualDensity.standard,
  );
}
