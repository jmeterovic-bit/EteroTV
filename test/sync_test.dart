// Two devices sharing "my library" through an in-memory Drive.
import 'dart:convert';
import 'dart:io';

import 'package:eterotv/data/database.dart';
import 'package:eterotv/data/profiles.dart';
import 'package:eterotv/iptv/xtream.dart';
import 'package:eterotv/player/vlc.dart';
import 'package:eterotv/state/app_state.dart';
import 'package:eterotv/sync/drive_store.dart';
import 'package:eterotv/sync/google_auth.dart';
import 'package:eterotv/sync/sync_service.dart';
import 'package:eterotv/ui/i18n.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _NoVlc extends VlcLauncher {
  @override
  Future<bool> available() async => false;
  @override
  Future<PlayResult?> play(
    String url, {
    required String title,
    int startSecs = 0,
    void Function(int, int)? onProgress,
  }) async => null;
}

class _MemoryDrive implements RemoteStore {
  final files = <String, String>{};
  @override
  Future<List<RemoteFile>> list() async => [for (final n in files.keys) RemoteFile(n, n)];
  @override
  Future<String> read(RemoteFile f) async => files[f.id]!;
  @override
  Future<void> write(String name, String content, {RemoteFile? existing}) async => files[name] = content;
}

class _SignedIn extends GoogleAuth {
  _SignedIn() : super(store: _NoStore());
  @override
  bool get signedIn => true;
}

class _NoStore implements TokenStore {
  @override
  Future<String?> read() async => null;
  @override
  Future<void> write(String value) async {}
  @override
  Future<void> delete() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  final movie = CatalogItem(kind: Kind.movie, id: 'm1', name: 'Dune', categoryId: 'c');
  final adult = Category(Kind.movie, 'x', 'Adultos');
  final series = CatalogItem(kind: Kind.series, id: 'f', name: 'Foundation', categoryId: 's');
  Episode ep(int n) => Episode(id: 'e$n', season: 1, number: n, title: 'E$n', extension: 'mkv', durationSecs: 3000);

  Future<AppState> device(String id) async {
    // Each device gets fresh preferences and secure storage.
    SharedPreferences.setMockInitialValues({'lastRefresh': DateTime.now().millisecondsSinceEpoch});
    FlutterSecureStorage.setMockInitialValues({});
    final db = AppDatabase(
      await databaseFactoryFfi.openDatabase(inMemoryDatabasePath, options: OpenDatabaseOptions(singleInstance: false)),
    );
    await AppDatabase.createTables(db.db);
    await db.replaceCatalog(Kind.movie, [Category(Kind.movie, 'c', 'Cine'), adult], [movie]);
    await db.replaceCatalog(Kind.series, [Category(Kind.series, 's', 'Series')], [series]);
    final s = AppState(db: db, prefs: await SharedPreferences.getInstance(), deviceId: id, vlc: _NoVlc());
    await s.init();
    return s;
  }

  test('favourite, PIN and protected folders travel; the newest change wins', () async {
    final drive = _MemoryDrive();
    final a = await device('A');
    final syncA = SyncService(a, auth: _SignedIn(), remote: drive);
    await a.toggleFavorite(movie);
    await a.setPin('4321');
    await a.setProtected(adult, true);
    await syncA.syncNow();
    expect(drive.files.keys, ['eterotv-device-A.json']);

    final b = await device('B');
    final syncB = SyncService(b, auth: _SignedIn(), remote: drive);
    await syncB.syncNow();
    expect(b.isFavorite(Kind.movie, 'm1'), isTrue);
    expect(b.checkPin('4321'), isTrue);
    expect(b.isProtected(adult), isTrue);
    expect(syncB.lastDevices, 1);

    // B changes later: B wins.
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await b.toggleFavorite(movie);
    await syncB.syncNow();
    await syncA.syncNow();
    expect(a.isFavorite(Kind.movie, 'm1'), isFalse);
  });

