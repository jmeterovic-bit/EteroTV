import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

import '../ui/i18n.dart';

/// Passing the Google session from a phone or PC to a TV over the home
/// network. Google refuses the hidden Drive folder (drive.appdata) for the
/// TV sign-in with a code ("Invalid device flow scope"), so the TV gets the
/// session from a device that is already connected.
///
/// The TV listens on [tvLinkPort] and shows a 6-digit code. The phone finds
/// it on the local network, and sends the session encrypted with a key that
/// both derive from an X25519 exchange and the code (AES-GCM). A wrong code
/// fails to decrypt; after [TvLinkServer.maxFailures] the TV stops listening.
const tvLinkPort = 47123;
const _helloPath = '/eterotv/hello';
const _linkPath = '/eterotv/link';

final _x25519 = X25519();
final _aes = AesGcm.with256bits();

Future<SecretKey> _key(SimpleKeyPair mine, List<int> theirPub, String code) async {
  final shared = await _x25519.sharedSecretKey(
    keyPair: mine,
    remotePublicKey: SimplePublicKey(theirPub, type: KeyPairType.x25519),
  );
  return Hkdf(
    hmac: Hmac.sha256(),
    outputLength: 32,
  ).deriveKey(secretKey: shared, nonce: utf8.encode('eterotv-link-v1'), info: utf8.encode(code));
}

class TvLinkException implements Exception {
  TvLinkException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// The TV side: waits for one session.
class TvLinkServer {
  TvLinkServer({required this.name, required this.onSession, this.port = tvLinkPort, Random? random})
    : _random = random ?? Random.secure();

  final String name;
  final Future<void> Function(Map<String, dynamic> session) onSession;
  final int port;
  final Random _random;

  static const maxFailures = 5;

  late final String code;
  late SimpleKeyPair _keys;
  HttpServer? _server;
  int _failures = 0;
  final _done = Completer<void>();

  /// The port actually listened on (tests use port 0).
  int get boundPort => _server!.port;

  /// Completes when a session arrived, or fails after too many wrong codes.
  Future<void> get done => _done.future;

  Future<void> start() async {
    code = List.generate(6, (_) => _random.nextInt(10)).join();
    _keys = await _x25519.newKeyPair();
    try {
      _server = await HttpServer.bind(InternetAddress.anyIPv4, port);
    } on SocketException {
      throw TvLinkException(tr('No se pudo esperar la conexión en este televisor (puerto {0} ocupado).', [port]));
    }
    _server!.listen(_handle, onError: (_) {});
  }

  Future<void> close() async => _server?.close(force: true);

  Future<void> _answer(HttpRequest req, int status, Map<String, Object?> body) async {
    req.response
      ..statusCode = status
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(body));
    await req.response.close();
  }

  Future<void> _handle(HttpRequest req) async {
    try {
      if (req.method == 'GET' && req.uri.path == _helloPath) {
        final pub = await _keys.extractPublicKey();
        return await _answer(req, 200, {'app': 'eterotv', 'v': 1, 'name': name, 'pub': base64.encode(pub.bytes)});
      }
      if (req.method != 'POST' || req.uri.path != _linkPath || _done.isCompleted) {
        return await _answer(req, 404, {});
      }
      final m = jsonDecode(await utf8.decoder.bind(req).join()) as Map<String, dynamic>;
      final key = await _key(_keys, base64.decode(m['pub'] as String), code);
      final box = SecretBox(
        base64.decode(m['data'] as String),
        nonce: base64.decode(m['nonce'] as String),
        mac: Mac(base64.decode(m['mac'] as String)),
      );
      List<int> plain;
      try {
        plain = await _aes.decrypt(box, secretKey: key);
      } on SecretBoxAuthenticationError {
        _failures++;
        if (_failures >= maxFailures) {
          await _answer(req, 429, {'error': 'too_many'});
          _done.completeError(TvLinkException(tr('Demasiados códigos incorrectos. Pide un código nuevo.')));
          await close();
          return;
        }
        return await _answer(req, 403, {'error': 'wrong_code'});
      }
      await onSession(jsonDecode(utf8.decode(plain)) as Map<String, dynamic>);
      await _answer(req, 200, {'ok': true});
      if (!_done.isCompleted) _done.complete();
    } catch (e) {
      try {
        await _answer(req, 400, {'error': 'bad_request'});
      } catch (_) {}
    }
  }
}

