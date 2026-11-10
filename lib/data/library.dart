import '../iptv/xtream.dart';
import '../ui/i18n.dart';

/// One entry of "my library": a favourite and/or something with progress.
/// This is the only data that will be synced between devices (stage 2).
class LibraryEntry {
  LibraryEntry({
    required this.kind,
    required this.id,
    required this.name,
    this.icon = '',
    this.extension = '',
    this.seriesId = '',
    this.seriesName = '',
    this.season = 0,
    this.episode = 0,
    this.tmdbId = '',
    this.year = '',
    this.epgId = '',
    this.favorite = false,
    this.positionSecs = 0,
    this.durationSecs = 0,
    this.watched = false,
    this.lastPlayed = 0,
    required this.updatedAt,
    this.device = '',
  });

  final Kind kind;
  final String id;
  String name;
  String icon;
  String extension;
  String seriesId;
  String seriesName;
  int season;
  int episode;
  String tmdbId;
  String year;
  String epgId;
  bool favorite;
  int positionSecs;
  int durationSecs;
  bool watched;

  /// ms since epoch; 0 = never played here.
  int lastPlayed;

  /// ms since epoch of the last change; the newest change wins when syncing.
  int updatedAt;
  String device;

  String get key => keyOf(kind, id);
  static String keyOf(Kind kind, String id) => '${kind.name}:$id';

  String get title => kind == Kind.episode
      ? tr('{0} · T{1} E{2}{3}', [seriesName, season, episode, name.isEmpty || name == seriesName ? '' : ' · $name'])
      : name;

  Map<String, Object?> toRow() => {
    'key': key,
    'kind': kind.name,
    'id': id,
    'name': name,
    'icon': icon,
    'ext': extension,
    'series_id': seriesId,
    'series_name': seriesName,
    'season': season,
    'episode': episode,
    'tmdb_id': tmdbId,
    'year': year,
    'epg_id': epgId,
    'favorite': favorite ? 1 : 0,
    'position': positionSecs,
    'duration': durationSecs,
    'watched': watched ? 1 : 0,
    'last_played': lastPlayed,
    'updated_at': updatedAt,
    'device': device,
  };

  static LibraryEntry fromRow(Map<String, Object?> r) => LibraryEntry(
    kind: Kind.values.byName(r['kind'] as String),
    id: r['id'] as String,
    name: (r['name'] ?? '') as String,
    icon: (r['icon'] ?? '') as String,
    extension: (r['ext'] ?? '') as String,
    seriesId: (r['series_id'] ?? '') as String,
    seriesName: (r['series_name'] ?? '') as String,
    season: (r['season'] ?? 0) as int,
    episode: (r['episode'] ?? 0) as int,
    tmdbId: (r['tmdb_id'] ?? '') as String,
    year: (r['year'] ?? '') as String,
    epgId: (r['epg_id'] ?? '') as String,
    favorite: r['favorite'] == 1,
    positionSecs: (r['position'] ?? 0) as int,
    durationSecs: (r['duration'] ?? 0) as int,
    watched: r['watched'] == 1,
    lastPlayed: (r['last_played'] ?? 0) as int,
    updatedAt: (r['updated_at'] ?? 0) as int,
    device: (r['device'] ?? '') as String,
  );

  static LibraryEntry fromCatalog(CatalogItem c, {required int now, required String device}) => LibraryEntry(
    kind: c.kind,
    id: c.id,
    name: c.name,
    icon: c.icon,
    extension: c.extension,
    tmdbId: c.tmdbId,
    year: c.year,
    epgId: c.epgId,
    updatedAt: now,
    device: device,
  );
}
