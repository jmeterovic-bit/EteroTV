import 'dart:convert';
import 'dart:io';

import 'package:eterotv/iptv/xtream.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('server URL is reduced to its origin', () {
    expect(Credentials.normalizeServer('example.com:8080/'), 'http://example.com:8080');
    expect(
      Credentials.normalizeServer(' https://tv.example.com/get.php?username=a&password=b '),
      'https://tv.example.com',
    );
    expect(Credentials.normalizeServer('http://1.2.3.4:25461'), 'http://1.2.3.4:25461');
  });

  test('numbers come as strings or ints', () {
    expect(asInt('2'), 2);
    expect(asInt(3), 3);
    expect(asInt('4.0'), 4);
    expect(asInt(null), 0);
  });

  test('durations', () {
    expect(parseDuration('5400', null), 5400);
    expect(parseDuration(null, '01:45:30'), 6330);
    expect(parseDuration(0, '45:10'), 2710);
    expect(parseDuration(null, '105 min'), 6300);
    expect(parseDuration(null, ''), 0);
  });

  test('account info and connection limit', () async {
    final mock = MockClient((req) async {
      expect(req.url.path, '/player_api.php');
      expect(req.url.queryParameters['username'], 'jose');
      return http.Response(
        jsonEncode({
          'user_info': {
            'auth': 1,
            'status': 'Active',
            'exp_date': '1893456000',
            'max_connections': '2',
            'active_cons': '2',
          },
        }),
        200,
      );
    });
    final x = XtreamClient(
      Credentials(server: 'tv.example.com:8080', username: 'jose', password: 'p w'),
      client: mock,
    );
    final a = await x.account();
    expect(a.maxConnections, 2);
    expect(a.full, isTrue);
    expect(a.expires!.year, 2030);
  });

  test('wrong password is reported', () async {
    final mock = MockClient(
      (_) async => http.Response(
        jsonEncode({
          'user_info': {'auth': 0},
        }),
        200,
      ),
    );
    final x = XtreamClient(
      Credentials(server: 'x', username: 'a', password: 'b'),
      client: mock,
    );
    expect(x.account(), throwsA(isA<XtreamException>()));
  });

  test('stream URLs escape user and password', () {
    final x = XtreamClient(Credentials(server: 'http://h:8080', username: 'jo se', password: 'a/b'));
    expect(x.liveUrl('7'), 'http://h:8080/live/jo%20se/a%2Fb/7.ts');
    expect(x.movieUrl('9', 'mkv'), 'http://h:8080/movie/jo%20se/a%2Fb/9.mkv');
    expect(x.episodeUrl('11', ''), 'http://h:8080/series/jo%20se/a%2Fb/11.mp4');
  });

  test('parse lists', () {
    final live = parseItems(Kind.live, [
      {
        'num': 1,
        'name': 'Canal 1 HD',
        'stream_id': 101,
        'stream_icon': 'http://i/1.png',
        'epg_channel_id': 'c1.es',
        'category_id': '5',
      },
      {'name': 'no id'},
    ]);
    expect(live, hasLength(1));
    expect(live.first.id, '101');
    expect(live.first.epgId, 'c1.es');

    final series = parseItems(Kind.series, [
      {
        'series_id': '33',
        'name': 'Serie',
        'cover': 'http://c',
        'releaseDate': '2019-05-01',
        'category_id': 2,
        'tmdb': '1399',
      },
    ]);
    expect(series.first.id, '33');
    expect(series.first.year, '2019');
    expect(series.first.tmdbId, '1399');
    expect(series.first.categoryId, '2');
  });

  test('parse series info: episodes by season, sorted', () {
    final info = parseSeriesInfo({
      'info': {'plot': 'Trama'},
      'episodes': {
        '1': [
          {
            'id': '2',
            'episode_num': 2,
            'title': 'B',
            'season': 1,
            'container_extension': 'mkv',
            'info': {'duration_secs': 2700},
          },
          {
            'id': '1',
            'episode_num': '1',
            'title': 'A',
            'season': '1',
            'container_extension': 'mkv',
            'info': {'duration': '00:44:00'},
          },
        ],
        '2': [
          {'id': '3', 'episode_num': 1, 'title': 'C', 'season': 2, 'info': []},
        ],
      },
    });
    expect(info.plot, 'Trama');
    expect(info.seasons[1]!.map((e) => e.id), ['1', '2']);
    expect(info.seasons[1]!.first.durationSecs, 2640);
    expect(info.seasons[2]!.single.durationSecs, 0);
  });

  test('parse movie info', () {
    final m = parseMovieInfo({
      'info': {'duration_secs': '6000', 'plot': 'x', 'tmdb_id': 12},
    });
    expect(m.durationSecs, 6000);
    expect(m.tmdbId, '12');
    expect(parseMovieInfo([]).durationSecs, 0);
  });

  test('https on a plain-http port is reported clearly', () async {
    final mock = MockClient(
      (_) async => throw const HandshakeException(
        'Handshake error in client (OS Error: WRONG_VERSION_NUMBER(tls_record.cc:127))',
      ),
    );
    final x = XtreamClient(
      Credentials(server: 'https://h:2052', username: 'a', password: 'b'),
      client: mock,
    );
    await expectLater(
      x.account(),
      throwsA(
        isA<XtreamException>()
            .having((e) => e.tlsMismatch, 'tlsMismatch', isTrue)
            .having((e) => e.message, 'message', contains('http://')),
      ),
    );
    expect(x.creds.withHttp().server, 'http://h:2052');
  });

  test('guide: titles in base64, now and next', () {
    String b(String t) => base64.encode(utf8.encode(t));
    final epg = parseShortEpg({
      'epg_listings': [
        {
          'title': b('Noticias'),
          'description': b('Edición nocturna'),
          'start_timestamp': '2000',
          'stop_timestamp': '3000',
        },
        {'title': b('Película'), 'start_timestamp': '1000', 'stop_timestamp': '2000'},
        {'title': 'sin fecha'},
      ],
    });
    expect(epg.map((e) => e.title), ['Película', 'Noticias']);
    expect(epg[1].description, 'Edición nocturna');
    final (on, next) = nowAndNext(epg, DateTime.fromMillisecondsSinceEpoch(1500 * 1000));
    expect(on?.title, 'Película');
    expect(next?.title, 'Noticias');
    final (on2, next2) = nowAndNext(epg, DateTime.fromMillisecondsSinceEpoch(500 * 1000));
    expect(on2, isNull);
    expect(next2?.title, 'Película');
    expect(parseShortEpg([]), isEmpty);
  });
}
