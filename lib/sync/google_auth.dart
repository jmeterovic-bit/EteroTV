import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

/// OAuth clients, injected at build time (GitHub secrets):
/// - "Desktop app" client: browser sign-in on phone and PC.
/// - "TVs and Limited Input devices" client: code on screen for TV.
/// For installed apps Google does not treat these secrets as confidential.
const _desktopId = String.fromEnvironment('GOOGLE_CLIENT_ID');
const _desktopSecret = String.fromEnvironment('GOOGLE_CLIENT_SECRET');
const _tvId = String.fromEnvironment('GOOGLE_TV_CLIENT_ID');
const _tvSecret = String.fromEnvironment('GOOGLE_TV_CLIENT_SECRET');

/// Only the app's hidden folder in the user's Drive: no access to anything else.
const driveScope = 'https://www.googleapis.com/auth/drive.appdata';

class OAuthClient {
  const OAuthClient(this.kind, this.id, this.secret);
  final String kind; // 'desktop' or 'tv'
  final String id;
  final String secret;
  bool get configured => id.isNotEmpty;

  static const desktop = OAuthClient('desktop', _desktopId, _desktopSecret);
  static const tv = OAuthClient('tv', _tvId, _tvSecret);
  static OAuthClient byKind(String k) => k == 'tv' ? tv : desktop;
}

class GoogleAuthException implements Exception {
  GoogleAuthException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// What the TV shows: go to [url] on another device and type [userCode].
class DeviceCode {
  DeviceCode({
    required this.deviceCode,
    required this.userCode,
    required this.url,
    required this.interval,
    required this.expiresAt,
  });
  final String deviceCode;
  final String userCode;
  final String url;
  final Duration interval;
  final DateTime expiresAt;
}

/// Where the refresh token is kept. Tests use a map.
abstract class TokenStore {
  Future<String?> read();
  Future<void> write(String value);
  Future<void> delete();
}

class SecureTokenStore implements TokenStore {
  static const _s = FlutterSecureStorage();
  static const _key = 'google_tokens';
  @override
  Future<String?> read() => _s.read(key: _key);
  @override
  Future<void> write(String value) => _s.write(key: _key, value: value);
  @override
  Future<void> delete() => _s.delete(key: _key);
}

/// Google sign-in without Google libraries (Fire TV has no Google services):
/// plain OAuth over HTTP. Phone and PC use the browser with a loopback
/// redirect and PKCE; TVs use the device flow (a code shown on screen).
class GoogleAuth {
  GoogleAuth({TokenStore? store, http.Client? client})
    : store = store ?? SecureTokenStore(),
      _http = client ?? http.Client();

  final TokenStore store;
  final http.Client _http;

  static const _tokenUrl = 'https://oauth2.googleapis.com/token';

  String? _refreshToken;
  String _clientKind = 'desktop';
  String? _accessToken;
  DateTime _expiry = DateTime.fromMillisecondsSinceEpoch(0);

  static bool get browserAvailable => OAuthClient.desktop.configured;
  static bool get codeAvailable => OAuthClient.tv.configured;
  static bool get configured => browserAvailable || codeAvailable;

  bool get signedIn => _refreshToken != null;

  Future<void> load() async {
    try {
      final raw = await store.read();
      if (raw == null) return;
      final m = jsonDecode(raw) as Map<String, dynamic>;
      _refreshToken = m['refresh_token'] as String?;
      _clientKind = (m['client'] as String?) ?? 'desktop';
    } catch (_) {
      _refreshToken = null;
    }
  }

  Future<void> _keep(Map<String, dynamic> token, String kind) async {
    final refresh = token['refresh_token'] as String?;
    if (refresh == null) throw GoogleAuthException('Google no entregó permiso permanente. Intenta de nuevo.');
    _refreshToken = refresh;
    _clientKind = kind;
    _setAccess(token);
    await store.write(jsonEncode({'refresh_token': refresh, 'client': kind}));
  }

  void _setAccess(Map<String, dynamic> token) {
    _accessToken = token['access_token'] as String?;
    final secs = (token['expires_in'] as num?)?.toInt() ?? 3600;
    _expiry = DateTime.now().add(Duration(seconds: secs - 60));
  }

  Future<void> signOut() async {
    _refreshToken = null;
    _accessToken = null;
    try {
      await store.delete();
    } catch (_) {}
  }

  /// A valid access token, refreshed when needed.
  Future<String> accessToken() async {
    final refresh = _refreshToken;
    if (refresh == null) throw GoogleAuthException('No has conectado Google en este dispositivo.');
    if (_accessToken != null && DateTime.now().isBefore(_expiry)) return _accessToken!;
    final c = OAuthClient.byKind(_clientKind);
    final r = await _http.post(
      Uri.parse(_tokenUrl),
      body: {'client_id': c.id, 'client_secret': c.secret, 'refresh_token': refresh, 'grant_type': 'refresh_token'},
    );
    final m = _json(r);
    if (r.statusCode != 200) {
      if (m['error'] == 'invalid_grant') {
        await signOut();
        throw GoogleAuthException('Google cerró la sesión. Conéctalo de nuevo en Ajustes.');
      }
      throw GoogleAuthException('Google no respondió (${m['error'] ?? r.statusCode}).');
    }
    _setAccess(m);
    return _accessToken!;
  }

  // ---- Browser (phone, PC) ----

