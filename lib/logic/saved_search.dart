import '../iptv/xtream.dart';

/// The filters a search can have (2.2.0, pedido de Jose 2026-11-15).
enum SearchFilter {
  /// Channels: not marked as down (see [ChannelHealth]).
  active,

  /// Channels: the guide says what is on now (they show the progress bar).
  onNow,
  neverSeen,
  seen,
  inProgress,
  myList;

  static SearchFilter? fromName(String? n) => values.where((f) => f.name == n).firstOrNull;
}

/// A search with its filters, as it is saved (per profile, synced).
class SavedSearch {
  SavedSearch({
    required this.id,
    this.name = '',
    this.text = '',
    this.kind,
    Set<SearchFilter>? filters,
    this.quality,
    this.inGuide = false,
    this.guideFirst = false,
    this.updatedAt = 0,
    this.deleted = false,
  }) : filters = filters ?? {};

  final String id;
  String name;
  String text;

  /// Null: everything (channels, movies and series).
  Kind? kind;
  Set<SearchFilter> filters;

  /// Channels: only this quality (from the name).
  Quality? quality;

  /// Channels: the words may also be in what is on now (the guide).
  bool inGuide;

  /// Channels with the progress bar (the guide says what is on) go first.
  bool guideFirst;
  int updatedAt;
  bool deleted;

  /// The example installed in every profile: channels showing Real Madrid now.
  static const exampleId = 'real-madrid-vivo';
  static SavedSearch example() => SavedSearch(
    id: exampleId,
    name: 'Real Madrid Vivo',
    text: 'real madrid',
    kind: Kind.live,
    filters: {SearchFilter.active},
    inGuide: true,
    guideFirst: true,
    // The oldest date: any change on any device wins over it.
    updatedAt: 1,
  );

  bool get isEmpty => text.trim().isEmpty && filters.isEmpty && quality == null && kind == null;

  /// Something to show without words: a filter (or a kind) is enough.
  bool get canRun => text.trim().isNotEmpty || filters.isNotEmpty || quality != null || inGuide;

  /// Only channels can be "active", "on now" or have a quality.
  bool get channelsOnly =>
      kind == Kind.live ||
      quality != null ||
      filters.contains(SearchFilter.active) ||
      filters.contains(SearchFilter.onNow) ||
      inGuide;

  SavedSearch copy({String? id, String? name}) => SavedSearch.fromJson({...toJson(), 'id': ?id, 'name': ?name});

  /// The same search (not the name or date).
  bool sameAs(SavedSearch o) =>
      text.trim().toLowerCase() == o.text.trim().toLowerCase() &&
      kind == o.kind &&
      quality == o.quality &&
      inGuide == o.inGuide &&
      guideFirst == o.guideFirst &&
      filters.length == o.filters.length &&
      filters.containsAll(o.filters);

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'text': text,
    'kind': kind?.name,
    'filters': [for (final f in filters) f.name]..sort(),
    'quality': quality?.name,
    'inGuide': inGuide,
    'guideFirst': guideFirst,
    'at': updatedAt,
    if (deleted) 'deleted': true,
  };

  static SavedSearch fromJson(Map<String, dynamic> j) => SavedSearch(
    id: j['id'] as String,
    name: (j['name'] ?? '') as String,
    text: (j['text'] ?? '') as String,
    kind: Kind.values.where((k) => k.name == j['kind']).firstOrNull,
    filters: {for (final f in (j['filters'] as List?) ?? const []) ?SearchFilter.fromName(f as String?)},
    quality: Quality.values.where((q) => q.name == j['quality']).firstOrNull,
    inGuide: j['inGuide'] == true,
    guideFirst: j['guideFirst'] == true,
    updatedAt: (j['at'] as num?)?.toInt() ?? 0,
    deleted: j['deleted'] == true,
  );
}

/// What the library knows of one catalog item, for the filters.
class ItemState {
  const ItemState({this.seen = false, this.started = false, this.inProgress = false, this.myList = false});

  /// Watched (a movie, an episode of a series) or played (a channel).
  final bool seen;

  /// Played or watched at all.
  final bool started;
  final bool inProgress;
  final bool myList;
}

/// True when [it] passes the filters of [s]. [down] and [onNow] tell the
/// state of channels; [state] what the library knows of it.
bool passesFilters(SavedSearch s, CatalogItem it, {required ItemState state, bool down = false, bool onNow = false}) {
  if (s.kind != null && it.kind != s.kind) return false;
  if (s.channelsOnly && it.kind != Kind.live) return false;
  if (s.quality != null && qualityOf(it.name) != s.quality) return false;
  for (final f in s.filters) {
    final ok = switch (f) {
      SearchFilter.active => !down,
      SearchFilter.onNow => onNow,
      SearchFilter.neverSeen => !state.started,
      SearchFilter.seen => state.seen,
      SearchFilter.inProgress => state.inProgress,
      SearchFilter.myList => state.myList,
    };
    if (!ok) return false;
  }
  return true;
}

/// Channels whose guide says what is on go first (stable otherwise).
List<CatalogItem> guideFirst(List<CatalogItem> items, bool Function(CatalogItem) hasGuide) {
  final a = <CatalogItem>[], b = <CatalogItem>[];
  for (final it in items) {
    (hasGuide(it) ? a : b).add(it);
  }
  return [...a, ...b];
}

/// Every word of [text] (lower case, no accents: see [AppDatabase.searchKey])
/// is in [key].
bool hasWords(String key, List<String> words) => words.every(key.contains);

/// Per-profile saved searches merged with another device's: the newest
/// change of each one wins (a deletion too).
int mergeSaved(Map<String, Map<String, SavedSearch>> local, Map<String, Map<String, SavedSearch>> remote) {
  var n = 0;
  for (final p in remote.entries) {
    final m = local.putIfAbsent(p.key, () => {});
    for (final e in p.value.entries) {
      if ((m[e.key]?.updatedAt ?? -1) >= e.value.updatedAt) continue;
      m[e.key] = e.value;
      n++;
    }
  }
  return n;
}

/// Whether a channel opened lately (2.2.0). Shared by all profiles and
/// devices: a channel down is down for everyone.
class ChannelHealth {
  const ChannelHealth(this.ok, this.at);
  final bool ok;

  /// ms since epoch.
  final int at;

  /// A mark is kept for some hours: a channel down now may be back later.
  static const keep = Duration(hours: 3);

  bool fresh(int now) => now - at < keep.inMilliseconds;

  Map<String, Object> toJson() => {'ok': ok, 'at': at};
  static ChannelHealth? fromJson(Object? j) {
    if (j is! Map) return null;
    final at = (j['at'] as num?)?.toInt();
    return at == null ? null : ChannelHealth(j['ok'] == true, at);
  }
}
