// "Lo nuevo" (1.1.0, Jose 2026-11-10): series from someone's history that
// got a new season or new episodes in a list refresh. Kept apart from the
// UI so it can be tested.

import '../iptv/xtream.dart';

enum NewsKind { season, episode }

/// What a device last knew of a series: its last season and how many
/// episodes that season had.
class SeriesShape {
  const SeriesShape(this.lastSeason, this.lastSeasonEpisodes);
  final int lastSeason;
  final int lastSeasonEpisodes;

  static SeriesShape of(SeriesInfo info) {
    final seasons = [
      for (final e in info.seasons.entries)
        if (e.value.isNotEmpty) e.key,
    ]..sort();
    if (seasons.isEmpty) return const SeriesShape(0, 0);
    final last = seasons.last;
    final eps = info.seasons[last]!;
    var top = 0;
    for (final ep in eps) {
      if (ep.number > top) top = ep.number;
    }
    return SeriesShape(last, top > eps.length ? top : eps.length);
  }

  List<int> toJson() => [lastSeason, lastSeasonEpisodes];
  static SeriesShape fromJson(Object? j) =>
      j is List && j.length == 2 ? SeriesShape((j[0] as num).toInt(), (j[1] as num).toInt()) : const SeriesShape(0, 0);
}

/// A new season beats new episodes. Null when nothing grew (or the series
/// was not known before: the first look only takes note).
NewsKind? newsBetween(SeriesShape? before, SeriesShape now) {
  if (before == null || now.lastSeason == 0) return null;
  if (now.lastSeason > before.lastSeason) return NewsKind.season;
  if (now.lastSeason == before.lastSeason && now.lastSeasonEpisodes > before.lastSeasonEpisodes) {
    return NewsKind.episode;
  }
  return null;
}

/// A series flagged as new, and what it looked like before (to know when
/// the user has watched the new part).
class SeriesNews {
  SeriesNews(this.kind, this.before, this.at);
  final NewsKind kind;
  final SeriesShape before;

  /// ms since epoch when it was found.
  final int at;

  /// Watching an episode past what was known before clears the mark.
  bool seenWith(int season, int episode) =>
      season > before.lastSeason || (season == before.lastSeason && episode > before.lastSeasonEpisodes);

  static const keepFor = Duration(days: 30);

  Map<String, Object?> toJson() => {'k': kind.name, 'b': before.toJson(), 'at': at};
  static SeriesNews fromJson(Map<String, dynamic> j) => SeriesNews(
    NewsKind.values.firstWhere((k) => k.name == j['k'], orElse: () => NewsKind.episode),
    SeriesShape.fromJson(j['b']),
    ((j['at'] ?? 0) as num).toInt(),
  );
}
