// Seen / not seen, "Seguir viendo" and folders with PIN, on AppState.
import 'package:eterotv/data/database.dart';
import 'package:eterotv/iptv/xtream.dart';
import 'package:eterotv/player/vlc.dart';
import 'package:eterotv/state/app_state.dart';
import 'package:eterotv/ui/series_screen.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _FakeVlc extends VlcLauncher {
  PlayResult? next;
  @override
  Future<bool> available() async => true;
  @override
  Future<PlayResult?> play(
    String url, {
    required String title,
    int startSecs = 0,
    void Function(int, int)? onProgress,
  }) async => next;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late AppState s;
  late _FakeVlc vlc;
  final series = CatalogItem(kind: Kind.series, id: 'f', name: 'Foundation', categoryId: 'sf');
  Episode ep(int season, int n) =>
      Episode(id: 'e$season$n', season: season, number: n, title: 'E$n', extension: 'mkv', durationSecs: 3000);
  final info = SeriesInfo({
    1: [ep(1, 1), ep(1, 2), ep(1, 3)],
  }, '');

  setUp(() async {
    SharedPreferences.setMockInitialValues({'lastRefresh': DateTime.now().millisecondsSinceEpoch});
    FlutterSecureStorage.setMockInitialValues({});
    final db = AppDatabase(
      await databaseFactoryFfi.openDatabase(inMemoryDatabasePath, options: OpenDatabaseOptions(singleInstance: false)),
    );
    await AppDatabase.createTables(db.db);
    await db.replaceCatalog(
      Kind.series,
      [Category(Kind.series, 'sf', 'Ciencia ficción'), Category(Kind.series, 'x', 'Adultos')],
      [series, CatalogItem(kind: Kind.series, id: 'h', name: 'Oculta', categoryId: 'x')],
    );
    vlc = _FakeVlc();
    s = AppState(db: db, prefs: await SharedPreferences.getInstance(), deviceId: 't', vlc: vlc, own: vlc)
      ..creds = Credentials(server: 'http://x:8080', username: 'u', password: 'secreta');
    await s.init();
  });

  test('the own player is the default; an outside one can be chosen per device', () async {
    expect(s.useOwnPlayer, isTrue);
    await s.setUseOwnPlayer(false);
    expect(s.useOwnPlayer, isFalse);
    expect(s.player, same(s.vlc));
  });

  test('mark episodes seen without playing, and unmark', () async {
    await s.setEpisodeWatched(series, ep(1, 1), true);
    await s.setEpisodeWatched(series, ep(1, 2), true);
    expect(nextEpisode(info, s)?.number, 3);
    expect(s.isInProgress(series), isFalse, reason: 'marking is not watching');
    await s.setEpisodeWatched(series, ep(1, 1), false);
    expect(s.entry(Kind.episode, 'e11')!.watched, isFalse);
    expect(nextEpisode(info, s)?.number, 1);
  });

  test('position from VLC is saved and shown; missing position is reported', () async {
    vlc.next = PlayResult(positionSecs: 600, durationSecs: 3000);
    final note = await s.playEpisode(series, ep(1, 2));
    expect(note, contains('10:00'));
    expect(s.entry(Kind.episode, 'e12')!.positionSecs, 600);
    expect(s.inProgress(Kind.series).map((i) => i.id), ['f']);

    vlc.next = null;
    expect(await s.playEpisode(series, ep(1, 2)), contains('no avisó'));
    expect(s.entry(Kind.episode, 'e12')!.positionSecs, 600, reason: 'kept');
  });

  test('remove a series from Seguir viendo keeps what was seen', () async {
    await s.setEpisodeWatched(series, ep(1, 1), true);
    vlc.next = PlayResult(positionSecs: 600, durationSecs: 3000);
    await s.playEpisode(series, ep(1, 2));
    await s.removeFromInProgress(series);
    expect(s.inProgress(Kind.series), isEmpty);
    expect(s.continueWatching, isEmpty);
    expect(s.entry(Kind.episode, 'e11')!.watched, isTrue);
  });

  test('protected folder hides its items until the PIN opens it', () async {
    final adult = Category(Kind.series, 'x', 'Adultos');
    final hidden = CatalogItem(kind: Kind.series, id: 'h', name: 'Oculta', categoryId: 'x');
    await s.toggleFavorite(hidden);
    expect(s.favorites(Kind.series).length, 1);

    await s.setPin('1234');
    await s.setProtected(adult, true);
    expect(s.isLocked(adult), isTrue);
    expect(s.isHiddenItem(hidden), isTrue);
    expect(s.favorites(Kind.series), isEmpty);

    expect(await s.unlock(adult, '0000'), isFalse);
    expect(await s.unlock(adult, '1234'), isTrue);
    expect(s.isHiddenItem(hidden), isFalse);
    expect(s.favorites(Kind.series).length, 1);

    await s.lockAll();
    expect(s.isLocked(adult), isTrue);
    expect(s.checkAccountPassword('secreta'), isTrue);
    expect(AppState.validPin('12a4'), isFalse);
  });
}
