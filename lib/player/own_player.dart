import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../ui/i18n.dart';
import 'vlc.dart';

/// Set on the app's MaterialApp, so the player can open its screen from
/// AppState (which has no BuildContext). One per app language: the app is
/// built anew when the language changes, and a shared key would carry the
/// old screens over.
GlobalKey<NavigatorState> navigatorKey = GlobalKey();
final _navigatorKeys = <Object, GlobalKey<NavigatorState>>{};
GlobalKey<NavigatorState> navigatorKeyFor(Object lang) =>
    navigatorKey = _navigatorKeys.putIfAbsent(lang, GlobalKey<NavigatorState>.new);

/// mpv's options for the languages chosen. Without a track in that language,
/// mpv plays the video's own (default) one. Forced subtitles are never chosen
/// on their own (`subs-fallback-forced=no`).
Map<String, String> mpvTrackOptions(TrackLang audio, TrackLang subs) => {
  'alang': ?audio.vlcCodes,
  'slang': ?subs.vlcCodes,
  'sid': subs == TrackLang.none ? 'no' : 'auto',
  'subs-fallback-forced': 'no',
};

/// EteroTV's own player (2026-11-10, Jose: VLC failed on his Bravia and
/// took no language from the app). Built on media_kit (the mpv engine).
/// It runs inside the app, so it knows the position and the tracks.
class OwnPlayer extends VlcLauncher {
  /// Ajustes → Reproductor (this device): off when a TV's chip decodes badly.
  bool hardwareDecoding = true;

  @override
  String get name => 'EteroTV';

  @override
  Future<bool> available() async => true;

  VoidCallback? _close;

  @override
  Future<void> stop() async => _close?.call();

  @override
  Future<PlayResult?> play(
    String url, {
    required String title,
    int startSecs = 0,
    void Function(int positionSecs, int lengthSecs)? onProgress,
  }) async {
    final nav = navigatorKey.currentState;
    if (nav == null) return null;
    final done = Completer<PlayResult?>();
    unawaited(
      nav.push(
        MaterialPageRoute<void>(
          builder: (_) => OwnPlayerScreen(
            url: url,
            title: title,
            startSecs: startSecs,
            audio: audioLang,
            subs: subLang,
            hardwareDecoding: hardwareDecoding,
            onProgress: onProgress,
            onOpen: (c) => _close = c,
            onDone: (r) {
              _close = null;
              if (!done.isCompleted) done.complete(r);
            },
          ),
        ),
      ),
    );
    return done.future;
  }
}

class OwnPlayerScreen extends StatefulWidget {
  const OwnPlayerScreen({
    super.key,
    required this.url,
    required this.title,
    this.startSecs = 0,
    this.audio = TrackLang.original,
    this.subs = TrackLang.none,
    this.hardwareDecoding = true,
    this.onProgress,
    this.onOpen,
    this.onDone,
  });

  final String url;
  final String title;
  final int startSecs;
  final TrackLang audio;
  final TrackLang subs;
  final bool hardwareDecoding;
  final void Function(int positionSecs, int lengthSecs)? onProgress;

  /// Gets the function that closes the screen (for [OwnPlayer.stop]).
  final void Function(VoidCallback close)? onOpen;
  final void Function(PlayResult?)? onDone;

  @override
  State<OwnPlayerScreen> createState() => _OwnPlayerScreenState();
}

class _OwnPlayerScreenState extends State<OwnPlayerScreen> {
  // Logs off: mpv would print the stream URL, which carries the IPTV password.
  late final Player _player = Player(
    configuration: const PlayerConfiguration(logLevel: MPVLogLevel.error, title: 'EteroTV'),
  );
  late final VideoController _video = VideoController(
    _player,
    configuration: VideoControllerConfiguration(enableHardwareAcceleration: widget.hardwareDecoding),
  );
  final _focus = FocusNode();
  final List<StreamSubscription<Object?>> _subs = [];

  Duration _pos = Duration.zero;
  Duration _len = Duration.zero;
  bool _playing = false;
  bool _buffering = true;
  bool _ended = false;
  String? _error;

