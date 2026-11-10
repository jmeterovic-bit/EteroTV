// Two devices sharing "my library" through an in-memory Drive.
import 'dart:convert';

import 'package:eterotv/data/database.dart';
import 'package:eterotv/iptv/xtream.dart';
import 'package:eterotv/player/vlc.dart';
import 'package:eterotv/state/app_state.dart';
import 'package:eterotv/sync/drive_store.dart';
import 'package:eterotv/sync/google_auth.dart';
import 'package:eterotv/sync/sync_service.dart';
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

  Future<AppState> device(String id) async {
    // Each device gets fresh preferences and secure storage.
    SharedPreferences.setMockInitialValues({'lastRefresh': DateTime.now().millisecondsSinceEpoch});
    FlutterSecureStorage.setMockInitialValues({});
    final db = AppDatabase(
      await databaseFactoryFfi.openDatabase(inMemoryDatabasePath, options: OpenDatabaseOptions(singleInstance: false)),
    );
    await AppDatabase.createTables(db.db);
    await db.replaceCatalog(Kind.movie, [Category(Kind.movie, 'c', 'Cine'), adult], [movie]);
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
}
