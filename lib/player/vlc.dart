import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

/// Where the user stopped. Null fields mean VLC did not tell us.
class PlayResult {
  PlayResult({this.positionSecs, this.durationSecs});
  final int? positionSecs;
  final int? durationSecs;
}

class VlcMissing implements Exception {
  @override
  String toString() => 'VLC no está instalado';
}

/// Opens a video in VLC (the app has no player of its own) and finds out
/// where the user stopped.
abstract class VlcLauncher {
  static VlcLauncher forPlatform() =>
      Platform.isAndroid ? AndroidVlc() : DesktopVlc();

  Future<bool> available();

  /// Completes when the user leaves VLC.
  Future<PlayResult?> play(String url, {required String title, int startSecs = 0});
}

/// Android, Google TV and Fire TV: VLC returns the position itself
/// (see MainActivity.kt).
class AndroidVlc extends VlcLauncher {
  static const _ch = MethodChannel('eterotv/vlc');

  @override
  Future<bool> available() async => await _ch.invokeMethod<bool>('isInstalled') ?? false;

  @override
  Future<PlayResult?> play(String url, {required String title, int startSecs = 0}) async {
    try {
      final r = await _ch.invokeMapMethod<String, Object?>(
          'play', {'url': url, 'title': title, 'positionMs': startSecs * 1000});
      if (r == null) return null;
      final pos = (r['positionMs'] as num?)?.toInt() ?? -1;
      final dur = (r['durationMs'] as num?)?.toInt() ?? -1;
      return PlayResult(
        positionSecs: pos >= 0 ? pos ~/ 1000 : null,
        durationSecs: dur > 0 ? dur ~/ 1000 : null,
      );
    } on PlatformException catch (e) {
      if (e.code == 'no_vlc') throw VlcMissing();
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

  @override
  Future<PlayResult?> play(String url, {required String title, int startSecs = 0}) async {
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
      '--meta-title=$title',
      url,
    ]);
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
        final r = await client
            .get(status, headers: {'Authorization': auth})
            .timeout(const Duration(seconds: 3));
        if (r.statusCode == 200) tracker.add(jsonDecode(r.body) as Map<String, dynamic>);
      } catch (_) {
        // VLC still starting, or closing: try again next round.
      }
    }
    client.close();
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
