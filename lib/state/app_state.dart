import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import 'package:flutter/foundation.dart' hide Category;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/database.dart';
import '../data/library.dart';
import '../iptv/xtream.dart';
import '../logic/progress.dart';
import '../logic/rematch.dart';
import '../player/vlc.dart';

class AppState extends ChangeNotifier {
  AppState({required this.db, required this.prefs, required this.deviceId, VlcLauncher? vlc})
    : vlc = vlc ?? VlcLauncher.forPlatform();

  final AppDatabase db;
  final SharedPreferences prefs;
  final String deviceId;
  final VlcLauncher vlc;

  static const _storage = FlutterSecureStorage();
  static const _credsKey = 'iptv_credentials';
  static const refreshEvery = Duration(hours: 24);

  Credentials? creds;
  XtreamClient? get client => creds == null ? null : XtreamClient(creds!);

  final Map<String, LibraryEntry> _library = {};

  bool refreshing = false;
  String refreshStep = '';
  String? error;

  /// Favourites / progress whose id disappeared in the last list refresh.
  List<LibraryEntry> lost = [];

  DateTime? get lastRefresh {
    final ms = prefs.getInt('lastRefresh');
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  int get _now => DateTime.now().millisecondsSinceEpoch;

  Future<void> init() async {
    try {
      final raw = await _storage.read(key: _credsKey);
      if (raw != null) creds = Credentials.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      creds = null;
    }
    for (final e in await db.library()) {
      _library[e.key] = e;
    }
    await _loadLocks();
    notifyListeners();
    final last = lastRefresh;
    if (creds != null && (last == null || DateTime.now().difference(last) > refreshEvery)) {
      unawaited(refreshCatalog());
    } else if (creds != null) {
      unawaited(_findLost());
    }
  }

  // ---- Account ----

  /// Checks the credentials with the server, then saves them.
  Future<AccountInfo> signIn(Credentials c) async {
    AccountInfo info;
    try {
      info = await XtreamClient(c).account();
    } on XtreamException catch (e) {
      // "https://" typed for a port that only speaks http: retry as http.
      if (!e.tlsMismatch || !c.server.startsWith('https://')) rethrow;
      c = c.withHttp();
      info = await XtreamClient(c).account();
    }
    await _storage.write(key: _credsKey, value: jsonEncode(c.toJson()));
    creds = c;
    notifyListeners();
    unawaited(refreshCatalog());
    return info;
  }

  Future<void> signOut() async {
    await _storage.delete(key: _credsKey);
    creds = null;
    notifyListeners();
  }

  Future<AccountInfo?> account() async {
    final c = client;
    if (c == null) return null;
    try {
      return await c.account();
    } finally {
      c.close();
    }
  }

  // ---- Catalog ----

  Future<void> refreshCatalog() async {
    final c = creds;
    if (c == null || refreshing) return;
    refreshing = true;
    error = null;
    notifyListeners();
    try {
      for (final kind in [Kind.live, Kind.movie, Kind.series]) {
        refreshStep = switch (kind) {
          Kind.live => 'Descargando canales…',
          Kind.movie => 'Descargando películas…',
          _ => 'Descargando series…',
        };
        notifyListeners();
        // Download and parse in another isolate: a big list must not freeze the screen.
        final (cats, items) = await downloadKind(c, kind);
        await db.replaceCatalog(kind, cats, items);
      }
      await prefs.setInt('lastRefresh', _now);
      await _refreshHidden();
      await _findLost();
    } catch (e) {
      error = e.toString();
    } finally {
      refreshing = false;
      refreshStep = '';
      notifyListeners();
    }
  }

  Future<void> _findLost() async {
    final out = <LibraryEntry>[];
    for (final e in _library.values) {
      if (!e.favorite && e.lastPlayed == 0) continue;
      final kind = e.kind == Kind.episode ? Kind.series : e.kind;
      final id = e.kind == Kind.episode ? e.seriesId : e.id;
      if (id.isEmpty) continue;
      if (await db.item(kind, id) == null) out.add(e);
    }
    // One lost series shows once, even with several episodes in progress.
    final seen = <String>{};
    lost = [
      for (final e in out)
        if (seen.add(e.kind == Kind.episode ? 'series:${e.seriesId}' : e.key)) e,
    ];
    notifyListeners();
  }

  /// Candidates for one lost entry, best first. Movies get their duration
  /// asked to the server for the top few, to tell remakes and versions apart.
  Future<List<Candidate>> candidatesFor(LibraryEntry e) async {
    final kind = e.kind == Kind.episode ? Kind.series : e.kind;
    final lostItem = LostItem(
      kind: kind,
      name: e.kind == Kind.episode ? e.seriesName : e.name,
      durationSecs: e.kind == Kind.movie ? e.durationSecs : 0,
      tmdbId: e.kind == Kind.episode ? '' : e.tmdbId,
      year: e.year,
      epgId: e.epgId,
    );
    var list = bestByName(lostItem, await db.allOf(kind));
    if (kind == Kind.movie && lostItem.durationSecs > 0 && client != null) {
      final x = client!;
      try {
        list = [
          for (final c in list)
            scoreCandidate(
              lostItem,
              c.item,
              candidateDuration: await x
                  .movieInfo(c.item.id)
                  .then((m) => m.durationSecs)
                  .timeout(const Duration(seconds: 8), onTimeout: () => 0)
                  .catchError((_) => 0),
            ),
        ]..sort((a, b) => b.score.compareTo(a.score));
      } finally {
        x.close();
      }
    }
    return list;
  }

  /// The user picked [replacement] for [old]: favourite and progress move over.
  Future<void> replaceLost(LibraryEntry old, CatalogItem replacement) async {
    if (old.kind == Kind.episode) {
      // Episodes keep their own ids inside the new series; move the series
      // favourite and drop the old episode rows (their ids are gone too).
      for (final e in _library.values.where((x) => x.seriesId == old.seriesId).toList()) {
        await _remove(e.key);
      }
      final fav = _library[LibraryEntry.keyOf(Kind.series, old.seriesId)];
      if (fav != null) await _remove(fav.key);
      await _save(LibraryEntry.fromCatalog(replacement, now: _now, device: deviceId)..favorite = true);
    } else {
      final n = LibraryEntry.fromCatalog(replacement, now: _now, device: deviceId)
        ..favorite = old.favorite
        ..positionSecs = old.positionSecs
        ..durationSecs = old.durationSecs
        ..watched = old.watched
        ..lastPlayed = old.lastPlayed;
      await _remove(old.key);
      await _save(n);
    }
    lost.remove(old);
    notifyListeners();
  }

  Future<void> dismissLost(LibraryEntry old) async {
    lost.remove(old);
    if (old.kind == Kind.episode) {
      for (final e in _library.values.where((x) => x.seriesId == old.seriesId).toList()) {
        await _remove(e.key);
      }
    } else {
      await _remove(old.key);
    }
    notifyListeners();
  }

  // ---- Library ----

  @visibleForTesting
  void debugAdd(LibraryEntry e) => _library[e.key] = e;

  LibraryEntry? entry(Kind kind, String id) => _library[LibraryEntry.keyOf(kind, id)];

  bool isFavorite(Kind kind, String id) => entry(kind, id)?.favorite ?? false;

  List<LibraryEntry> favorites(Kind kind) =>
      _library.values.where((e) => e.kind == kind && e.favorite && !isHiddenEntry(e)).toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

  /// Netflix-style row: unfinished movies and episodes, newest first.
  List<LibraryEntry> get continueWatching =>
      _library.values
          .where(
            (e) =>
                (e.kind == Kind.movie || e.kind == Kind.episode) &&
                e.lastPlayed > 0 &&
                !e.watched &&
                e.positionSecs > 0 &&
                !isHiddenEntry(e),
          )
          .toList()
        ..sort((a, b) => b.lastPlayed.compareTo(a.lastPlayed));

  /// "Seguir viendo" folder: unfinished movies, or series with an episode
  /// played and not marked as finished, newest first.
  List<CatalogItem> inProgress(Kind kind) {
    if (kind == Kind.movie) {
      return [
        for (final e in continueWatching.where((e) => e.kind == Kind.movie))
          CatalogItem(
            kind: Kind.movie,
            id: e.id,
            name: e.name,
            categoryId: '',
            icon: e.icon,
            extension: e.extension,
            tmdbId: e.tmdbId,
            year: e.year,
          ),
      ];
    }
    if (kind != Kind.series) return const [];
    final eps = _library.values.where((e) => e.kind == Kind.episode && e.lastPlayed > 0 && !isHiddenEntry(e)).toList()
      ..sort((a, b) => b.lastPlayed.compareTo(a.lastPlayed));
    final seen = <String>{};
    return [
      for (final e in eps)
        if (e.seriesId.isNotEmpty && seen.add(e.seriesId))
          CatalogItem(
            kind: Kind.series,
            id: e.seriesId,
            name: e.seriesName,
            categoryId: '',
            icon: e.icon,
            year: e.year,
          ),
    ];
  }

  List<LibraryEntry> get recentChannels =>
      _library.values.where((e) => e.kind == Kind.live && e.lastPlayed > 0).toList()
        ..sort((a, b) => b.lastPlayed.compareTo(a.lastPlayed));

  List<LibraryEntry> episodesOf(String seriesId) =>
      _library.values.where((e) => e.kind == Kind.episode && e.seriesId == seriesId).toList();

  Future<void> toggleFavorite(CatalogItem item) async {
    final e = entry(item.kind, item.id) ?? LibraryEntry.fromCatalog(item, now: _now, device: deviceId);
    e
      ..favorite = !e.favorite
      ..updatedAt = _now
      ..device = deviceId;
    await _save(e);
    notifyListeners();
  }

  Future<void> setWatched(LibraryEntry e, bool watched) async {
    e
      ..watched = watched
      ..positionSecs = watched ? e.durationSecs : 0
      ..updatedAt = _now
      ..device = deviceId;
    await _save(e);
    notifyListeners();
  }

  /// "Quitar de Continuar viendo": forget the position, keep the rest. For an
  /// episode the whole series leaves "Seguir viendo" (episodes marked as
  /// seen stay seen).
  Future<void> removeFromContinue(LibraryEntry e) async {
    if (e.kind == Kind.episode && e.seriesId.isNotEmpty) return removeSeriesFromContinue(e.seriesId);
    e
      ..positionSecs = 0
      ..updatedAt = _now
      ..device = deviceId;
    await _save(e);
    notifyListeners();
  }

  Future<void> removeSeriesFromContinue(String seriesId) async {
    for (final e in episodesOf(seriesId)) {
      if (e.lastPlayed == 0 && e.positionSecs == 0) continue;
      e
        ..lastPlayed = 0
        ..positionSecs = e.watched ? e.positionSecs : 0
        ..updatedAt = _now
        ..device = deviceId;
      await _save(e);
    }
    notifyListeners();
  }

  /// From the "Seguir viendo" folder or a poster menu.
  Future<void> removeFromInProgress(CatalogItem item) async {
    if (item.kind == Kind.series) return removeSeriesFromContinue(item.id);
    final e = entry(item.kind, item.id);
    if (e != null) await removeFromContinue(e);
  }

  bool isInProgress(CatalogItem item) => item.kind == Kind.series
      ? episodesOf(item.id).any((e) => e.lastPlayed > 0)
      : continueWatching.any((e) => e.kind == item.kind && e.id == item.id);

  /// Marks an episode as seen (or not) without playing it.
  Future<void> setEpisodeWatched(CatalogItem series, Episode ep, bool watched) async {
    final e = _episodeEntry(series, ep);
    await setWatched(e, watched);
  }

  LibraryEntry _episodeEntry(CatalogItem series, Episode ep) {
    final e =
        entry(Kind.episode, ep.id) ??
        LibraryEntry(
          kind: Kind.episode,
          id: ep.id,
          name: ep.title,
          icon: series.icon,
          extension: ep.extension,
          seriesId: series.id,
          seriesName: series.name,
          season: ep.season,
          episode: ep.number,
          tmdbId: series.tmdbId,
          year: series.year,
          updatedAt: _now,
          device: deviceId,
        );
    if (e.durationSecs == 0) e.durationSecs = ep.durationSecs;
    return e;
  }

  /// Movies (not series) can be marked from a poster too.
  Future<void> setMovieWatched(CatalogItem m, bool watched) async {
    final e = entry(Kind.movie, m.id) ?? LibraryEntry.fromCatalog(m, now: _now, device: deviceId);
    await setWatched(e, watched);
  }

  /// Movies and series marked as favourite, most recently added first ("Mi lista").
  List<LibraryEntry> get myList =>
      _library.values
          .where((e) => e.favorite && (e.kind == Kind.movie || e.kind == Kind.series) && !isHiddenEntry(e))
          .toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  Future<void> _save(LibraryEntry e) async {
    _library[e.key] = e;
    await db.saveEntry(e);
  }

  Future<void> _remove(String key) async {
    _library.remove(key);
    await db.deleteEntry(key);
  }

  // ---- Playing ----

  /// Null when it is fine to play; otherwise a message for the user.
  Future<String?> connectionWarning() async {
    try {
      final a = await account().timeout(const Duration(seconds: 6));
      if (a != null && a.full) {
        return 'Tu proveedor permite ${a.maxConnections} reproducciones a la vez y ya hay '
            '${a.activeConnections} en uso. Cierra VLC en otro dispositivo o espera un momento.';
      }
    } catch (_) {
      // No answer: let VLC try anyway.
    }
    return null;
  }

  Future<void> playLive(CatalogItem ch) async {
    final x = client!;
    final e = entry(Kind.live, ch.id) ?? LibraryEntry.fromCatalog(ch, now: _now, device: deviceId);
    e
      ..lastPlayed = _now
      ..updatedAt = _now
      ..device = deviceId;
    await _save(e);
    notifyListeners();
    await vlc.play(x.liveUrl(ch.id), title: ch.name);
    x.close();
  }

  Future<String?> playMovie(CatalogItem m) {
    final e = entry(Kind.movie, m.id) ?? LibraryEntry.fromCatalog(m, now: _now, device: deviceId);
    return _play(e, client!.movieUrl(m.id, m.extension));
  }

  Future<String?> playEpisode(CatalogItem series, Episode ep) =>
      _play(_episodeEntry(series, ep), client!.episodeUrl(ep.id, ep.extension));

  /// From the "Continue watching" row.
  Future<String?> resume(LibraryEntry e) {
    final x = client!;
    final url = e.kind == Kind.movie ? x.movieUrl(e.id, e.extension) : x.episodeUrl(e.id, e.extension);
    x.close();
    return _play(e, url);
  }

  /// Plays in VLC and saves where the user stopped. Returns a short note for
  /// the user about what was saved.
  Future<String?> _play(LibraryEntry e, String url) async {
    if (e.kind == Kind.movie && e.durationSecs == 0) {
      // Remember the length: it helps to find the movie again after a list change.
      final x = client!;
      try {
        e.durationSecs = (await x.movieInfo(e.id).timeout(const Duration(seconds: 5))).durationSecs;
      } catch (_) {
      } finally {
        x.close();
      }
    }
    final start = resumeFrom(e.positionSecs, e.durationSecs, watched: e.watched);
    e
      ..lastPlayed = _now
      ..updatedAt = _now
      ..device = deviceId;
    if (e.watched) e.watched = false; // watching again
    await _save(e);
    notifyListeners();

    final r = await vlc.play(url, title: e.title, startSecs: start);
    // VLC did not report: keep what we had and say so.
    if (r == null || r.positionSecs == null) {
      final info = r == null || r.info.isEmpty ? '' : ' (${r.info})';
      return 'VLC no avisó hasta dónde viste; el avance no se guardó.$info';
    }
    applyResult(e, r);
    e
      ..updatedAt = _now
      ..device = deviceId;
    await _save(e);
    notifyListeners();
    if (e.watched) return 'Marcado como visto.';
    return e.durationSecs > 0
        ? 'Guardado: vas en ${formatTime(e.positionSecs)} de ${formatTime(e.durationSecs)}.'
        : 'Guardado: vas en ${formatTime(e.positionSecs)}.';
  }

  // ---- Folders with PIN ----

  static const _pinKey = 'folder_pin';
  static const _lockedKey = 'locked_folders';

  String? _pin;
  Set<String> _locked = {};
  final Set<String> _unlocked = {};
  Set<String> _hiddenKeys = {};

  bool get hasPin => _pin != null;
  int get lockedCount => _locked.length;

  static String folderKey(Category c) => '${c.kind.name}:${c.id}';

  bool isProtected(Category c) => _locked.contains(folderKey(c));

  /// Protected and not opened with the PIN since the app started.
  bool isLocked(Category c) => isProtected(c) && !_unlocked.contains(folderKey(c));

  bool isHiddenItem(CatalogItem it) {
    final k = '${it.kind.name}:${it.categoryId}';
    return (_locked.contains(k) && !_unlocked.contains(k)) || _hiddenKeys.contains(LibraryEntry.keyOf(it.kind, it.id));
  }

  bool isHiddenEntry(LibraryEntry e) => e.kind == Kind.episode
      ? _hiddenKeys.contains(LibraryEntry.keyOf(Kind.series, e.seriesId))
      : _hiddenKeys.contains(e.key);

  Future<void> _loadLocks() async {
    try {
      _pin = await _storage.read(key: _pinKey);
    } catch (_) {
      _pin = null;
    }
    _locked = (prefs.getStringList(_lockedKey) ?? const []).toSet();
    await _refreshHidden();
  }

  /// Library keys of everything inside folders that are locked right now.
  Future<void> _refreshHidden() async {
    final keys = <String>{};
    for (final f in _locked.difference(_unlocked)) {
      final i = f.indexOf(':');
      final kind = Kind.values.byName(f.substring(0, i));
      for (final id in await db.idsIn(kind, f.substring(i + 1))) {
        keys.add(LibraryEntry.keyOf(kind, id));
      }
    }
    _hiddenKeys = keys;
  }

  bool checkPin(String pin) => _pin != null && pin == _pin;

  static bool validPin(String pin) => RegExp(r'^\d{4}$').hasMatch(pin);

  Future<void> setPin(String pin) async {
    assert(validPin(pin));
    await _storage.write(key: _pinKey, value: pin);
    _pin = pin;
    notifyListeners();
  }

  /// "Olvidé el PIN": the IPTV password proves it is the owner.
  bool checkAccountPassword(String password) => creds != null && password == creds!.password;

  Future<void> setProtected(Category c, bool protect) async {
    final k = folderKey(c);
    protect ? _locked.add(k) : _locked.remove(k);
    if (protect) _unlocked.remove(k);
    await prefs.setStringList(_lockedKey, _locked.toList()..sort());
    await _refreshHidden();
    notifyListeners();
  }

  /// Opens a protected folder until the app closes or [lockAll] runs.
  Future<bool> unlock(Category c, String pin) async {
    if (!checkPin(pin)) return false;
    _unlocked.add(folderKey(c));
    await _refreshHidden();
    notifyListeners();
    return true;
  }

  Future<void> lockAll() async {
    if (_unlocked.isEmpty) return;
    _unlocked.clear();
    await _refreshHidden();
    notifyListeners();
  }

  @visibleForTesting
  static void applyResult(LibraryEntry e, PlayResult r) {
    if (r.durationSecs != null && r.durationSecs! > 0) e.durationSecs = r.durationSecs!;
    if (r.positionSecs != null && r.positionSecs! >= 0) e.positionSecs = r.positionSecs!;
    e.watched = isWatched(e.positionSecs, e.durationSecs);
  }
}

/// Downloads and parses one list in another isolate, so that a big list does
/// not freeze the screen. Top-level so the closure only carries [c] and [kind].
Future<(List<Category>, List<CatalogItem>)> downloadKind(Credentials c, Kind kind) => Isolate.run(() async {
  final x = XtreamClient(c);
  try {
    return (await x.categories(kind), await x.items(kind));
  } finally {
    x.close();
  }
});
