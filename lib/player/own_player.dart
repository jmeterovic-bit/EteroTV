import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../iptv/xtream.dart';
import '../platform/device.dart';
import '../platform/pip.dart';
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

/// How big the subtitles are (Ajustes → Reproductor, or «Audio y
/// subtítulos» while watching; per device, since each screen is seen from
/// its own distance).
enum SubSize {
  small(0.75),
  normal(1.0),
  large(1.3),
  huge(1.6);

  const SubSize(this.scale);
  final double scale;

  static SubSize fromName(String? n) => values.firstWhere((d) => d.name == n, orElse: () => normal);

  /// media_kit draws the subtitles itself: its normal style, scaled.
  SubtitleViewConfiguration get configuration => SubtitleViewConfiguration(
    style: TextStyle(
      height: 1.4,
      fontSize: 32 * scale,
      color: const Color(0xffffffff),
      backgroundColor: const Color(0xaa000000),
    ),
  );
}

/// Live channels: what to do when the stream stops. The server sometimes
/// drops the connection (seen on the Fire TV after ~40 min, 2026-11-13):
/// mpv then reached the end of the stream and the player closed, back to
/// the list. Now it opens the channel again, waiting a bit longer each time.
/// Null: give up (the signal is gone).
Duration? liveRetryDelay(int attempt) =>
    attempt >= liveRetries ? null : Duration(seconds: [1, 2, 3, 5, 8, 10][attempt]);
const liveRetries = 6;

