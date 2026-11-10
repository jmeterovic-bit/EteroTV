import 'package:eterotv/player/own_player.dart';
import 'package:eterotv/player/vlc.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the player saved on a device is read back, and anything else is VLC', () {
    for (final p in AndroidPlayer.values) {
      expect(AndroidPlayer.fromName(p.name), p);
    }
    expect(AndroidPlayer.fromName(null), AndroidPlayer.vlc);
    expect(AndroidPlayer.fromName('otro'), AndroidPlayer.vlc);
  });

  test('messages name the chosen player', () {
    final a = AndroidVlc();
    expect(a.name, 'VLC');
    a.player = AndroidPlayer.just;
    expect(a.name, 'Just Player');
    expect(VlcMissing(a.name).toString(), 'Just Player no está instalado');
  });

  test('VLC on Windows gets the languages chosen', () {
    expect(vlcTrackArgs(TrackLang.original, TrackLang.none), ['--sub-language=none']);
    expect(vlcTrackArgs(TrackLang.es, TrackLang.en), ['--audio-language=es,spa', '--sub-language=en,eng']);
    expect(vlcTrackArgs(TrackLang.fr, TrackLang.fr), ['--audio-language=fr,fra,fre', '--sub-language=fr,fra,fre']);
    expect(TrackLang.fromName('nada', TrackLang.original), TrackLang.original);
  });

  test('the own player asks mpv for the languages and never for forced subtitles alone', () {
    expect(mpvTrackOptions(TrackLang.original, TrackLang.none), {'sid': 'no', 'subs-fallback-forced': 'no'});
    expect(mpvTrackOptions(TrackLang.es, TrackLang.en), {
      'alang': 'es,spa',
      'slang': 'en,eng',
      'sid': 'auto',
      'subs-fallback-forced': 'no',
    });
  });

  test('player errors never show the stream address', () {
    expect(hideUrls('Failed to open http://srv:8080/movie/u/secreta/1.mkv.'), 'Failed to open …');
  });

  test('clock', () {
    expect(formatClock(const Duration(seconds: 65)), '1:05');
    expect(formatClock(const Duration(hours: 1, minutes: 2, seconds: 3)), '1:02:03');
  });
}
