import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../iptv/xtream.dart';
import '../platform/device.dart';
import '../ui/i18n.dart';
import '../ui/remote.dart';
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

/// How the own player decodes the video (Ajustes → Reproductor, per device).
enum VideoDecode {
  /// The chip decodes and mpv draws the picture (it can fall back to
  /// software for a track the chip refuses).
  auto,

  /// Android: the chip decodes and draws straight on the screen, like Just
  /// Player. Sharpest and lightest, but a video the chip cannot decode
  /// shows no picture.
  direct,

  /// No chip: the processor decodes. Slower, works with anything.
  software;

  static VideoDecode fromName(String? n) => values.firstWhere((d) => d.name == n, orElse: () => auto);

  VideoControllerConfiguration get configuration => switch (this) {
    auto => const VideoControllerConfiguration(),
    direct => const VideoControllerConfiguration(vo: 'mediacodec_embed', hwdec: 'mediacodec'),
    software => const VideoControllerConfiguration(enableHardwareAcceleration: false),
  };
}

/// EteroTV's own player (2026-11-10, Jose: VLC failed on his Bravia and
/// took no language from the app). Built on media_kit (the mpv engine).
/// It runs inside the app, so it knows the position and the tracks.
class OwnPlayer extends VlcLauncher {
  VideoDecode decode = VideoDecode.auto;

  /// For the next live channel: its guide, shown over the video.
  Future<List<EpgEntry>> Function()? nextEpg;

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
    final epg = nextEpg;
    nextEpg = null;
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
            decode: decode,
            epg: epg,
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
    this.decode = VideoDecode.auto,
    this.epg,
    this.onProgress,
    this.onOpen,
    this.onDone,
  });

  final String url;
  final String title;
  final int startSecs;
  final TrackLang audio;
  final TrackLang subs;
  final VideoDecode decode;

  /// Live channels: loads the guide shown in the bar.
  final Future<List<EpgEntry>> Function()? epg;
  final void Function(int positionSecs, int lengthSecs)? onProgress;

  /// Gets the function that closes the screen (for [OwnPlayer.stop]).
  final void Function(VoidCallback close)? onOpen;
  final void Function(PlayResult?)? onDone;

  @override
  State<OwnPlayerScreen> createState() => _OwnPlayerScreenState();
}

/// A button of the bar. On a TV the remote moves a highlight over them
/// (they take no focus, so the arrows never leave the player).
class _Action {
  const _Action(this.icon, this.tip, this.onTap, {this.size = 32});
  final IconData icon;
  final String tip;
  final VoidCallback onTap;
  final double size;
}

class _OwnPlayerScreenState extends State<OwnPlayerScreen> {
  // Logs off: mpv would print the stream URL, which carries the IPTV password.
  late final Player _player = Player(
    configuration: const PlayerConfiguration(logLevel: MPVLogLevel.error, title: 'EteroTV'),
  );
  late final VideoController _video = VideoController(_player, configuration: widget.decode.configuration);
  final _focus = FocusNode();
  final List<StreamSubscription<Object?>> _subs = [];

  Duration _pos = Duration.zero;
  Duration _len = Duration.zero;
  bool _playing = false;
  bool _buffering = true;
  bool _ended = false;

  /// The video got going: an error after this (a track the chip refused)
  /// does not stop it, so it is not shown.
  bool _started = false;
  String? _error;

  /// The bar with the title, time and buttons. Hides after a few seconds.
  bool _overlay = true;
  Timer? _hideTimer;

  /// Remote and keyboard: what the highlight is on. -1 is the time line
  /// (◀ ▶ move the video), 0… the buttons.
  int _sel = 0;
  bool _keys = false;

  /// "-10 s" / "+10 s" shown for a moment after a seek.
  String? _flash;
  Timer? _flashTimer;
  int _lastReport = -1;

  List<EpgEntry> _guide = [];
  Timer? _guideTimer;

  static const _step = Duration(seconds: 10);

  bool get _live => widget.epg != null || _len == Duration.zero;

  @override
  void initState() {
    super.initState();
    widget.onOpen?.call(close);
    tvFullScreen.value = true;
    _subs
      ..add(
        _player.stream.position.listen((p) {
          _pos = p;
          if (p > Duration.zero) _started = true;
          final s = p.inSeconds;
          if (s != _lastReport && _len > Duration.zero) {
            _lastReport = s;
            widget.onProgress?.call(s, _len.inSeconds);
          }
          if (mounted && (_overlay || _error != null)) setState(() {});
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
    _loadGuide();
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

  Future<void> _loadGuide() async {
    final load = widget.epg;
    if (load == null) return;
    final g = await load();
    if (!mounted) return;
    setState(() => _guide = g);
    // Refresh the "now" line when the programme changes.
    _guideTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted && _overlay) setState(() {});
    });
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
    _guideTimer?.cancel();
    _focus.dispose();
    _player.dispose();
    tvFullScreen.value = false;
    if (Platform.isAndroid) SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _showOverlay({int? select}) {
    setState(() {
      _overlay = true;
      if (select != null) _sel = select;
    });
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 5), () {
      if (mounted && _playing) setState(() => _overlay = false);
    });
  }

