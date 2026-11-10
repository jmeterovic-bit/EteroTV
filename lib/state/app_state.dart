import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:math';

import 'package:flutter/foundation.dart' hide Category;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/database.dart';
import '../data/library.dart';
import '../data/profiles.dart';
import '../iptv/xtream.dart';
import '../logic/progress.dart';
import '../logic/rematch.dart';
import '../player/own_player.dart';
import '../player/vlc.dart';
import '../ui/i18n.dart';

class AppState extends ChangeNotifier {
  AppState({required this.db, required this.prefs, required this.deviceId, VlcLauncher? vlc, VlcLauncher? own})
    : vlc = vlc ?? VlcLauncher.forPlatform(),
      own = own ?? OwnPlayer();

  final AppDatabase db;
  final SharedPreferences prefs;
  final String deviceId;

  /// The outside player: VLC, or on Android Just Player / MX Player.
  final VlcLauncher vlc;

  /// EteroTV's own player (1.1.0), the default.
  final VlcLauncher own;

  static const _ownKey = 'ownPlayer';
  static const _hwKey = 'hwDecoding';
  static const _decodeKey = 'videoDecode';

  /// This device plays with EteroTV's own player (not synced).
  bool get useOwnPlayer => prefs.getBool(_ownKey) ?? true;

  /// The player in use on this device.
  VlcLauncher get player => useOwnPlayer ? own : vlc;

  Future<void> setUseOwnPlayer(bool v) async {
    await prefs.setBool(_ownKey, v);
    notifyListeners();
  }

  /// Own player: how the video is decoded on this device (not synced).
  VideoDecode get videoDecode {
    final v = prefs.getString(_decodeKey);
    if (v != null) return VideoDecode.fromName(v);
    return prefs.getBool(_hwKey) == false ? VideoDecode.software : VideoDecode.auto; // 1.1.0 test build
  }

  Future<void> setVideoDecode(VideoDecode d) async {
    await prefs.setString(_decodeKey, d.name);
    final o = own;
    if (o is OwnPlayer) o.decode = d;
    notifyListeners();
  }

  static const _storage = FlutterSecureStorage();
  static const _credsKey = 'iptv_credentials';
  static const refreshEvery = Duration(hours: 24);
  static const _playerKey = 'player';

  /// Android: which player this device uses (not synced: it depends on the device).
  AndroidPlayer? get androidPlayer {
    final v = vlc;
    return v is AndroidVlc ? v.player : null;
  }

  static const _uiLangKey = 'uiLang';
  static const _audioKey = 'audioLang';
  static const _subsKey = 'subLang';

  /// The app's language, of the profile in use. Changing it rebuilds the
  /// whole app.
  UiLang get uiLanguage => uiLang;
  Future<void> setUiLanguage(UiLang l) => _editProfile((p) => p.lang = l.name);

  TrackLang get audioLang => vlc.audioLang;
  TrackLang get subLang => vlc.subLang;
  Future<void> setAudioLang(TrackLang l) => _editProfile((p) => p.audio = l.name);
  Future<void> setSubLang(TrackLang l) => _editProfile((p) => p.subs = l.name);

  // ---- Profiles (1.0.0) ----

  static const _profilesKey = 'profiles';
  static const _lastProfileKey = 'lastProfile';
  static const maxProfiles = 5;

  final Map<String, Profile> _profiles = {};

  /// The profile in use. [profileChosen] is false until someone picks one
  /// in «¿Quién va a ver?» (each time the app opens).
  String profileId = defaultProfile;
  bool profileChosen = false;

  /// The profiles, oldest first.
  List<Profile> get profiles {
    if (_profiles.values.every((p) => p.deleted)) _profiles[defaultProfile] = Profile(id: defaultProfile);
    return _profiles.values.where((p) => !p.deleted).toList()..sort((a, b) => _order(a.id, b.id));
  }

  static int _order(String a, String b) => a == defaultProfile ? -1 : (b == defaultProfile ? 1 : a.compareTo(b));

  Profile get profile => _profiles[profileId] ?? profiles.first;

  /// The name to show: the first profile may have none yet.
  static String profileName(Profile p) => p.name.isNotEmpty ? p.name : tr('Mi perfil');