  test(
    '«Lo nuevo» follows the profile: one device notes, another finds the news, watching clears it everywhere',
    () async {
      final drive = _MemoryDrive();
      final a = await device('A');
      final b = await device('B');
      final syncA = SyncService(a, auth: _SignedIn(), remote: drive);
      final syncB = SyncService(b, auth: _SignedIn(), remote: drive);
      await a.setEpisodeWatched(series, ep(1), true);
      var episodes = 1;
      Future<SeriesInfo> fetch(String id) async => SeriesInfo({1: List.generate(episodes, (i) => ep(i + 1))}, '');

      await a.checkSeriesNews(fetch: fetch); // A takes note
      await syncA.syncNow();
      await syncB.syncNow();

      episodes = 2;
      await b.checkSeriesNews(fetch: fetch); // B already knows what A saw
      expect(b.whatsNew.single.$1.id, 'f');
      await syncB.syncNow();
      await syncA.syncNow();
      expect(a.whatsNew.single.$1.id, 'f', reason: 'the mark travels');

      await Future<void>.delayed(const Duration(milliseconds: 5));
      a.creds = Credentials(server: 'http://x:8080', username: 'u', password: 'p');
      await a.playEpisode(series, ep(2));
      expect(a.whatsNew, isEmpty);
      await syncA.syncNow();
      await syncB.syncNow();
      expect(b.whatsNew, isEmpty, reason: 'seen on one device, gone on the other');
    },
  );

  test('older change does not overwrite a newer one', () async {
    final drive = _MemoryDrive();
    final a = await device('A');
    final b = await device('B');
    final syncA = SyncService(a, auth: _SignedIn(), remote: drive);
    final syncB = SyncService(b, auth: _SignedIn(), remote: drive);
    await a.setMovieWatched(movie, true); // older
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await b.setMovieWatched(movie, false); // newer
    await syncA.syncNow();
    await syncB.syncNow();
    await syncA.syncNow();
    expect(a.entry(Kind.movie, 'm1')!.watched, isFalse);
    expect(b.entry(Kind.movie, 'm1')!.watched, isFalse);
  });

  test('IPTV account arrives on a new device', () async {
    final drive = _MemoryDrive();
    final a = await device('A');
    final snap = a.exportSnapshot()
      ..['creds'] = {
        'value': {'server': 'http://x:8080', 'username': 'u', 'password': 'p'},
        'at': 10,
      };
    drive.files['eterotv-device-A.json'] = jsonEncode(snap);
    final b = await device('B');
    await SyncService(b, auth: _SignedIn(), remote: drive).syncNow();
    expect(b.creds?.username, 'u');
  });

  test('account and PIN saved before 0.4.0 (no date) still reach a new device', () async {
    final drive = _MemoryDrive();
    final a = await device('A');
    // What a phone on 0.4.0-0.6.0 sent for settings saved before 0.4.0: 'at' 0.
    final snap = a.exportSnapshot()
      ..['creds'] = {
        'value': {'server': 'http://x:8080', 'username': 'u', 'password': 'p'},
        'at': 0,
      }
      ..['pin'] = {'value': '1234', 'at': 0}
      ..['locked'] = {
        'value': ['movie:x'],
        'at': 0,
      };
    drive.files['eterotv-device-A.json'] = jsonEncode(snap);
    final b = await device('B');
    await SyncService(b, auth: _SignedIn(), remote: drive).syncNow();
    expect(b.creds?.username, 'u');
    expect(b.checkPin('1234'), isTrue);
    expect(b.isProtected(adult), isTrue);
    // And from now on, settings without a date are sent as the oldest change.
    expect((b.exportSnapshot()['creds'] as Map)['at'], 1);
  });

  test('a deletion on another device removes it here, and is not brought back', () async {
    final a = await device('A');
    await a.toggleFavorite(movie);
    final at = a.entry(Kind.movie, 'm1')!.updatedAt + 1;
    final fromB = {
      'schema': AppState.snapshotSchema,
      'library': <Object>[],
      'deleted': {'movie:m1': at},
    };
    expect(await a.mergeSnapshot(fromB), 1);
    expect(a.entry(Kind.movie, 'm1'), isNull);
    // An old copy of the row (from a third device) does not resurrect it.
    final old = {
      'schema': AppState.snapshotSchema,
      'library': [
        {'key': 'movie:m1', 'kind': 'movie', 'id': 'm1', 'name': 'Dune', 'favorite': 1, 'updated_at': at - 1},
      ],
    };
    expect(await a.mergeSnapshot(old), 0);
    expect(a.entry(Kind.movie, 'm1'), isNull);
    expect(a.exportSnapshot()['deleted'], {'movie:m1': at});
  });