  void _hideOverlay() {
    _hideTimer?.cancel();
    setState(() => _overlay = false);
  }

  void _toggleOverlay() => _overlay ? _hideOverlay() : _showOverlay();

  void _playPause() {
    _player.playOrPause();
    _showOverlay();
  }

  void _seekBy(Duration d) {
    if (_live) return;
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

  List<_Action> _actions(bool touch) => [
    if (!_live) _Action(Icons.replay_10, tr('Atrás 10 s'), () => _seekBy(-_step)),
    _Action(_playing ? Icons.pause : Icons.play_arrow, _playing ? tr('Pausa') : tr('Reproducir'), _playPause, size: 40),
    if (!_live) _Action(Icons.forward_10, tr('Adelante 10 s'), () => _seekBy(_step)),
    _Action(Icons.subtitles, tr('Audio y subtítulos'), _chooseTracks),
    if (!touch) _Action(Icons.fullscreen, tr('Pantalla completa'), _toggleFullscreen),
  ];

  int get _playIndex => _live ? 0 : 1;

  KeyEventResult _onKey(FocusNode _, KeyEvent e) {
    if (e is KeyUpEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    final repeat = e is KeyRepeatEvent;
    final left = k == LogicalKeyboardKey.arrowLeft;
    final right = k == LogicalKeyboardKey.arrowRight;
    final up = k == LogicalKeyboardKey.arrowUp;
    final down = k == LogicalKeyboardKey.arrowDown;
    final ok = k == LogicalKeyboardKey.select || k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.gameButtonA;
    final back = k == LogicalKeyboardKey.goBack || k == LogicalKeyboardKey.browserBack;
    _keys = true;
    final actions = _actions(Platform.isAndroid || Platform.isIOS);
    final onLine = _sel < 0;

    if (k == LogicalKeyboardKey.mediaRewind) {
      _seekBy(-_step * 3);
    } else if (k == LogicalKeyboardKey.mediaFastForward) {
      _seekBy(_step * 3);
    } else if (k == LogicalKeyboardKey.mediaPlayPause || k == LogicalKeyboardKey.space) {
      if (!repeat) _playPause();
    } else if (k == LogicalKeyboardKey.mediaPlay) {
      _player.play();
    } else if (k == LogicalKeyboardKey.mediaPause) {
      _player.pause();
    } else if (k == LogicalKeyboardKey.mediaStop || k == LogicalKeyboardKey.escape) {
      close();
    } else if (k == LogicalKeyboardKey.keyL || k == LogicalKeyboardKey.contextMenu) {
      if (!repeat) _chooseTracks();
    } else if (k == LogicalKeyboardKey.keyF && !Platform.isAndroid) {
      if (!repeat) _toggleFullscreen();
    } else if (!_overlay) {
      // Bar hidden: ◀ ▶ move the video, OK pauses, anything else shows the bar.
      if (left || right) {
        if (!_live) _sel = -1;
        _seekBy((left ? -_step : _step) * (repeat ? 3 : 1));
      } else if (ok) {
        if (repeat) return KeyEventResult.handled;
        _player.playOrPause();
        _showOverlay(select: _playIndex);
      } else if (up || down) {
        _showOverlay(select: _playIndex);
      } else if (back) {
        close();
      } else {
        return KeyEventResult.ignored;
      }
    } else {
      // Bar shown: the highlight moves over the time line and the buttons.
      if (left || right) {
        if (onLine) {
          _seekBy((left ? -_step : _step) * (repeat ? 3 : 1));
        } else {
          _showOverlay(select: (_sel + (left ? -1 : 1)).clamp(0, actions.length - 1));
        }
      } else if (up) {
        if (!onLine && !_live) _showOverlay(select: -1);
      } else if (down) {
        onLine ? _showOverlay(select: _playIndex) : _hideOverlay();
      } else if (ok) {
        if (repeat) return KeyEventResult.handled;
        if (onLine) {
          _playPause();
        } else {
          actions[_sel.clamp(0, actions.length - 1)].onTap();
        }
      } else if (back) {
        _hideOverlay();
      } else {
        return KeyEventResult.ignored;
      }
    }
    return KeyEventResult.handled;
  }

  bool _fullscreen = false;
  Future<void> _toggleFullscreen() async {
    _fullscreen = !_fullscreen;
    await (_fullscreen ? defaultEnterNativeFullscreen() : defaultExitNativeFullscreen());
  }

  /// What the video is and how it is decoded, to compare settings.
  Future<String> _videoInfo() async {
    final native = _player.platform;
    if (native is! NativePlayer) return '';
    Future<String> get(String p) async {
      try {
        return await native.getProperty(p);
      } catch (_) {
        return '';
      }
    }

    final codec = await get('video-codec');
    final w = await get('width');
    final h = await get('height');
    final hw = await get('hwdec-current');
    final audio = await get('audio-codec-name');
    final mode = switch (widget.decode) {
      VideoDecode.auto => tr('chip'),
      VideoDecode.direct => tr('chip directo'),
      VideoDecode.software => tr('sin chip'),
    };
    return [
      tr('Video: {0} {1}×{2}', [codec, w, h]),
      tr('Decodifica: {0} ({1})', [hw.isEmpty || hw == 'no' ? tr('procesador') : hw, mode]),
      if (audio.isNotEmpty) tr('Audio: {0}', [audio]),
    ].join('\n');
  }

  /// Audio and subtitles of this video.
  Future<void> _chooseTracks() async {
    _hideTimer?.cancel();
    final tracks = _player.state.tracks;
    final current = _player.state.track;
    final info = await _videoInfo();
    if (!mounted) return;
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
          if (info.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
              child: Text(info, style: Theme.of(c).textTheme.bodySmall),
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
    // A refused track (seen on the Bravia: "Could not open codec") does not
    // stop a video that plays: only an error before it starts is shown.
    final error = _started ? null : _error;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Focus(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: _onKey,
        child: MouseRegion(
          onHover: touch
              ? null
              : (_) {
                  _keys = false;
                  _showOverlay();
                },
          cursor: _overlay ? SystemMouseCursors.basic : SystemMouseCursors.none,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Video(controller: _video, controls: NoVideoControls),
              // Phone: tap shows the bar, double tap on a side jumps 10 s
              // (like VLC). Windows: click pauses, double click is full screen.
              Row(
                children: [
                  for (final side in [-1, 0, 1])
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          _keys = false;
                          touch ? _toggleOverlay() : _playPause();
                        },
                        onDoubleTap: !touch
                            ? _toggleFullscreen
                            : side == 0
                            ? _playPause
                            : () => _seekBy(side < 0 ? -_step : _step),
                      ),
                    ),
                ],
              ),
              if (_buffering && error == null) const Center(child: CircularProgressIndicator()),
              if (error != null)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      tr('No se pudo reproducir: {0}', [error]),
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
    const white = TextStyle(color: Colors.white);
    final actions = _actions(touch);
    final now = DateTime.now();
    final (on, next) = nowAndNext(_guide, now);
    String hm(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    final lineSelected = _keys && _sel < 0;
    // Big screens (TV) get a margin so nothing falls off the edge (overscan).
    final edge = runningOnTv ? const EdgeInsets.symmetric(horizontal: 48, vertical: 24) : EdgeInsets.zero;
    return Padding(
      padding: edge,
      child: Column(
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
                ExcludeFocus(
                  child: IconButton(
                    color: Colors.white,
                    icon: const Icon(Icons.arrow_back),
                    tooltip: tr('Salir'),
                    onPressed: close,
                  ),
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
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (on != null) ...[
                  Text(
                    tr('Ahora: {0}', [on.title]),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: white.copyWith(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: LinearProgressIndicator(
                      value:
                          now.difference(on.start).inSeconds / on.end.difference(on.start).inSeconds.clamp(1, 1 << 30),
                    ),
                  ),
                  Text('${hm(on.start)} – ${hm(on.end)}', style: white.copyWith(color: Colors.white70)),
                ],
                if (next != null)
                  Text(
                    tr('Después, {0}: {1}', [hm(next.start), next.title]),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: white.copyWith(color: Colors.white70),
                  ),
                if (!_live)
                  Row(
                    children: [
                      Text(formatClock(_pos), style: white),
                      Expanded(
                        child: ExcludeFocus(
                          child: SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              trackHeight: lineSelected ? 6 : 3,
                              thumbShape: RoundSliderThumbShape(enabledThumbRadius: lineSelected ? 10 : 7),
                              thumbColor: lineSelected ? Colors.white : null,
                            ),
                            child: Slider(
                              value: _pos.inMilliseconds.clamp(0, _len.inMilliseconds).toDouble(),
                              max: _len.inMilliseconds.toDouble(),
                              onChanged: (v) {
                                _player.seek(Duration(milliseconds: v.round()));
                                _showOverlay();
                              },
                            ),
                          ),
                        ),
                      ),
                      Text(formatClock(_len), style: white),
                    ],
                  ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (final (i, a) in actions.indexed)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: _Btn(action: a, selected: _keys && _sel == i),
                      ),
                  ],
                ),
                if (!touch || runningOnTv)
                  Center(
                    child: Text(
                      _live
                          ? tr('◀ ▶: elegir · OK: usar · Atrás: ocultar')
                          : tr('▲: línea de tiempo · ◀ ▶: elegir o mover 10 s · OK: usar · Atrás: ocultar'),
                      style: white.copyWith(fontSize: 12, color: Colors.white70),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
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

/// Not focusable: on a TV the remote's keys go straight to the player, which
/// draws the highlight itself.
class _Btn extends StatelessWidget {
  const _Btn({required this.action, required this.selected});
  final _Action action;
  final bool selected;

  @override
  Widget build(BuildContext context) => ExcludeFocus(
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 100),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? Colors.white24 : Colors.transparent,
        border: Border.all(color: selected ? Colors.white : Colors.transparent, width: 2),
      ),
      child: IconButton(
        color: Colors.white,
        iconSize: action.size,
        tooltip: action.tip,
        icon: Icon(action.icon),
        onPressed: action.onTap,
      ),
    ),
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
