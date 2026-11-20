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

  test('a live channel that stops is opened again a few times, waiting longer each time', () {
    final waits = [for (var i = 0; i < liveRetries; i++) liveRetryDelay(i)!];
    for (var i = 1; i < waits.length; i++) {
      expect(waits[i] >= waits[i - 1], isTrue);
    }
    expect(liveRetryDelay(liveRetries), isNull);
  });

  test('live channels keep little behind and let ffmpeg reconnect', () {
    expect(mpvLiveOptions['stream-lavf-o'], contains('reconnect_streamed=1'));
    expect(int.parse(mpvLiveOptions['demuxer-max-back-bytes']!), lessThanOrEqualTo(8 << 20));
  });

  test('subtitle sizes are read back, and grow in order', () {
    for (final z in SubSize.values) {
      expect(SubSize.fromName(z.name), z);
    }
    expect(SubSize.fromName(null), SubSize.normal);
    expect(SubSize.normal.configuration.style.fontSize, 32);
    for (var i = 1; i < SubSize.values.length; i++) {
      expect(SubSize.values[i].scale > SubSize.values[i - 1].scale, isTrue);
    }
  });

  test('sound delay: steps of 50 ms up to ±5 s, in seconds for mpv, shown with a sign', () {
    expect(clampAudioDelay(130), 150);
    expect(clampAudioDelay(-9000), -5000);
    expect(mpvAudioDelay(-250), '-0.250');
    expect(formatAudioDelay(0), '0 s');
    expect(formatAudioDelay(250), '+0,25 s');
    expect(formatAudioDelay(-1500), '−1,5 s');
    expect(formatAudioDelay(1000), '+1 s');
  });

  test('subtitles in a small window follow its height, so they can still be read', () {
    expect(32 * compactSubScale(270), closeTo(270 * 0.055, 0.01));
    expect(compactSubScale(2000), 1.0, reason: 'never bigger than normal');
    expect(compactSubScale(10), 0.2);
  });
}