  void _loadProfiles() {
    _profiles.clear();
    try {
      for (final j in (jsonDecode(prefs.getString(_profilesKey) ?? '[]') as List)) {
        final p = Profile.fromJson(Map<String, dynamic>.from(j as Map));
        _profiles[p.id] = p;
      }
    } catch (_) {}
    if (profiles.isEmpty) {
      // Before 1.0.0: one profile with what this device had, dated 0 so any
      // other device's profiles win.
      _profiles[defaultProfile] = Profile(
        id: defaultProfile,
        lang: prefs.getString(_uiLangKey) ?? UiLang.es.name,
        audio: prefs.getString(_audioKey) ?? TrackLang.original.name,
        subs: prefs.getString(_subsKey) ?? TrackLang.none.name,
      );
    }
    final last = prefs.getString(_lastProfileKey);
    profileId = _profiles[last]?.deleted == false ? last! : profiles.first.id;
    _applyProfile();
  }

  Future<void> _saveProfiles() async {
    await prefs.setString(_profilesKey, jsonEncode([for (final p in _profiles.values) p.toJson()]));
    _changed();
  }

  /// The profile's languages go to the app and the player.
  void _applyProfile() {
    final p = profile;
    uiLang = UiLang.fromName(p.lang);
    for (final v in [vlc, own]) {
      v
        ..audioLang = TrackLang.fromName(p.audio, TrackLang.original)
        ..subLang = TrackLang.fromName(p.subs, TrackLang.none);
    }
  }

  Future<void> _editProfile(void Function(Profile) edit, [String? id]) async {
    final p = _profiles[id ?? profileId];
    if (p == null) return;
    edit(p);
    p.updatedAt = _now;
    await _saveProfiles();
    if (p.id == profileId) _applyProfile();
    notifyListeners();
  }

  Future<void> selectProfile(String id) async {
    if (_profiles[id] == null || _profiles[id]!.deleted) return;
    profileId = id;
    profileChosen = true;
    await prefs.setString(_lastProfileKey, id);
    _applyProfile();
    notifyListeners();
    unawaited(_findLost());
  }

  /// Back to «¿Quién va a ver?».
  void leaveProfile() {
    profileChosen = false;
    notifyListeners();
  }

  /// A new profile, with the languages of the one in use. Null when there
  /// are already [maxProfiles].
  Future<Profile?> addProfile(String name, String avatar) async {
    if (profiles.length >= maxProfiles) return null;
    final from = profile;
    var t = _now;
    while (_profiles.containsKey('p${t.toRadixString(36)}')) {
      t++;
    }
    final p = Profile(
      id: 'p${t.toRadixString(36)}',
      name: name.trim(),
      avatar: avatar,
      lang: from.lang,
      audio: from.audio,
      subs: from.subs,
      updatedAt: _now,
    );
    _profiles[p.id] = p;
    await _saveProfiles();
    notifyListeners();
    return p;
  }

  Future<void> editProfile(String id, {String? name, String? avatar}) => _editProfile((p) {
    if (name != null) p.name = name.trim();
    if (avatar != null) p.avatar = avatar;
  }, id);

  /// Removes a profile and its favourites and progress, on every device.
  /// The last profile stays.
  Future<void> deleteProfile(String id) async {
    if (profiles.length <= 1 || _profiles[id] == null) return;
    await _editProfile((p) => p.deleted = true, id);
    await _dropProfileData(id);
    if (profileId == id) {
      profileId = profiles.first.id;
      profileChosen = false;
      _applyProfile();
    }
    notifyListeners();
  }

  Future<void> _dropProfileData(String id) async {
    _libs.remove(id);
    await db.deleteProfile(id);
  }

  Future<void> setAndroidPlayer(AndroidPlayer p) async {
    final v = vlc;
    if (v is! AndroidVlc) return;
    v.player = p;
    await prefs.setString(_playerKey, p.name);
    await prefs.setBool(_ownKey, false);
    notifyListeners();
  }

  Credentials? creds;
  XtreamClient? get client => creds == null ? null : XtreamClient(creds!);

  /// Each profile's library, by [LibraryEntry.key].
  final Map<String, Map<String, LibraryEntry>> _libs = {};

