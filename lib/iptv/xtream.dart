import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// What the user types once: server URL, user name and password.
class Credentials {
  Credentials({required String server, required this.username, required this.password})
      : server = normalizeServer(server);

  final String server;
  final String username;
  final String password;

  /// Same account over plain http (most IPTV ports are not encrypted).
  Credentials withHttp() => Credentials(
      server: server.replaceFirst(RegExp('^https://', caseSensitive: false), 'http://'),
      username: username,
      password: password);

  Map<String, String> toJson() =>
      {'server': server, 'username': username, 'password': password};

  static Credentials? fromJson(Map<String, dynamic>? j) {
    if (j == null || j['server'] == null) return null;
    return Credentials(
      server: j['server'] as String,
      username: (j['username'] ?? '') as String,
      password: (j['password'] ?? '') as String,
    );
  }

  /// "example.com:8080/" -> "http://example.com:8080"
  static String normalizeServer(String raw) {
    var s = raw.trim();
    if (s.isEmpty) return s;
    if (!s.startsWith(RegExp(r'https?://', caseSensitive: false))) s = 'http://$s';
    // People often paste the full API or M3U link: keep only the origin.
    final uri = Uri.tryParse(s);
    if (uri == null || uri.host.isEmpty) return s;
    return uri.hasPort ? '${uri.scheme}://${uri.host}:${uri.port}' : '${uri.scheme}://${uri.host}';
  }
}

/// Account state as the server reports it (Xtream `user_info`).
class AccountInfo {
  AccountInfo({
    required this.active,
    required this.status,
    this.expires,
    required this.maxConnections,
    required this.activeConnections,
  });

  final bool active;
  final String status;
  final DateTime? expires;
  final int maxConnections;
  final int activeConnections;

  bool get full => maxConnections > 0 && activeConnections >= maxConnections;

  static AccountInfo fromJson(Map<String, dynamic> j) {
    final u = (j['user_info'] ?? const {}) as Map<String, dynamic>;
    final exp = asInt(u['exp_date']);
    return AccountInfo(
      active: asInt(u['auth']) == 1,
      status: (u['status'] ?? '').toString(),
      expires: exp > 0 ? DateTime.fromMillisecondsSinceEpoch(exp * 1000) : null,
      maxConnections: asInt(u['max_connections']),
      activeConnections: asInt(u['active_cons']),
    );
  }
}

enum Kind { live, movie, series, episode }

class Category {
  Category(this.kind, this.id, this.name);
  final Kind kind;
  final String id;
  final String name;
}

/// A channel, movie or series as listed in the catalog.
class CatalogItem {
  CatalogItem({
    required this.kind,
    required this.id,
    required this.name,
    required this.categoryId,
    this.icon = '',
    this.extension = '',
    this.epgId = '',
    this.tmdbId = '',
    this.year = '',
    this.number = 0,
  });

  final Kind kind;
  final String id;
  final String name;
  final String categoryId;
  final String icon;
  final String extension;
  final String epgId;
  final String tmdbId;
  final String year;
  final int number;

  Map<String, Object?> toRow() => {
        'kind': kind.name,
        'id': id,
        'name': name,
        'category_id': categoryId,
        'icon': icon,
        'ext': extension,
        'epg_id': epgId,
        'tmdb_id': tmdbId,
        'year': year,
        'num': number,
      };

  static CatalogItem fromRow(Map<String, Object?> r) => CatalogItem(
        kind: Kind.values.byName(r['kind'] as String),
        id: r['id'] as String,
        name: r['name'] as String,
        categoryId: (r['category_id'] ?? '') as String,
        icon: (r['icon'] ?? '') as String,
        extension: (r['ext'] ?? '') as String,
        epgId: (r['epg_id'] ?? '') as String,
        tmdbId: (r['tmdb_id'] ?? '') as String,
        year: (r['year'] ?? '') as String,
        number: (r['num'] ?? 0) as int,
      );
}

class Episode {
  Episode({
    required this.id,
    required this.season,
    required this.number,
    required this.title,
    required this.extension,
    required this.durationSecs,
  });