  test('profiles: each one has its own library, and they travel with it', () async {
    final drive = _MemoryDrive();
    final a = await device('A');
    final syncA = SyncService(a, auth: _SignedIn(), remote: drive);
    await a.editProfile(a.profileId, name: 'Jose');
    await a.toggleFavorite(movie); // Jose's
    final kid = (await a.addProfile('Sofía', 'unicorn'))!;
    await a.selectProfile(kid.id);
    expect(a.isFavorite(Kind.movie, 'm1'), isFalse, reason: 'Sofía no tiene los favoritos de Jose');
    await a.setMovieWatched(movie, true);
    await a.setUiLanguage(UiLang.fr);
    expect(uiLang, UiLang.fr);
    await syncA.syncNow();

    final b = await device('B');
    await SyncService(b, auth: _SignedIn(), remote: drive).syncNow();
    expect([for (final p in b.profiles) AppState.profileName(p)], ['Jose', 'Sofía']);
    await b.selectProfile(b.profiles.first.id);
    expect(b.isFavorite(Kind.movie, 'm1'), isTrue);
    expect(b.entry(Kind.movie, 'm1')!.watched, isFalse);
    expect(uiLang, UiLang.es);
    await b.selectProfile(kid.id);
    expect(b.entry(Kind.movie, 'm1')!.watched, isTrue);
    expect(b.isFavorite(Kind.movie, 'm1'), isFalse);
    expect(uiLang, UiLang.fr);
    uiLang = UiLang.es;

    // Removing Sofía on A removes her (and what she watched) on B.
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await a.deleteProfile(kid.id);
    expect(a.profiles.length, 1);
    await syncA.syncNow();
    await SyncService(b, auth: _SignedIn(), remote: drive).syncNow();
    expect(b.profiles.map((p) => p.name), ['Jose']);
    expect(b.profileChosen, isFalse, reason: 'B estaba en el perfil borrado: vuelve a «¿Quién va a ver?»');
    expect(b.profileId, b.profiles.first.id);
    expect(await b.db.library(), hasLength(1));
  });

  test('a snapshot from before profiles (schema 1) goes to the first profile', () async {
    final a = await device('A');
    await a.addProfile('Otra', 'cat');
    final n = await a.mergeSnapshot({
      'schema': 1,
      'library': [
        {'key': 'movie:m1', 'kind': 'movie', 'id': 'm1', 'name': 'Dune', 'favorite': 1, 'updated_at': 5},
      ],
    });
    expect(n, 1);
    await a.selectProfile(defaultProfile);
    expect(a.isFavorite(Kind.movie, 'm1'), isTrue);
  });

  test('the library from before 1.0.0 moves to the first profile', () async {
    final path = '${Directory.systemTemp.createTempSync('etero').path}/old.db';
    final old = await databaseFactoryFfi.openDatabase(path);
    await old.execute('''
      CREATE TABLE library(
        key TEXT PRIMARY KEY, kind TEXT NOT NULL, id TEXT NOT NULL,
        name TEXT, icon TEXT, ext TEXT, series_id TEXT, series_name TEXT,
        season INTEGER, episode INTEGER, tmdb_id TEXT, year TEXT, epg_id TEXT,
        favorite INTEGER, position INTEGER, duration INTEGER, watched INTEGER,
        last_played INTEGER, updated_at INTEGER, device TEXT)''');
    await old.execute('CREATE INDEX library_series ON library(series_id)');
    await old.insert('library', {'key': 'movie:m1', 'kind': 'movie', 'id': 'm1', 'name': 'Dune', 'favorite': 1});
    await old.setVersion(1);
    await old.close();
    databaseFactory = databaseFactoryFfi;
    final db = await AppDatabase.open(path);
    final rows = await db.library();
    expect(rows.single.profile, defaultProfile);
    expect(rows.single.favorite, isTrue);
    await db.db.close();
  });
}
