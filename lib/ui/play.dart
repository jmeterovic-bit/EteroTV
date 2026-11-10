import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../iptv/xtream.dart';
import '../platform/win_window.dart';
import '../player/vlc.dart';
import '../state/app_state.dart';

/// Checks the provider's connection limit, then runs [action] (which opens
/// VLC). Shows clear messages instead of failing silently.
/// When [action] returns a String (what was saved), it shows as a message.
///
/// After an episode is finished, offers the next one with a 10 s countdown
/// ("Siguiente episodio"). On Windows it also appears when the credits start,
/// over VLC.
Future<void> playWithChecks(
  BuildContext context,
  Future<Object?> Function(AppState) action, {
  bool checkConnections = true,
}) async {
  final state = context.read<AppState>();
  final messenger = ScaffoldMessenger.of(context);
  if (!await state.vlc.available()) {
    if (context.mounted) await _noVlc(context, state.vlc.name);
    return;
  }
  // Right after closing VLC the server may still count that stream: the
  // next episode skips this check.
  final warning = checkConnections ? await state.connectionWarning() : null;
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
  // Windows: credits reached while VLC plays.
  (CatalogItem, Episode)? acceptedNext;
  var declined = false;
  var asking = false;
  var vlcClosed = false;
  Future<void> onNearEnd() async {
    final e = state.nearEnd.value;
    if (e == null || asking || !context.mounted) return;
    asking = true;
    final next = await state.nextAfter(e);
    if (next == null || !context.mounted) return;
    WinWindow.bringToFront();
    final go = await showNextEpisode(context, next.$2);
    WinWindow.release();
    if (go && vlcClosed) {
      // VLC was closed while the message was up: start it from here.
      if (context.mounted) {
        await playWithChecks(context, (s) => s.playEpisode(next.$1, next.$2), checkConnections: false);
      }
    } else if (go) {
      acceptedNext = next;
      await state.stopPlayer();
    } else {
      declined = true;
    }
  }

  void listener() => onNearEnd();
  state.nearEnd.addListener(listener);
  try {
    final note = await action(state);
    if (note is String) messenger.showSnackBar(SnackBar(content: Text(note)));
  } on VlcMissing catch (e) {
    if (context.mounted) await _noVlc(context, e.player);
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('No se pudo abrir ${state.vlc.name}: $e')));
  } finally {
    vlcClosed = true;
    state.nearEnd.removeListener(listener);
    state.nearEnd.value = null;
  }

  final finished = state.takeUpNext();
  if (!context.mounted) return;
  var next = acceptedNext;
  if (next == null && finished != null && !declined && !asking) {
    next = await state.nextAfter(finished);
    if (next == null || !context.mounted) return;
    if (!await showNextEpisode(context, next.$2)) return;
  }
  if (next == null || !context.mounted) return;
  final (series, ep) = next;
  await playWithChecks(context, (s) => s.playEpisode(series, ep), checkConnections: false);
}

/// "Siguiente: T3 E4" with a 10 s countdown. True = play it.
Future<bool> showNextEpisode(BuildContext context, Episode ep) async =>
    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => NextEpisodeDialog(episode: ep),
    ) ??
    false;

class NextEpisodeDialog extends StatefulWidget {
  const NextEpisodeDialog({super.key, required this.episode, this.seconds = 10});
  final Episode episode;
  final int seconds;

  @override
  State<NextEpisodeDialog> createState() => _NextEpisodeDialogState();
}

class _NextEpisodeDialogState extends State<NextEpisodeDialog> {
  late int _left = widget.seconds;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_left <= 1) {
        t.cancel();
        if (mounted) Navigator.pop(context, true);
      } else {
        setState(() => _left--);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ep = widget.episode;
    return AlertDialog(
      title: Text('Siguiente: T${ep.season} E${ep.number}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (ep.title.isNotEmpty) Text(ep.title, maxLines: 2, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 16),
          LinearProgressIndicator(value: _left / widget.seconds),
          const SizedBox(height: 8),
          Text('Empieza en $_left s'),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
        FilledButton.icon(
          autofocus: true,
          icon: const Icon(Icons.play_arrow),
          label: const Text('Ver ahora'),
          onPressed: () => Navigator.pop(context, true),
        ),
      ],
    );
  }
}

Future<void> _noVlc(BuildContext context, String player) => showDialog<void>(
  context: context,
  builder: (c) => AlertDialog(
    title: Text('Falta $player'),
    content: Text(
      Platform.isAndroid
          ? 'Este aparato reproduce con $player. Instálalo desde Google Play o, en Fire TV, desde la Appstore de '
                'Amazon, o elige otro en Ajustes → Reproductor.'
          : 'EteroTV usa VLC para reproducir. Instálalo desde videolan.org (versión de 64 bits) y vuelve a intentarlo.',
    ),
    actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('Entendido'))],
  ),
);