/// A TV found on the network.
class TvFound {
  TvFound(this.host, this.name, this.pub, {this.port = tvLinkPort});
  final String host;
  final String name;
  final List<int> pub;
  final int port;
}

/// The phone / PC side.
class TvLinkClient {
  static Future<TvFound?> probe(
    String host, {
    int port = tvLinkPort,
    Duration timeout = const Duration(milliseconds: 900),
  }) async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final req = await client.getUrl(Uri(scheme: 'http', host: host, port: port, path: _helloPath)).timeout(timeout);
      final res = await req.close().timeout(timeout);
      if (res.statusCode != 200) return null;
      final m = jsonDecode(await utf8.decoder.bind(res).join().timeout(timeout)) as Map<String, dynamic>;
      if (m['app'] != 'eterotv') return null;
      return TvFound(host, (m['name'] as String?) ?? host, base64.decode(m['pub'] as String), port: port);
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  /// The addresses of this device's home networks (/24), without itself.
  static Future<List<String>> candidates() async {
    final out = <String>[];
    for (final i in await NetworkInterface.list(type: InternetAddressType.IPv4)) {
      for (final a in i.addresses) {
        final p = a.address.split('.');
        if (p.length != 4 || !_private(a.address)) continue;
        for (var n = 1; n < 255; n++) {
          final h = '${p[0]}.${p[1]}.${p[2]}.$n';
          if (h != a.address && !out.contains(h)) out.add(h);
        }
      }
    }
    return out;
  }

  static bool _private(String ip) =>
      ip.startsWith('192.168.') || ip.startsWith('10.') || RegExp(r'^172\.(1[6-9]|2\d|3[01])\.').hasMatch(ip);

  /// Looks for TVs waiting for a session on the home network (a few seconds).
  static Future<List<TvFound>> find({List<String>? hosts, int port = tvLinkPort}) async {
    final all = hosts ?? await candidates();
    final found = await Future.wait(all.map((h) => probe(h, port: port)));
    return found.whereType<TvFound>().toList();
  }

  /// Sends [session] to [tv]. Throws [TvLinkException] when the code is wrong.
  static Future<void> send(TvFound tv, String code, Map<String, dynamic> session) async {
    final mine = await _x25519.newKeyPair();
    final key = await _key(mine, tv.pub, code);
    final box = await _aes.encrypt(utf8.encode(jsonEncode(session)), secretKey: key);
    final pub = await mine.extractPublicKey();
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final req = await client.postUrl(Uri(scheme: 'http', host: tv.host, port: tv.port, path: _linkPath));
      req.headers.contentType = ContentType.json;
      req.write(
        jsonEncode({
          'pub': base64.encode(pub.bytes),
          'nonce': base64.encode(box.nonce),
          'data': base64.encode(box.cipherText),
          'mac': base64.encode(box.mac.bytes),
        }),
      );
      final res = await req.close().timeout(const Duration(seconds: 20));
      await res.drain<void>();
      switch (res.statusCode) {
        case 200:
          return;
        case 403:
          throw TvLinkException(tr('El código no coincide con el de la TV.'));
        case 429:
          throw TvLinkException(tr('Demasiados intentos. En la TV, pide un código nuevo.'));
        default:
          throw TvLinkException(tr('La TV no aceptó la conexión ({0}).', [res.statusCode]));
      }
    } on TvLinkException {
      rethrow;
    } catch (_) {
      throw TvLinkException(tr('No se pudo hablar con la TV. Revisa que siga mostrando el código.'));
    } finally {
      client.close(force: true);
    }
  }
}