  Future<void> signInWithBrowser() async {
    const c = OAuthClient.desktop;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final redirect = 'http://127.0.0.1:${server.port}';
    final state = _random(24);
    final verifier = _random(64);
    final challenge = base64Url.encode(sha256.convert(ascii.encode(verifier)).bytes).replaceAll('=', '');
    final url = Uri.https('accounts.google.com', '/o/oauth2/v2/auth', {
      'client_id': c.id,
      'redirect_uri': redirect,
      'response_type': 'code',
      'scope': driveScope,
      'access_type': 'offline',
      'prompt': 'consent',
      'state': state,
      'code_challenge': challenge,
      'code_challenge_method': 'S256',
    });
    String code;
    try {
      if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
        throw GoogleAuthException('No se pudo abrir el navegador. En la TV usa «Con un código».');
      }
      code = await _waitForCode(server, state).timeout(const Duration(minutes: 10));
    } finally {
      await server.close(force: true);
    }
    // Exchange after coming back to the app, retrying: some devices cut the
    // network of apps in the background while the browser is in front.
    Object? last;
    for (var i = 0; i < 10; i++) {
      if (i > 0) await Future<void>.delayed(Duration(seconds: 2 * i));
      try {
        final r = await _http.post(
          Uri.parse(_tokenUrl),
          body: {
            'client_id': c.id,
            'client_secret': c.secret,
            'code': code,
            'code_verifier': verifier,
            'redirect_uri': redirect,
            'grant_type': 'authorization_code',
          },
        );
        final m = _json(r);
        if (r.statusCode != 200) throw GoogleAuthException('Google rechazó el inicio de sesión (${m['error']}).');
        await _keep(m, c.kind);
        return;
      } on SocketException catch (e) {
        last = e;
      } on http.ClientException catch (e) {
        last = e;
      }
    }
    throw GoogleAuthException('Sin conexión para terminar el inicio de sesión: $last');
  }

  static Future<String> _waitForCode(HttpServer server, String state) async {
    await for (final req in server) {
      final q = req.uri.queryParameters;
      final code = q['code'];
      final error = q['error'];
      if (code == null && error == null) {
        req.response.statusCode = 404;
        await req.response.close();
        continue;
      }
      final ok = error == null && q['state'] == state && code!.isNotEmpty;
      req.response
        ..statusCode = 200
        ..headers.set('content-type', 'text/html; charset=UTF-8')
        ..write(
          '<!DOCTYPE html><html><head><meta name="viewport" content="width=device-width"></head>'
          '<body style="font:20px sans-serif;text-align:center;padding-top:40px;background:#141414;color:#eee">'
          '${ok ? '&#10003; EteroTV<br><br>Vuelve a la app.' : 'No se pudo iniciar sesión: ${error ?? 'estado'}'}'
          '</body></html>',
        );
      await req.response.close();
      if (!ok) throw GoogleAuthException('Google: ${error ?? 'respuesta inesperada'}');
      return code;
    }
    throw GoogleAuthException('Se cerró la ventana de inicio de sesión.');
  }

  // ---- Code on screen (TV) ----

  Future<DeviceCode> startDeviceFlow() async {
    const c = OAuthClient.tv;
    final r = await _http.post(
      Uri.parse('https://oauth2.googleapis.com/device/code'),
      body: {'client_id': c.id, 'scope': driveScope},
    );
    final m = _json(r);
    if (r.statusCode != 200) {
      // Google's own explanation helps tell a wrong client id from a scope problem.
      final why = [m['error'] ?? r.statusCode, ?m['error_description']].join(': ');
      throw GoogleAuthException('Google no dio un código ($why).');
    }
    return DeviceCode(
      deviceCode: m['device_code'] as String,
      userCode: m['user_code'] as String,
      url: (m['verification_url'] ?? m['verification_uri'] ?? 'https://www.google.com/device') as String,
      interval: Duration(seconds: (m['interval'] as num?)?.toInt() ?? 5),
      expiresAt: DateTime.now().add(Duration(seconds: (m['expires_in'] as num?)?.toInt() ?? 1800)),
    );
  }

  /// Waits until the user approves [d] on another device. [cancelled] stops it.
  Future<void> waitForDevice(DeviceCode d, {bool Function()? cancelled}) async {
    const c = OAuthClient.tv;
    var interval = d.interval;
    while (DateTime.now().isBefore(d.expiresAt)) {
      await Future<void>.delayed(interval);
      if (cancelled?.call() ?? false) throw GoogleAuthException('Cancelado.');
      http.Response r;
      try {
        r = await _http.post(
          Uri.parse(_tokenUrl),
          body: {
            'client_id': c.id,
            'client_secret': c.secret,
            'device_code': d.deviceCode,
            'grant_type': 'urn:ietf:params:oauth:grant-type:device_code',
          },
        );
      } on SocketException {
        continue;
      }
      final m = _json(r);
      if (r.statusCode == 200) {
        await _keep(m, c.kind);
        return;
      }
      switch (m['error']) {
        case 'authorization_pending':
          continue;
        case 'slow_down':
          interval += const Duration(seconds: 5);
          continue;
        case 'access_denied':
          throw GoogleAuthException('Se rechazó el permiso en Google.');
        default:
          throw GoogleAuthException('Google: ${m['error'] ?? r.statusCode}');
      }
    }
    throw GoogleAuthException('El código venció. Pide uno nuevo.');
  }

  static Map<String, dynamic> _json(http.Response r) {
    try {
      return jsonDecode(r.body) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  static String _random(int n) {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';
    final r = Random.secure();
    return List.generate(n, (_) => chars[r.nextInt(chars.length)]).join();
  }
}
