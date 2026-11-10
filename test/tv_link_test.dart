import 'dart:convert';

import 'package:eterotv/sync/google_auth.dart';
import 'package:eterotv/sync/tv_link.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _MemStore implements TokenStore {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String v) async => value = v;
  @override
  Future<void> delete() async => value = null;
}

void main() {
  test('the phone finds the TV and passes the session with the right code', () async {
    Map<String, dynamic>? received;
    final tv = TvLinkServer(name: 'Bravia sala', port: 0, onSession: (s) async => received = s);
    await tv.start();
    addTearDown(tv.close);

    final found = await TvLinkClient.find(hosts: ['127.0.0.1'], port: tv.boundPort);
    expect(found, hasLength(1));
    expect(found.single.name, 'Bravia sala');

    final wrong = tv.code == '000000' ? '111111' : '000000';
    await expectLater(
      TvLinkClient.send(found.single, wrong, {'refresh_token': 'r1'}),
      throwsA(isA<TvLinkException>().having((e) => e.message, 'message', contains('no coincide'))),
    );
    expect(received, isNull);

    await TvLinkClient.send(found.single, tv.code, {'refresh_token': 'r1', 'client': 'desktop'});
    await tv.done;
    expect(received, {'refresh_token': 'r1', 'client': 'desktop'});
  });

  test('too many wrong codes stop the TV from listening', () async {
    final tv = TvLinkServer(name: 'TV', port: 0, onSession: (_) async {});
    await tv.start();
    final doneError = expectLater(tv.done, throwsA(isA<TvLinkException>()));
    final found = (await TvLinkClient.find(hosts: ['127.0.0.1'], port: tv.boundPort)).single;
    final wrong = tv.code == '000000' ? '111111' : '000000';
    for (var i = 0; i < TvLinkServer.maxFailures; i++) {
      await expectLater(TvLinkClient.send(found, wrong, {}), throwsA(isA<TvLinkException>()));
    }
    await doneError;
  });

  test('the TV keeps the session only if Google accepts it', () async {
    var accept = false;
    final client = MockClient((req) async {
      expect(req.url.toString(), 'https://oauth2.googleapis.com/token');
      return accept
          ? http.Response(jsonEncode({'access_token': 'a', 'expires_in': 3600}), 200)
          : http.Response(jsonEncode({'error': 'invalid_grant'}), 400);
    });
    final store = _MemStore();
    final auth = GoogleAuth(store: store, client: client);

    await expectLater(auth.adoptSession({'refresh_token': 'bad'}), throwsA(isA<GoogleAuthException>()));
    expect(store.value, isNull);

    accept = true;
    await auth.adoptSession({'refresh_token': 'good', 'client': 'desktop'});
    expect(auth.signedIn, isTrue);
    expect(jsonDecode(store.value!), {'refresh_token': 'good', 'client': 'desktop'});
    expect(auth.exportSession(), {'refresh_token': 'good', 'client': 'desktop'});
  });
}