  /// The library of the profile in use.
  Map<String, LibraryEntry> get _library => _libs.putIfAbsent(profileId, () => {});

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
      _libs.putIfAbsent(e.profile, () => {})[e.key] = e;
    }
    await _loadLocks();
    final v = vlc;
    if (v is AndroidVlc) v.player = AndroidPlayer.fromName(prefs.getString(_playerKey));
    final o = own;
    if (o is OwnPlayer) o.decode = videoDecode;
    _loadProfiles();
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
    await prefs.setInt(_credsAtKey, _now);
    creds = c;
    _changed();
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
          Kind.live => tr('Descargando canales…'),
          Kind.movie => tr('Descargando películas…'),
          _ => tr('Descargando series…'),
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
  void debugAdd(LibraryEntry e) => _libs.putIfAbsent(e.profile, () => {})[e.key] = e;

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
    e.profile = profileId;
    _library[e.key] = e;
    await db.saveEntry(e);
    _changed();
  }

  Future<void> _remove(String key, {int? at}) async {
    _library.remove(key);
    await db.deleteEntry(profileId, key);
    // Remember the deletion, so other devices drop it too (and do not bring it back).
    final dead = _deleted..[_deadKey(profileId, key)] = at ?? _now;
    await prefs.setString(_deletedKey, jsonEncode(dead));
    _changed();
  }

  // ---- Sync (stage 2) ----

  static const _deletedKey = 'deletedKeys';
  static const _credsAtKey = 'credsUpdatedAt';
  static const _pinAtKey = 'pinUpdatedAt';
  static const _lockedAtKey = 'lockedUpdatedAt';

  /// 2 (1.0.0) adds profiles; a snapshot from 1 is the first profile's.
  static const snapshotSchema = 2;

  /// A deletion's key: the first profile keeps the old form.
  static String _deadKey(String profile, String key) => profile == defaultProfile ? key : '$profile|$key';
  static (String, String) _splitDead(String k) {
    final i = k.indexOf('|');
    return i < 0 ? (defaultProfile, k) : (k.substring(0, i), k.substring(i + 1));
  }

  /// Called after every local change to the library or the shared settings
  /// (the sync service uploads a few seconds later).
  VoidCallback? onLocalChange;
  bool _merging = false;

  void _changed() {
    if (!_merging) onLocalChange?.call();
  }

  Map<String, int> get _deleted {
    try {
      return (jsonDecode(prefs.getString(_deletedKey) ?? '{}') as Map<String, dynamic>).map(
        (k, v) => MapEntry(k, (v as num).toInt()),
      );
    } catch (_) {
      return {};
    }
  }

  /// Everything this device shares: "my library", the IPTV account, the PIN
  /// and the protected folders. The catalog is never shared.
  Map<String, dynamic> exportSnapshot() => {
    'schema': snapshotSchema,
    'app': 'eterotv',
    'device': deviceId,
    'library': [
      for (final lib in _libs.values)
        for (final e in lib.values) e.toRow(),
    ],
    'profiles': [for (final p in _profiles.values) p.toJson()],
    'deleted': _deleted,
    'creds': {'value': creds?.toJson(), 'at': _settingAt(_credsAtKey, creds != null)},
    'pin': {'value': _pin, 'at': _settingAt(_pinAtKey, _pin != null)},
    'locked': {'value': _locked.toList()..sort(), 'at': _settingAt(_lockedAtKey, _locked.isNotEmpty)},
  };

  /// When a shared setting was last changed. Settings saved before 0.4.0
  /// have no date: they count as the oldest (1), so they still reach a new
  /// device but any later change wins.
  int _settingAt(String key, bool hasValue) => prefs.getInt(key) ?? (hasValue ? 1 : 0);

  /// Takes what is newer in another device's snapshot. Returns how many
  /// things changed here.
  Future<int> mergeSnapshot(Map<String, dynamic> data) async {
    final schema = data['schema'];
    if (schema != snapshotSchema && schema != 1) return 0; // written by a newer version
    var n = 0;
    _merging = true;
    try {
      // Profiles first: the newest change of each wins; a removed one takes
      // its library with it.
      var profilesChanged = false;
      for (final raw in (data['profiles'] as List?) ?? const []) {
        final p = Profile.fromJson(Map<String, dynamic>.from(raw as Map));
        final local = _profiles[p.id];
        if (local != null && local.updatedAt >= p.updatedAt) continue;
        _profiles[p.id] = p;
        profilesChanged = true;
        if (p.deleted) await _dropProfileData(p.id);
        n++;
      }
      if (profilesChanged) {
        await prefs.setString(_profilesKey, jsonEncode([for (final p in _profiles.values) p.toJson()]));
        if (_profiles[profileId]?.deleted != false) {
          profileId = profiles.first.id;
          profileChosen = false;
        }
        _applyProfile();
      }
      // Deletions first, so a deleted favourite is not brought back.
      final dead = _deleted;
      var deadChanged = false;
      for (final MapEntry(:key, :value) in ((data['deleted'] as Map?) ?? const {}).entries) {
        final at = (value as num).toInt();
        if (at <= (dead[key] ?? 0)) continue;
        dead[key as String] = at;
        deadChanged = true;
        final (profile, k) = _splitDead(key);
        final local = _libs[profile]?[k];
        if (local != null && local.updatedAt <= at) {
          _libs[profile]!.remove(k);
          await db.deleteEntry(profile, k);
          n++;
        }
      }
      if (deadChanged) await prefs.setString(_deletedKey, jsonEncode(dead));
      for (final raw in (data['library'] as List?) ?? const []) {
        final e = LibraryEntry.fromRow(Map<String, Object?>.from(raw as Map));
        if (_profiles[e.profile]?.deleted ?? false) continue;
        if (e.updatedAt <= (dead[_deadKey(e.profile, e.key)] ?? 0)) continue;
        final lib = _libs.putIfAbsent(e.profile, () => {});
        final local = lib[e.key];
        if (local != null && local.updatedAt >= e.updatedAt) continue;
        lib[e.key] = e;
        await db.saveEntry(e);
        n++;
      }
      // Shared settings: the newest wins as a whole.
      int at(String k) => ((data[k] as Map?)?['at'] as num?)?.toInt() ?? 0;
      Object? value(String k) => (data[k] as Map?)?['value'];
      final remoteCreds = value('creds') is Map
          ? Credentials.fromJson(Map<String, dynamic>.from(value('creds')! as Map))
          : null;
      // A device with nothing yet takes the other one's even without a date
      // (devices still on 0.4.0-0.6.0 send 0 for settings from before 0.4.0).
      if (remoteCreds != null && (at('creds') > (prefs.getInt(_credsAtKey) ?? 0) || creds == null)) {
        final c = remoteCreds;
        await _storage.write(key: _credsKey, value: jsonEncode(c.toJson()));
        await prefs.setInt(_credsAtKey, max(at('creds'), 1));
        final first = creds == null;
        creds = c;
        n++;
        if (first || lastRefresh == null) unawaited(refreshCatalog());
      }
      if (at('pin') > (prefs.getInt(_pinAtKey) ?? 0) || (_pin == null && value('pin') is String)) {
        final pin = value('pin') as String?;
        if (pin == null) {
          await _storage.delete(key: _pinKey);
        } else {
          await _storage.write(key: _pinKey, value: pin);
        }
        _pin = pin;
        await prefs.setInt(_pinAtKey, max(at('pin'), 1));
        n++;
      }
      if (at('locked') > (prefs.getInt(_lockedAtKey) ?? 0) ||
          (_locked.isEmpty && (value('locked') as List? ?? const []).isNotEmpty)) {
        _locked = {for (final f in (value('locked') as List? ?? const [])) f as String};
        await prefs.setStringList(_lockedKey, _locked.toList()..sort());
        await prefs.setInt(_lockedAtKey, max(at('locked'), 1));
        await _refreshHidden();
        n++;
      }
    } finally {
      _merging = false;
    }
    if (n > 0) notifyListeners();
    return n;
  }

  // ---- Playing ----

  /// Null when it is fine to play; otherwise a message for the user.
  Future<String?> connectionWarning() async {
    try {
      final a = await account().timeout(const Duration(seconds: 6));
      if (a != null && a.full) {
        return tr(
          'Tu proveedor permite {0} reproducciones a la vez y ya hay {1} en uso. Cierra VLC en otro dispositivo o espera un momento.',
          [a.maxConnections, a.activeConnections],
        );
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
    final p = player;
    if (p is OwnPlayer) p.nextEpg = () => epgFor(ch.id);
    await p.play(x.liveUrl(ch.id), title: ch.name);
    x.close();
  }

  // ---- Guide (live channels) ----

  final Map<String, (DateTime, Future<List<EpgEntry>>)> _epg = {};
  int _epgRunning = 0;
  final List<Completer<void>> _epgQueue = [];

  /// Now and next of a channel, from the provider. Kept 10 minutes; at most 4
  /// requests at a time (a list shows many channels at once). Empty when the
  /// provider has no guide for it or does not answer.
  Future<List<EpgEntry>> epgFor(String channelId) {
    final hit = _epg[channelId];
    if (hit != null && DateTime.now().difference(hit.$1) < const Duration(minutes: 10)) return hit.$2;
    final f = _loadEpg(channelId);
    _epg[channelId] = (DateTime.now(), f);
    return f;
  }

  Future<List<EpgEntry>> _loadEpg(String channelId) async {
    final x = client;
    if (x == null) return [];
    if (_epgRunning >= 4) {
      final turn = Completer<void>();
      _epgQueue.add(turn);
      await turn.future;
    }
    _epgRunning++;
    try {
      return await x.shortEpg(channelId).timeout(const Duration(seconds: 15));
    } catch (_) {
      _epg.remove(channelId); // try again next time
      return [];
    } finally {
      x.close();
      _epgRunning--;
      if (_epgQueue.isNotEmpty) _epgQueue.removeAt(0).complete();
    }
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

  // ---- Next episode ----

  LibraryEntry? _upNext;

  /// Windows: set when the credits of an episode start, while VLC plays.
  final ValueNotifier<LibraryEntry?> nearEnd = ValueNotifier(null);

  /// The episode that was just finished, once (for "Siguiente episodio").
  LibraryEntry? takeUpNext() {
    final e = _upNext;
    _upNext = null;
    return e;
  }

  /// Closes VLC (Windows), e.g. to start the next episode from the credits.
  Future<void> stopPlayer() => player.stop();

  /// The episode after [e] in its series (next season included), or null.
  Future<(CatalogItem, Episode)?> nextAfter(LibraryEntry e) async {
    if (e.kind != Kind.episode || e.seriesId.isEmpty) return null;
    final x = client;
    if (x == null) return null;
    try {
      final info = await x.seriesInfo(e.seriesId).timeout(const Duration(seconds: 10));
      final all = [for (final k in (info.seasons.keys.toList()..sort())) ...info.seasons[k]!];
      final i = all.indexWhere((ep) => ep.id == e.id);
      if (i < 0 || i + 1 >= all.length) return null;
      final series =
          await db.item(Kind.series, e.seriesId) ??
          CatalogItem(
            kind: Kind.series,
            id: e.seriesId,
            name: e.seriesName,
            categoryId: '',
            icon: e.icon,
            tmdbId: e.tmdbId,
            year: e.year,
          );
      return (series, all[i + 1]);
    } catch (_) {
      return null;
    } finally {
      x.close();
    }
  }

  /// Plays and saves where the user stopped. Returns a note for the user
  /// only when the player did not say where that was.
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

    _upNext = null;
    var nearEndFired = false;
    final pl = player;
    final r = await pl.play(
      url,
      title: e.title,
      startSecs: start,
      onProgress: e.kind != Kind.episode
          ? null
          : (pos, len) {
              // Windows: credits reached while VLC is still playing.
              if (!nearEndFired && creditsReached(pos, len)) {
                nearEndFired = true;
                nearEnd.value = e;
              }
            },
    );
    // VLC did not report: keep what we had and say so.
    if (r == null || r.positionSecs == null) {
      final info = r == null || r.info.isEmpty ? '' : ' (${r.info})';
      return tr('{0} no avisó hasta dónde viste; el avance no se guardó.{1}', [pl.name, info]);
    }
    applyResult(e, r);
    e
      ..updatedAt = _now
      ..device = deviceId;
    await _save(e);
    notifyListeners();
    if (e.watched && e.kind == Kind.episode) _upNext = e;
    // No message when it went well: Jose did not want to see the time
    // after each video (2026-11-10). The list shows the progress.
    return null;
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
    await prefs.setInt(_pinAtKey, _now);
    _changed();
    notifyListeners();
  }

  /// "Olvidé el PIN": the IPTV password proves it is the owner.
  bool checkAccountPassword(String password) => creds != null && password == creds!.password;

  Future<void> setProtected(Category c, bool protect) async {
    final k = folderKey(c);
    protect ? _locked.add(k) : _locked.remove(k);
    if (protect) _unlocked.remove(k);
    await prefs.setStringList(_lockedKey, _locked.toList()..sort());
    await prefs.setInt(_lockedAtKey, _now);
    _changed();
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
