import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../player/vlc.dart';
import '../state/app_state.dart';

/// Checks the provider's connection limit, then runs [action] (which opens
/// VLC). Shows clear messages instead of failing silently.
/// When [action] returns a String (what was saved), it shows as a message.
Future<void> playWithChecks(BuildContext context, Future<Object?> Function(AppState) action) async {
  final state = context.read<AppState>();
  final messenger = ScaffoldMessenger.of(context);
  if (!await state.vlc.available()) {
    if (context.mounted) await _noVlc(context);
    return;
  }
  final warning = await state.connectionWarning();
  if (warning != null && context.mounted) {
    final go = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Límite de reproducciones'),
        content: Text(warning),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Abrir igual')),
        ],
      ),
    );
    if (go != true) return;
  }
  try {
    final note = await action(state);
    if (note is String) messenger.showSnackBar(SnackBar(content: Text(note)));
  } on VlcMissing {
    if (context.mounted) await _noVlc(context);
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('No se pudo abrir VLC: $e')));
  }
}

Future<void> _noVlc(BuildContext context) => showDialog<void>(
  context: context,
  builder: (c) => AlertDialog(
    title: const Text('Falta VLC'),
    content: Text(
      Platform.isAndroid
          ? 'EteroTV usa VLC para reproducir. Instálalo desde Google Play o, en Fire TV, desde la Appstore de Amazon.'
          : 'EteroTV usa VLC para reproducir. Instálalo desde videolan.org (versión de 64 bits) y vuelve a intentarlo.',
    ),
    actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('Entendido'))],
  ),
);