  final String id;
  final int season;
  final int number;
  final String title;
  final String extension;
  final int durationSecs;
}

class SeriesInfo {
  SeriesInfo(this.seasons, this.plot);
  final Map<int, List<Episode>> seasons;
  final String plot;
}

class MovieInfo {
  MovieInfo({required this.durationSecs, required this.plot, required this.tmdbId});
  final int durationSecs;
  final String plot;
  final String tmdbId;
}

class XtreamException implements Exception {
  XtreamException(this.message, {this.tlsMismatch = false});
  final String message;

  /// The server answered plain HTTP to an https:// request.
  final bool tlsMismatch;
  @override
  String toString() => message;
}

/// Client for the Xtream Codes "player_api.php", which most IPTV providers
/// offer when they give a server URL, user and password.
class XtreamClient {
  XtreamClient(this.creds, {http.Client? client}) : _http = client ?? http.Client();

  final Credentials creds;
  final http.Client _http;

  Uri _api([Map<String, String> extra = const {}]) =>
      Uri.parse('${creds.server}/player_api.php').replace(queryParameters: {
        'username': creds.username,
        'password': creds.password,
        ...extra,
      });

  Future<dynamic> _get(Map<String, String> params) async {
    final http.Response res;
    try {
      res = await _http.get(_api(params)).timeout(const Duration(seconds: 60));
    } on HandshakeException catch (e) {
      throw XtreamException(
        'El servidor no usa https en ese puerto. Prueba con http:// al inicio de la URL.',
        tlsMismatch: e.toString().contains('WRONG_VERSION_NUMBER'),
      );
    } on TimeoutException {
      throw XtreamException('El servidor no respondió. Revisa la URL y el puerto.');
    } on SocketException {
      throw XtreamException('No se encontró el servidor. Revisa la URL, el puerto y tu conexión a internet.');
    } catch (e) {
      throw XtreamException('No se pudo conectar con el servidor ($e)');
    }
    if (res.statusCode == 401 || res.statusCode == 403) {
      throw XtreamException('El servidor rechazó el usuario o la contraseña');
    }
    if (res.statusCode != 200) {
      throw XtreamException('El servidor respondió ${res.statusCode}');
    }
    return parseJson(res.body);
  }

  Future<AccountInfo> account() async {
    final j = await _get(const {});
    if (j is! Map<String, dynamic>) throw XtreamException('Respuesta inesperada del servidor');
    final info = AccountInfo.fromJson(j);
    if (!info.active) throw XtreamException('Usuario o contraseña incorrectos');
    return info;
  }

  Future<List<Category>> categories(Kind kind) async {
    final action = switch (kind) {
      Kind.live => 'get_live_categories',
      Kind.movie => 'get_vod_categories',
      _ => 'get_series_categories',
    };
    return parseCategories(kind, await _get({'action': action}));
  }

  /// The whole list of one kind. Televizo-style: downloaded once and kept in
  /// the local database; screens read from there.
  Future<List<CatalogItem>> items(Kind kind) async {
    final action = switch (kind) {
      Kind.live => 'get_live_streams',
      Kind.movie => 'get_vod_streams',
      _ => 'get_series',
    };
    return parseItems(kind, await _get({'action': action}));
  }

  Future<SeriesInfo> seriesInfo(String seriesId) async =>
      parseSeriesInfo(await _get({'action': 'get_series_info', 'series_id': seriesId}));

  Future<MovieInfo> movieInfo(String vodId) async =>
      parseMovieInfo(await _get({'action': 'get_vod_info', 'vod_id': vodId}));

  String liveUrl(String id) => '${creds.server}/live/${_seg(creds.username)}/${_seg(creds.password)}/$id.ts';

  String movieUrl(String id, String ext) =>
      '${creds.server}/movie/${_seg(creds.username)}/${_seg(creds.password)}/$id.${ext.isEmpty ? 'mp4' : ext}';

  String episodeUrl(String id, String ext) =>
      '${creds.server}/series/${_seg(creds.username)}/${_seg(creds.password)}/$id.${ext.isEmpty ? 'mp4' : ext}';

