import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../ui/i18n.dart';

/// Where the user stopped. Null fields mean VLC did not tell us.
class PlayResult {
  PlayResult({this.positionSecs, this.durationSecs, this.info = ''});
  final int? positionSecs;
  final int? durationSecs;

  /// Android: how VLC answered (launch type, result code, extra names), to
  /// explain a missing position. Never contains the URL.
  final String info;
}

class VlcMissing implements Exception {
  VlcMissing([this.player = 'VLC']);
  final String player;
  @override
  String toString() => tr('{0} no está instalado', [player]);
}

/// The player used on Android. VLC everywhere, except on a device where VLC
/// does not work (Jose's Sony Bravia, 2026-11-10: VLC hangs on any video
/// there, even its own test). Just Player and MX Player hand back the
/// position like VLC (the "MX Player" interface). Saved per device, not synced.
enum AndroidPlayer {
  vlc('VLC'),
  just('Just Player'),
  mx('MX Player');

  const AndroidPlayer(this.label);
  final String label;

  static AndroidPlayer fromName(String? n) => values.firstWhere((p) => p.name == n, orElse: () => vlc);
}

/// The language to ask for in a video's audio or subtitles. [original]
/// (audio) and [none] (subtitles) leave it to the video.
enum TrackLang {
  original,
  none,
  es,
  en,
  fr;

  static TrackLang fromName(String? n, TrackLang fallback) =>
      values.firstWhere((l) => l.name == n, orElse: () => fallback);

  /// The codes VLC matches against the tracks (two and three letters).
  String? get vlcCodes => switch (this) {
    es => 'es,spa',
    en => 'en,eng',
    fr => 'fr,fra,fre',
    _ => null,
  };
}

/// VLC's options for the languages chosen. Without a track in that
/// language, VLC plays the video's own one (the default track).
List<String> vlcTrackArgs(TrackLang audio, TrackLang subs) => [
  if (audio.vlcCodes case final c?) '--audio-language=$c',
  if (subs.vlcCodes case final c?) '--sub-language=$c' else if (subs == TrackLang.none) '--sub-language=none',
];

/// Opens a video in VLC (the app has no player of its own) and finds out
/// where the user stopped.
abstract class VlcLauncher {
  /// Ajustes → Idioma (this device). Only VLC on Windows takes them from us:
  /// the Android players have their own setting.
  TrackLang audioLang = TrackLang.original;
  TrackLang subLang = TrackLang.none;

  static VlcLauncher forPlatform() => Platform.isAndroid ? AndroidVlc() : DesktopVlc();

  /// The player's name, for messages.
  String get name => 'VLC';

  Future<bool> available();

  /// Completes when the user leaves VLC. [onProgress] gets (position,
  /// length) in seconds while playing, where the player can tell (Windows).
  Future<PlayResult?> play(
    String url, {
    required String title,
    int startSecs = 0,
    void Function(int positionSecs, int lengthSecs)? onProgress,
  });

  /// Closes the player opened by [play], where possible (Windows).
  Future<void> stop() async {}
}

/// Android, Google TV and Fire TV: VLC returns the position itself
/// (see MainActivity.kt).
class AndroidVlc extends VlcLauncher {
  static const _ch = MethodChannel('eterotv/vlc');

  /// Set from Ajustes → Reproductor (this device only).
  AndroidPlayer player = AndroidPlayer.vlc;

  @override
  String get name => player.label;

  /// Only a hint: if Android says no, VLC is still tried when playing and
  /// the "VLC missing" message only shows if that launch fails.
  @override
  Future<bool> available() async => true;

  Future<bool> looksInstalled() async => await _ch.invokeMethod<bool>('isInstalled') ?? true;

  @override
  Future<PlayResult?> play(
    String url, {
    required String title,
    int startSecs = 0,
    void Function(int positionSecs, int lengthSecs)? onProgress,
  }) async {
    try {
      final r = await _ch.invokeMapMethod<String, Object?>('play', {
        'url': url,
        'title': title,
        'positionMs': startSecs * 1000,
        'player': player.name,
      });
      if (r == null) return null;
      final pos = (r['positionMs'] as num?)?.toInt() ?? -1;
      final dur = (r['durationMs'] as num?)?.toInt() ?? -1;
      return PlayResult(
        positionSecs: pos >= 0 ? pos ~/ 1000 : null,
        durationSecs: dur > 0 ? dur ~/ 1000 : null,
        info: (r['info'] as String?) ?? '',
      );
    } on PlatformException catch (e) {
      if (e.code == 'no_vlc') throw VlcMissing(name);
      rethrow;
    }
  }
}