  /// The bar with the title, time and buttons. Hides after a few seconds.
  bool _overlay = true;
  Timer? _hideTimer;

  /// "-10 s" / "+10 s" shown for a moment after a seek.
  String? _flash;
  Timer? _flashTimer;
  int _lastReport = -1;

  static const _step = Duration(seconds: 10);

  @override
  void initState() {
    super.initState();
    widget.onOpen?.call(close);
    _subs
      ..add(
        _player.stream.position.listen((p) {
          _pos = p;
          final s = p.inSeconds;
          if (s != _lastReport && _len > Duration.zero) {
            _lastReport = s;
            widget.onProgress?.call(s, _len.inSeconds);
          }
          if (_overlay && mounted) setState(() {});
        }),
      )
      ..add(_player.stream.duration.listen((d) => setState(() => _len = d)))
      ..add(_player.stream.playing.listen((v) => setState(() => _playing = v)))
      ..add(_player.stream.buffering.listen((v) => setState(() => _buffering = v)))
      ..add(_player.stream.error.listen((e) => setState(() => _error = hideUrls(e))))
      ..add(
        _player.stream.completed.listen((v) {
          if (v && !_ended) {
            _ended = true;
            close();
          }
        }),
      );
    _start();
    _showOverlay();
    if (Platform.isAndroid) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
  }

  Future<void> _start() async {
    final native = _player.platform;
    if (native is NativePlayer) {
      for (final o in mpvTrackOptions(widget.audio, widget.subs).entries) {
        await native.setProperty(o.key, o.value);
      }
    }
    await _player.open(Media(widget.url, start: Duration(seconds: widget.startSecs)));
  }

  bool _closing = false;