  static String _seg(String s) => Uri.encodeComponent(s);

  void close() => _http.close();
}

// ---- Parsing (pure, tested). Providers mix strings and numbers freely. ----

dynamic parseJson(String body) {
  try {
    return jsonDecode(body);
  } catch (_) {
    throw XtreamException('El servidor no devolvió datos válidos');
  }
}

int asInt(Object? v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v.trim()) ?? double.tryParse(v.trim())?.toInt() ?? 0;
  return 0;
}

String asStr(Object? v) => v == null ? '' : v.toString().trim();

/// "01:45:30" or "105 min" or seconds -> seconds.
int parseDuration(Object? secs, Object? text) {
  final s = asInt(secs);
  if (s > 0) return s;
  final t = asStr(text);
  final hms = RegExp(r'^(\d+):(\d{1,2})(?::(\d{1,2}))?$').firstMatch(t);
  if (hms != null) {
    final a = int.parse(hms[1]!), b = int.parse(hms[2]!);
    final c = hms[3] == null ? null : int.parse(hms[3]!);
    return c == null ? a * 60 + b : a * 3600 + b * 60 + c;
  }
  final min = RegExp(r'(\d+)\s*min').firstMatch(t);
  if (min != null) return int.parse(min[1]!) * 60;
  return 0;
}

List<Category> parseCategories(Kind kind, dynamic j) {
  if (j is! List) return const [];
  return [
    for (final c in j)
      if (c is Map) Category(kind, asStr(c['category_id']), asStr(c['category_name'])),
  ];
}

List<CatalogItem> parseItems(Kind kind, dynamic j) {
  if (j is! List) return const [];
  final out = <CatalogItem>[];
  for (final e in j) {
    if (e is! Map) continue;
    final id = asStr(kind == Kind.series ? e['series_id'] : e['stream_id']);
    if (id.isEmpty) continue;
    final release = asStr(e['releaseDate'] ?? e['release_date'] ?? e['year']);
    out.add(CatalogItem(
      kind: kind,
      id: id,
      name: asStr(e['name']),
      categoryId: asStr(e['category_id']),
      icon: asStr(kind == Kind.series ? e['cover'] : e['stream_icon']),
      extension: asStr(e['container_extension']),
      epgId: asStr(e['epg_channel_id']),
      tmdbId: asStr(e['tmdb'] ?? e['tmdb_id']),
      year: release.length >= 4 ? release.substring(0, 4) : '',
      number: asInt(e['num']),
    ));
  }
  return out;
}

SeriesInfo parseSeriesInfo(dynamic j) {
  final seasons = <int, List<Episode>>{};
  if (j is! Map) return SeriesInfo(seasons, '');
  final eps = j['episodes'];
  final lists = eps is Map ? eps.values : (eps is List ? eps : const []);
  for (final list in lists) {
    if (list is! List) continue;
    for (final e in list) {
      if (e is! Map) continue;
      final info = e['info'] is Map ? e['info'] as Map : const {};
      final ep = Episode(
        id: asStr(e['id']),
        season: asInt(e['season']),
        number: asInt(e['episode_num']),
        title: asStr(e['title']),
        extension: asStr(e['container_extension']),
        durationSecs: parseDuration(info['duration_secs'], info['duration']),
      );
      if (ep.id.isEmpty) continue;
      seasons.putIfAbsent(ep.season, () => []).add(ep);
    }
  }
  for (final l in seasons.values) {
    l.sort((a, b) => a.number.compareTo(b.number));
  }
  final info = j['info'] is Map ? j['info'] as Map : const {};
  return SeriesInfo(seasons, asStr(info['plot']));
}

MovieInfo parseMovieInfo(dynamic j) {
  final info = j is Map && j['info'] is Map ? j['info'] as Map : const {};
  return MovieInfo(
    durationSecs: parseDuration(info['duration_secs'], info['duration']),
    plot: asStr(info['plot'] ?? info['description']),
    tmdbId: asStr(info['tmdb_id']),
  );
}