/// A live channel whose time has not moved for this long while not paused
/// is stuck: it is opened again.
const liveStall = Duration(seconds: 20);

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
  SubSize subSize = SubSize.normal;

  /// The size chosen while watching, to keep it for the next video.
  void Function(SubSize)? onSubSize;

  /// Sound delay for every video on this device, in ms (2.3.0).
  int audioDelayMs = 0;

  /// The general delay changed while watching, to keep it.
  void Function(int)? onAudioDelay;

  /// For the next live channel: its guide, shown over the video.
  Future<List<EpgEntry>> Function()? nextEpg;

  /// For the next live channel: told whether it opened (2.2.0, to mark
  /// channels that do not work).
  void Function(bool ok)? nextHealth;

  /// A video is on screen.
  bool get isOpen => _close != null;

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
    final health = nextHealth;
    nextEpg = null;
    nextHealth = null;
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
            subSize: subSize,
            onSubSize: (z) {
              subSize = z;
              onSubSize?.call(z);
            },
            audioDelayMs: audioDelayMs,
            onAudioDelay: (ms) {
              audioDelayMs = ms;
              onAudioDelay?.call(ms);
            },
            epg: epg,
            onHealth: health,
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
    this.subSize = SubSize.normal,
    this.onSubSize,
    this.audioDelayMs = 0,
    this.onAudioDelay,
    this.epg,
    this.onHealth,
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
  final SubSize subSize;
  final void Function(SubSize)? onSubSize;

  /// Sound delay for every video on this device (ms), and where a change goes.
  final int audioDelayMs;
  final void Function(int)? onAudioDelay;

  /// Live channels: loads the guide shown in the bar.
  final Future<List<EpgEntry>> Function()? epg;

  /// Live channels: whether it opened (once: it played, or it never started).
  final void Function(bool ok)? onHealth;
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

  /// A live channel (not a video still loading its length).
  bool get _channel => widget.epg != null;

  late SubSize _subSize = widget.subSize;

  /// Sound delay (ms): for every video on this device, and only for this
  /// one (2.3.0, Jose: «general» and «local»). mpv plays the sum.
  late int _generalDelay = widget.audioDelayMs;
  int _localDelay = 0;

  Future<void> _applyDelay() async {
    final native = _player.platform;
    if (native is! NativePlayer) return;
    try {
      await native.setProperty('audio-delay', mpvAudioDelay(_generalDelay + _localDelay));
    } catch (_) {}
  }

  /// Picture in picture: allowed only while the video plays (Android).
  void _updatePip() {
    final w = _player.state.width ?? 0;
    final h = _player.state.height ?? 0;
    unawaited(Pip.allow(_playing && !_closing, width: w > 0 ? w : 16, height: h > 0 ? h : 9));
  }

  void _onPip() {
    if (!mounted) return;
    if (Pip.active.value) {
      _hideTimer?.cancel();
      _overlay = false;
      _flash = null;
    }
    setState(() {});
  }

  /// Live channels: the stream is being opened again.
  bool _reconnecting = false;
  int _retries = 0;

  /// Where the channel's time was when it last moved, and when.
  Duration _lastMoved = Duration.zero;
  DateTime _lastMovedAt = DateTime.now();
  DateTime _reconnectedAt = DateTime.now();
  Timer? _stallTimer;
  Timer? _openTimer;
  bool _signalLost = false;

  /// Whether the channel opened, told once (2.2.0).
  bool _healthTold = false;
  void _health(bool ok) {
    if (_healthTold || !_channel) return;
    _healthTold = true;
    _openTimer?.cancel();
    widget.onHealth?.call(ok);
  }

  @override
  void initState() {
    super.initState();
    widget.onOpen?.call(close);
    enterTvFullScreen();
    _subs
      ..add(
        _player.stream.position.listen((p) {
          if (_seekTarget == null) _pos = p;
          if (p > Duration.zero && !_started) {
            _started = true;
            _health(true);
          }
          if (p != _lastMoved) {
            _lastMoved = p;
            _lastMovedAt = DateTime.now();
            // Playing again for a minute: the next drop starts counting anew.
            if (_retries > 0 &&
                !_reconnecting &&
                _lastMovedAt.difference(_reconnectedAt) > const Duration(minutes: 1)) {
              _retries = 0;
            }
          }
          final s = p.inSeconds;
          if (s != _lastReport && _len > Duration.zero) {
            _lastReport = s;
            widget.onProgress?.call(s, _len.inSeconds);
          }
          if (mounted && (_overlay || _error != null)) setState(() {});
        }),
      )
      ..add(_player.stream.duration.listen((d) => setState(() => _len = d)))
      ..add(
        _player.stream.playing.listen((v) {
          setState(() => _playing = v);
          _updatePip();
        }),
      )
      ..add(_player.stream.width.listen((_) => _updatePip()))
      ..add(_player.stream.buffering.listen((v) => setState(() => _buffering = v)))
      ..add(
        _player.stream.error.listen((e) {
          // Not a failure yet: a track the chip refuses («Could not open
          // codec») can come before the video starts anyway (2.2.1).
          setState(() => _error = hideUrls(e));
        }),
      )
      ..add(
        _player.stream.completed.listen((v) {
          if (!v || _ended) return;
          // A channel that played and stopped: open it again. One that never
          // started closes as before (its error showed).
          if (_channel && _started) {
            _reconnect();
          } else {
            _ended = true;
            close();
          }
        }),
      );
    Pip.onClosed = close;
    Pip.active.addListener(_onPip);
    _start();
    _showOverlay();
    _loadGuide();
    if (_channel) {
      // A channel that shows nothing in 20 s counts as not working.
      _openTimer = Timer(const Duration(seconds: 20), () {
        if (!_started && !_closing) _health(false);
      });
      _stallTimer = Timer.periodic(const Duration(seconds: 5), (_) {
        if (_closing || _reconnecting || _signalLost || !_started) return;
        if (_player.state.playing && DateTime.now().difference(_lastMovedAt) > liveStall) _reconnect();
      });
    }
    if (Platform.isAndroid) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
  }

  Future<void> _start() async {
    final native = _player.platform;
    if (native is NativePlayer) {
      final options = {...mpvTrackOptions(widget.audio, widget.subs), if (_channel) ...mpvLiveOptions};
      for (final o in options.entries) {
        await native.setProperty(o.key, o.value);
      }
      await _applyDelay();
    }
    await _player.open(Media(widget.url, start: Duration(seconds: widget.startSecs)));
  }

  /// Live channel: the stream stopped (or got stuck). Opens it again, with
  /// "Reconectando…" over the video, instead of going back to the list.
  Future<void> _reconnect() async {
    if (_closing || _reconnecting || _signalLost) return;
    final wait = liveRetryDelay(_retries);
    if (wait == null) {
      setState(() => _signalLost = true);
      _health(false);
      return;
    }
    _retries++;
    setState(() => _reconnecting = true);
    await Future<void>.delayed(wait);
    if (_closing || !mounted) return;
    try {
      _error = null;
      _lastMovedAt = DateTime.now();
      await _player.open(Media(widget.url));
    } catch (_) {
      // The next check (end of stream or stuck) tries again.
    }
    if (!mounted) return;
    _lastMovedAt = _reconnectedAt = DateTime.now();
    setState(() => _reconnecting = false);
  }

  Future<void> _loadGuide() async {
    final load = widget.epg;
    if (load == null) return;
    final g = await load();
    if (!mounted) return;
    setState(() => _guide = g);
    // Refresh the "now" line and its bar; when the programme ends, ask the
    // guide again (it holds only a few programmes).
    var ticks = 0;
    _guideTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
      if (!mounted) return;
      ticks++;
      final (on, next) = nowAndNext(_guide, DateTime.now());
      if ((on == null || next == null) && ticks % 4 == 0) {
        final g = await load();
        if (mounted) _guide = g;
      }
      if (mounted && _overlay) setState(() {});
    });
  }

  bool _closing = false;

  /// Leaves the player (Back, Esc, end of the video, or the next episode).
  void close() {
    if (_closing || !mounted) return;
    // Left before it started, with an error on screen: it did not work.
    if (!_started && _error != null) _health(false);
    _closing = true;
    _seekTarget = null;
    _updatePip();
    // The next-episode card may be over the player: take out the player's
    // own screen, not whatever is on top (a plain pop closed the card).
    final route = ModalRoute.of(context);
    final nav = Navigator.of(context);
    if (route != null && !route.isCurrent) {
      nav.removeRoute(route);
    } else {
      nav.pop();
    }
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
    _stallTimer?.cancel();
    _openTimer?.cancel();
    _focus.dispose();
    Pip.active.removeListener(_onPip);
    if (Pip.onClosed == close) Pip.onClosed = null;
    unawaited(Pip.allow(false));
    unawaited(_release(_player));
    leaveTvFullScreen();
    if (Platform.isAndroid) SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  /// Lets go of the player without hanging the app. The video surface is
  /// taken from mpv first (vid=no, vo=null): media_kit releases it on the
  /// main thread while mpv could still be drawing on it, and on the Fire TV
  /// that froze the app when leaving a video.
  static Future<void> _release(Player player) async {
    try {
      final native = player.platform;
      if (native is NativePlayer) {
        await native.setProperty('pause', 'yes').timeout(_releaseWait);
        await native.setProperty('vid', 'no').timeout(_releaseWait);
        await native.setProperty('vo', 'null').timeout(_releaseWait);
      }
    } catch (_) {
      // Still free it below.
    }
    try {
      await player.dispose();
    } catch (_) {}
  }

  static const _releaseWait = Duration(seconds: 2);

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

  /// Where a seek in progress is going. While one runs, more presses only
  /// move this target: a burst of ◀ (held on the remote) used to queue one
  /// mpv seek per press, and on the Fire TV each one reopened the stream,
  /// so the video froze and closing waited behind all of them.
  Duration? _seekTarget;
  bool _seeking = false;

  void _seekTo(Duration t) {
    if (_closing) return;
    _seekTarget = t;
    _pos = t;
    if (_seeking) return;
    _seeking = true;
    unawaited(_runSeeks());
  }

  Future<void> _runSeeks() async {
    try {
      while (_seekTarget != null && !_closing) {
        final t = _seekTarget!;
        await _player.seek(t);
        if (_seekTarget == t) _seekTarget = null;
      }
    } catch (_) {
      // The player went away (closed while seeking).
    } finally {
      _seekTarget = null;
      _seeking = false;
    }
  }

  void _seekBy(Duration d) {
    if (_live) return;
    var t = (_seekTarget ?? _pos) + d;
    if (t < Duration.zero) t = Duration.zero;
    if (t > _len) t = _len;
    _seekTo(t);
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
    _Action(Icons.settings, tr('Tamaño de los subtítulos'), _chooseSubSize),
    _Action(Icons.av_timer, tr('Sincronizar el audio'), _chooseAudioDelay),
    if (!touch) _Action(Icons.fullscreen, tr('Pantalla completa'), _toggleFullscreen),
  ];

  int get _playIndex => _live ? 0 : 1;

  KeyEventResult _onKey(FocusNode _, KeyEvent e) {
    final k = e.logicalKey;
    // Back acts when it is released: Android goes back on key-up, so a Back
    // handled on key-down closed the player and then the key-up also took
    // the screen behind back to Inicio (Bravia, 2026-11-10).
    if (k == LogicalKeyboardKey.goBack || k == LogicalKeyboardKey.browserBack) {
      if (e is KeyUpEvent) _overlay ? _hideOverlay() : close();
      return KeyEventResult.handled;
    }
    if (e is KeyUpEvent) return KeyEventResult.ignored;
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

  /// Subtitle size, on its own button (Jose, 2026-11-15: in «Audio y
  /// subtítulos» that menu got too crowded).
  Future<void> _chooseSubSize() async {
    _hideTimer?.cancel();
    await showDialog<void>(
      context: context,
      builder: (c) => SimpleDialog(
        title: Text(tr('Tamaño de los subtítulos')),
        children: [
          for (final z in SubSize.values)
            _TrackTile(
              selected: z == _subSize,
              label: subSizeLabel(z),
              onTap: () {
                setState(() => _subSize = z);
                widget.onSubSize?.call(z);
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

  /// Sound ahead of or behind the picture (2.3.0): for every video on this
  /// device, and only for this one. It changes while the dialog is open, so
  /// the effect is seen at once.
  Future<void> _chooseAudioDelay() async {
    _hideTimer?.cancel();
    await showDialog<void>(
      context: context,
      builder: (c) => AudioDelayDialog(
        rows: [
          AudioDelayRow(tr('Solo este video'), () => _localDelay, (ms) {
            _localDelay = ms;
            unawaited(_applyDelay());
          }),
          AudioDelayRow(tr('Todos los videos en este aparato'), () => _generalDelay, (ms) {
            _generalDelay = ms;
            widget.onAudioDelay?.call(ms);
            unawaited(_applyDelay());
          }),
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
    final error = _signalLost
        ? tr('Se perdió la señal del canal. Atrás para volver a la lista.')
        : _started || _reconnecting
        ? null
        : _error;
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
              Video(controller: _video, controls: NoVideoControls, subtitleViewConfiguration: _subSize.configuration),
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
              if ((_buffering || _reconnecting) && error == null) const Center(child: CircularProgressIndicator()),
              if (_reconnecting && !_signalLost)
                Align(
                  alignment: const Alignment(0, 0.3),
                  child: Text(tr('Reconectando…'), style: const TextStyle(color: Colors.white, fontSize: 18)),
                ),
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
              if (_flash != null && !Pip.active.value)
                Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(12)),
                    child: Text(_flash!, style: const TextStyle(color: Colors.white, fontSize: 28)),
                  ),
                ),
              if (_overlay && !Pip.active.value) _bar(touch),
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
    // It goes inside the shaded bands, which reach the edges of the screen
    // (2.3.0: on the TV they stopped 48 dp short of each side, Jose).
    final tv = runningOnTv;
    final side = tv ? 48.0 : 0.0;
    final edge = tv ? 24.0 : 0.0;
    return SizedBox.expand(
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
            padding: EdgeInsets.fromLTRB(8 + side, 16 + edge, 16 + side, 32),
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
            padding: EdgeInsets.fromLTRB(16 + side, 32, 16 + side, 12 + edge),
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
                  Text(
                    '${hm(on.start)} – ${hm(on.end)} · ${tr('quedan {0} min', [on.end.difference(now).inMinutes + 1])}',
                    style: white.copyWith(color: Colors.white70),
                  ),
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
                                _seekTo(Duration(milliseconds: v.round()));
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

/// Live channels: ffmpeg reconnects by itself after a short drop, and only
/// a little is kept behind the current point (a channel cannot go back), so
/// hours of watching do not fill the memory of a small box (Fire TV).
const mpvLiveOptions = {
  'stream-lavf-o': 'reconnect=1,reconnect_streamed=1,reconnect_delay_max=5',
  'demuxer-max-back-bytes': '4194304',
};

/// The sound delay can go from −5 s to +5 s, in steps of 50 ms.
const audioDelayStep = 50;
const audioDelayMax = 5000;

int clampAudioDelay(int ms) => ((ms / audioDelayStep).round() * audioDelayStep).clamp(-audioDelayMax, audioDelayMax);

/// mpv's `audio-delay`, in seconds: positive plays the sound later.
String mpvAudioDelay(int ms) => (ms / 1000).toStringAsFixed(3);

/// «+0,25 s», «−1,5 s», «0 s» (a comma in Spanish and French).
String formatAudioDelay(int ms) {
  if (ms == 0) return '0 s';
  var n = (ms.abs() / 1000).toStringAsFixed(2);
  n = n.replaceFirst(RegExp(r'\.?0+$'), '');
  if (uiLang != UiLang.en) n = n.replaceAll('.', ',');
  return '${ms > 0 ? '+' : '−'}$n s';
}

/// One line of [AudioDelayDialog]: what it changes, and its value.
class AudioDelayRow {
  const AudioDelayRow(this.label, this.value, this.onChanged);
  final String label;
  final int Function() value;
  final void Function(int ms) onChanged;
}

/// − and + move the sound 50 ms (holding OK repeats); «0» puts it back.
/// Used by the player and by Ajustes → Reproductor.
class AudioDelayDialog extends StatefulWidget {
  const AudioDelayDialog({super.key, required this.rows});
  final List<AudioDelayRow> rows;

  @override
  State<AudioDelayDialog> createState() => _AudioDelayDialogState();
}

class _AudioDelayDialogState extends State<AudioDelayDialog> {
  void _set(AudioDelayRow r, int ms) {
    setState(() => r.onChanged(clampAudioDelay(ms)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(tr('Sincronizar el audio')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tr('Si el sonido llega antes que la imagen, usa +. Si llega tarde, usa −.'),
              style: theme.textTheme.bodySmall,
            ),
            for (final (i, r) in widget.rows.indexed) ...[
              const SizedBox(height: 16),
              Text(r.label, style: theme.textTheme.titleSmall),
              Row(
                children: [
                  IconButton.outlined(
                    tooltip: tr('Adelantar el sonido'),
                    icon: const Icon(Icons.remove),
                    onPressed: () => _set(r, r.value() - audioDelayStep),
                  ),
                  SizedBox(
                    width: 96,
                    child: Text(
                      formatAudioDelay(r.value()),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  IconButton.outlined(
                    autofocus: i == 0,
                    tooltip: tr('Atrasar el sonido'),
                    icon: const Icon(Icons.add),
                    onPressed: () => _set(r, r.value() + audioDelayStep),
                  ),
                  const SizedBox(width: 12),
                  TextButton(onPressed: () => _set(r, 0), child: const Text('0')),
                ],
              ),
            ],
          ],
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Listo')))],
    );
  }
}

String subSizeLabel(SubSize z) => switch (z) {
  SubSize.small => tr('Pequeña'),
  SubSize.normal => tr('Normal'),
  SubSize.large => tr('Grande'),
  SubSize.huge => tr('Muy grande'),
};

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