  /// Leaves the player (Back, Esc, end of the video, or the next episode).
  void close() {
    if (_closing || !mounted) return;
    _closing = true;
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    final len = _len.inSeconds;
    widget.onDone?.call(
      PlayResult(positionSecs: _ended && len > 0 ? len : _pos.inSeconds, durationSecs: len > 0 ? len : null),
    );
    for (final s in _subs) {
      s.cancel();
    }
    _hideTimer?.cancel();
    _flashTimer?.cancel();
    _focus.dispose();
    _player.dispose();
    if (Platform.isAndroid) SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _showOverlay() {
    setState(() => _overlay = true);
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && _playing) setState(() => _overlay = false);
    });
  }

  void _toggleOverlay() {
    if (_overlay) {
      _hideTimer?.cancel();
      setState(() => _overlay = false);
    } else {
      _showOverlay();
    }
  }

  void _playPause() {
    _player.playOrPause();
    _showOverlay();
  }

  void _seekBy(Duration d) {
    if (_len == Duration.zero) return; // live channel
    var t = _pos + d;
    if (t < Duration.zero) t = Duration.zero;
    if (t > _len) t = _len;
    _player.seek(t);
    _pos = t;
    _flashTimer?.cancel();
    setState(() => _flash = d.isNegative ? '-${d.inSeconds.abs()} s' : '+${d.inSeconds} s');
    _flashTimer = Timer(const Duration(milliseconds: 700), () {
      if (mounted) setState(() => _flash = null);
    });
    _showOverlay();
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent e) {
    if (e is KeyUpEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    final repeat = e is KeyRepeatEvent;
    if (k == LogicalKeyboardKey.arrowLeft || k == LogicalKeyboardKey.mediaRewind) {
      _seekBy(repeat ? -_step * 3 : -_step);
    } else if (k == LogicalKeyboardKey.arrowRight || k == LogicalKeyboardKey.mediaFastForward) {
      _seekBy(repeat ? _step * 3 : _step);
    } else if (repeat) {
      return KeyEventResult.handled;
    } else if (k == LogicalKeyboardKey.select ||
        k == LogicalKeyboardKey.enter ||
        k == LogicalKeyboardKey.space ||
        k == LogicalKeyboardKey.mediaPlayPause ||
        k == LogicalKeyboardKey.gameButtonA) {
      _playPause();
    } else if (k == LogicalKeyboardKey.mediaPlay) {
      _player.play();
    } else if (k == LogicalKeyboardKey.mediaPause) {
      _player.pause();
    } else if (k == LogicalKeyboardKey.arrowUp || k == LogicalKeyboardKey.keyL || k == LogicalKeyboardKey.contextMenu) {
      _chooseTracks();
    } else if (k == LogicalKeyboardKey.arrowDown) {
      _toggleOverlay();
    } else if (k == LogicalKeyboardKey.keyF && !Platform.isAndroid) {
      _toggleFullscreen();
    } else if (k == LogicalKeyboardKey.escape ||
        k == LogicalKeyboardKey.goBack ||
        k == LogicalKeyboardKey.browserBack ||
        k == LogicalKeyboardKey.mediaStop) {
      close();
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  bool _fullscreen = false;
  Future<void> _toggleFullscreen() async {
    _fullscreen = !_fullscreen;
    await (_fullscreen ? defaultEnterNativeFullscreen() : defaultExitNativeFullscreen());
  }

  /// Audio and subtitles of this video.
  Future<void> _chooseTracks() async {
    _hideTimer?.cancel();
    final tracks = _player.state.tracks;
    final current = _player.state.track;
    String label(String? title, String? lang, int i) {
      final parts = [
        if (lang != null && lang.isNotEmpty) _langName(lang),
        if (title != null && title.isNotEmpty) title,
      ];
      return parts.isEmpty ? tr('Pista {0}', [i]) : parts.join(' · ');
    }

    final audio = [
      for (final t in tracks.audio)
        if (t.id != 'auto' && t.id != 'no') t,
    ];
    final subs = [
      for (final t in tracks.subtitle)
        if (t.id != 'auto') t,
    ];
    await showDialog<void>(
      context: context,
      builder: (c) => SimpleDialog(
        title: Text(tr('Audio y subtítulos')),
        children: [
          if (audio.length > 1) ...[
            _Header(tr('Audio')),
            for (final (i, t) in audio.indexed)
              _TrackTile(
                selected: t == current.audio,
                label: label(t.title, t.language, i + 1),
                onTap: () {
                  _player.setAudioTrack(t);
                  Navigator.pop(c);
                },
              ),
          ],
          _Header(tr('Subtítulos')),
          for (final (i, t) in subs.indexed)
            _TrackTile(
              selected: t == current.subtitle,
              label: t.id == 'no' ? tr('Sin subtítulos') : label(t.title, t.language, i),
              onTap: () {
                _player.setSubtitleTrack(t);
                Navigator.pop(c);
              },
            ),
        ],
      ),
    );
    if (mounted) {
      _focus.requestFocus();
      _showOverlay();
    }
  }

  static String _langName(String code) => switch (code.toLowerCase()) {
    'es' || 'spa' => tr('Español'),
    'en' || 'eng' => tr('Inglés'),
    'fr' || 'fra' || 'fre' => tr('Francés'),
    _ => code,
  };

  @override
  Widget build(BuildContext context) {
    final touch = Platform.isAndroid || Platform.isIOS;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Focus(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: _onKey,
        child: MouseRegion(
          onHover: touch ? null : (_) => _showOverlay(),
          cursor: _overlay ? SystemMouseCursors.basic : SystemMouseCursors.none,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Video(controller: _video, controls: NoVideoControls),
              // Phone: tap shows the bar, double tap on a side jumps 10 s
              // (like VLC). Windows: click pauses, double click is full screen.
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: touch ? _toggleOverlay : _playPause,
                      onDoubleTap: touch ? () => _seekBy(-_step) : _toggleFullscreen,
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: touch ? _toggleOverlay : _playPause,
                      onDoubleTap: touch ? _playPause : _toggleFullscreen,
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: touch ? _toggleOverlay : _playPause,
                      onDoubleTap: touch ? () => _seekBy(_step) : _toggleFullscreen,
                    ),
                  ),
                ],
              ),
              if (_buffering && _error == null) const Center(child: CircularProgressIndicator()),
              if (_error != null)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      tr('No se pudo reproducir: {0}', [_error!]),
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontSize: 18),
                    ),
                  ),
                ),
              if (_flash != null)
                Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(12)),
                    child: Text(_flash!, style: const TextStyle(color: Colors.white, fontSize: 28)),
                  ),
                ),
              if (_overlay) _bar(touch),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bar(bool touch) {
    final live = _len == Duration.zero;
    const white = TextStyle(color: Colors.white);
    return Column(
      children: [
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.black87, Colors.transparent],
            ),
          ),
          padding: const EdgeInsets.fromLTRB(8, 16, 16, 32),
          child: Row(
            children: [
              IconButton(
                color: Colors.white,
                icon: const Icon(Icons.arrow_back),
                tooltip: tr('Salir'),
                onPressed: close,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: white.copyWith(fontSize: 20),
                ),
              ),
            ],
          ),
        ),
        const Spacer(),
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [Colors.black87, Colors.transparent],
            ),
          ),
          padding: const EdgeInsets.fromLTRB(16, 32, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!live)
                Row(
                  children: [
                    Text(formatClock(_pos), style: white),
                    Expanded(
                      child: Slider(
                        focusNode: FocusNode(skipTraversal: true, canRequestFocus: false),
                        value: _pos.inMilliseconds.clamp(0, _len.inMilliseconds).toDouble(),
                        max: _len.inMilliseconds.toDouble(),
                        onChanged: (v) {
                          _player.seek(Duration(milliseconds: v.round()));
                          _showOverlay();
                        },
                      ),
                    ),
                    Text(formatClock(_len), style: white),
                  ],
                ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (!live) _Btn(icon: Icons.replay_10, tip: tr('Atrás 10 s'), onTap: () => _seekBy(-_step)),
                  _Btn(
                    icon: _playing ? Icons.pause : Icons.play_arrow,
                    tip: _playing ? tr('Pausa') : tr('Reproducir'),
                    size: 40,
                    onTap: _playPause,
                  ),
                  if (!live) _Btn(icon: Icons.forward_10, tip: tr('Adelante 10 s'), onTap: () => _seekBy(_step)),
                  const SizedBox(width: 24),
                  _Btn(icon: Icons.subtitles, tip: tr('Audio y subtítulos'), onTap: _chooseTracks),
                  if (!touch) _Btn(icon: Icons.fullscreen, tip: tr('Pantalla completa'), onTap: _toggleFullscreen),
                ],
              ),
              if (!touch)
                Text(
                  tr('OK: pausa · ◀ ▶: 10 s · ▲: audio y subtítulos · Atrás: salir'),
                  style: white.copyWith(fontSize: 12, color: Colors.white70),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// mpv's errors can quote the stream address, which carries the IPTV
/// password: it never reaches the screen.
String hideUrls(String text) => text.replaceAll(RegExp(r'\w+://\S+'), '…');

/// 1:02:03 or 2:03.
String formatClock(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60).toString().padLeft(h > 0 ? 2 : 1, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return h > 0 ? '$h:$m:$s' : '$m:$s';
}

/// Not focusable: on a TV the remote's keys go straight to the player.
class _Btn extends StatelessWidget {
  const _Btn({required this.icon, required this.tip, required this.onTap, this.size = 32});
  final IconData icon;
  final String tip;
  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) => ExcludeFocus(
    child: IconButton(color: Colors.white, iconSize: size, tooltip: tip, icon: Icon(icon), onPressed: onTap),
  );
}

class _Header extends StatelessWidget {
  const _Header(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 12, 24, 4),
    child: Text(text, style: Theme.of(context).textTheme.labelLarge),
  );
}

class _TrackTile extends StatelessWidget {
  const _TrackTile({required this.selected, required this.label, required this.onTap});
  final bool selected;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    autofocus: selected,
    leading: Icon(selected ? Icons.radio_button_checked : Icons.radio_button_unchecked),
    title: Text(label),
    onTap: onTap,
  );
}