/// Windows (and Linux for development). VLC desktop returns nothing when it
/// closes, so it is started with its web interface on 127.0.0.1 and a random
/// password, and the app asks it every few seconds where it is.
class DesktopVlc extends VlcLauncher {
  DesktopVlc({this.customPath});
  final String? customPath;

  static const pollEvery = Duration(seconds: 5);

  String? findExe() {
    if (customPath != null && File(customPath!).existsSync()) return customPath;
    if (Platform.isWindows) {
      final env = Platform.environment;
      for (final base in [env['ProgramFiles'], env['ProgramFiles(x86)'], env['ProgramW6432']]) {
        if (base == null) continue;
        final p = '$base\\VideoLAN\\VLC\\vlc.exe';
        if (File(p).existsSync()) return p;
      }
      return null;
    }
    for (final p in ['/usr/bin/vlc', '/snap/bin/vlc', '/usr/local/bin/vlc']) {
      if (File(p).existsSync()) return p;
    }
    return null;
  }

  @override
  Future<bool> available() async => findExe() != null;

  Process? _proc;

  @override
  Future<void> stop() async {
    _proc?.kill();
  }

  @override
  Future<PlayResult?> play(
    String url, {
    required String title,
    int startSecs = 0,
    void Function(int positionSecs, int lengthSecs)? onProgress,
  }) async {
    final exe = findExe();
    if (exe == null) throw VlcMissing();
    final port = await _freePort();
    final password = _randomPassword();
    final proc = await Process.start(exe, [
      '--no-one-instance', // our own window, so its web interface is ours
      '--extraintf=http',
      '--http-host=127.0.0.1',
      '--http-port=$port',
      '--http-password=$password',
      '--no-qt-recentplay', // the URL carries the IPTV password: keep it out of "Recent"
      '--no-qt-privacy-ask',
      if (startSecs > 0) '--start-time=$startSecs',
      ...vlcTrackArgs(audioLang, subLang),
      '--meta-title=$title',
      url,
    ]);
    _proc = proc;
    // Do not let VLC block on full pipes.
    proc.stdout.drain<void>();
    proc.stderr.drain<void>();

    final tracker = VlcStatusTracker();
    final client = http.Client();
    final auth = 'Basic ${base64Encode(utf8.encode(':$password'))}';
    final status = Uri.parse('http://127.0.0.1:$port/requests/status.json');
    var exited = false;
    final exit = proc.exitCode.then((_) => exited = true);
    while (!exited) {
      await Future.any([exit, Future<void>.delayed(pollEvery)]);
      if (exited) break;
      try {
        final r = await client.get(status, headers: {'Authorization': auth}).timeout(const Duration(seconds: 3));
        if (r.statusCode == 200) {
          tracker.add(jsonDecode(r.body) as Map<String, dynamic>);
          final t = tracker.result();
          if (onProgress != null && t?.positionSecs != null && (t?.durationSecs ?? 0) > 0) {
            onProgress(t!.positionSecs!, t.durationSecs!);
          }
        }
      } catch (_) {
        // VLC still starting, or closing: try again next round.
      }
    }
    client.close();
    if (identical(_proc, proc)) _proc = null;
    return tracker.result();
  }

  static Future<int> _freePort() async {
    final s = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final p = s.port;
    await s.close();
    return p;
  }

  static String _randomPassword() {
    final r = Random.secure();
    return List.generate(24, (_) => r.nextInt(36).toRadixString(36)).join();
  }
}

/// Turns the status samples from VLC's web interface into a final position.
/// Kept separate so it can be tested.
class VlcStatusTracker {
  int? _time;
  int? _length;

  void add(Map<String, dynamic> s) {
    final state = s['state']?.toString() ?? '';
    final time = (s['time'] as num?)?.toInt() ?? 0;
    final length = (s['length'] as num?)?.toInt() ?? 0;
    if (length > 0) _length = length;
    if (state == 'stopped' && time == 0) {
      // Reached the end (VLC resets to 0): keep "at the end" if we were near it.
      if (_time != null && _length != null && _length! - _time! <= pollSlackSecs) _time = _length;
      return;
    }
    if (time > 0) _time = time;
  }

  /// A poll every 5 s can miss the last seconds before the end.
  static const pollSlackSecs = 15;

  PlayResult? result() =>
      _time == null && _length == null ? null : PlayResult(positionSecs: _time, durationSecs: _length);
}
