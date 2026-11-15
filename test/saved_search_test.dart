// 2.2.0: the full guide (XMLTV), saved searches with filters, channels that
// work or not, and the progress bar of a programme.
import 'dart:async';

import 'package:eterotv/data/database.dart';
import 'package:eterotv/data/profiles.dart';
import 'package:eterotv/iptv/xmltv.dart';
import 'package:eterotv/iptv/xtream.dart';
import 'package:eterotv/logic/saved_search.dart';
import 'package:eterotv/player/vlc.dart';
import 'package:eterotv/state/app_state.dart';
import 'package:eterotv/ui/browse_screen.dart' show programmeProgress;
import 'package:eterotv/ui/search_screen.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _NoPlayer extends VlcLauncher {
  @override
  Future<bool> available() async => true;
  @override
  Future<PlayResult?> play(
    String url, {
    required String title,
    int startSecs = 0,
    void Function(int, int)? onProgress,
  }) async => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  group('XMLTV', () {
    test('times with and without offset', () {
      expect(parseXmltvTime('20261115160000 +0000'), DateTime.utc(2026, 11, 15, 16).millisecondsSinceEpoch);
      expect(parseXmltvTime('20261115170000 +0100'), DateTime.utc(2026, 11, 15, 16).millisecondsSinceEpoch);
      expect(parseXmltvTime('20261115110000 -0500'), DateTime.utc(2026, 11, 15, 16).millisecondsSinceEpoch);
      expect(parseXmltvTime('202611151600'), DateTime.utc(2026, 11, 15, 16).millisecondsSinceEpoch);
      expect(parseXmltvTime('nada'), isNull);
    });

    test('read in small pieces: only the window and the channels of the list', () {
      const xml = '''<?xml version="1.0" encoding="UTF-8"?>
<tv><channel id="dazn1.es"><display-name>DAZN 1</display-name></channel>
<programme start="20261115150000 +0000" stop="20261115170000 +0000" channel="dazn1.es">
  <title lang="es">LaLiga: Real Madrid &amp; Barça</title><desc>Fútbol</desc></programme>
<programme start="20261115170000 +0000" stop="20261115190000 +0000" channel="dazn1.es"><title>Después</title></programme>
<programme start="20261114100000 +0000" stop="20261114110000 +0000" channel="dazn1.es"><title>Ayer</title></programme>
<programme start="20261115150000 +0000" stop="20261115170000 +0000" channel="otro"><title>No está en la lista</title></programme>
<programme start='20261115150000 +0000' stop='20261115170000 +0000' channel='la1.es'><title><![CDATA[Telediario]]></title></programme>
</tv>''';
      final scan = XmltvScanner(
        from: DateTime.utc(2026, 11, 15, 16).millisecondsSinceEpoch,
        to: DateTime.utc(2026, 11, 16).millisecondsSinceEpoch,
        channels: {'dazn1.es', 'la1.es'},
      );
      for (var i = 0; i < xml.length; i += 7) {
        scan.add(xml.substring(i, i + 7 > xml.length ? xml.length : i + 7));
      }
      expect(
        [for (final r in scan.rows) (r.channel, r.title)],
        [('dazn1.es', 'LaLiga: Real Madrid & Barça'), ('dazn1.es', 'Después'), ('la1.es', 'Telediario')],
      );
    });
  });

  group('SavedSearch', () {
    test('json both ways, and the example', () {
      final s = SavedSearch.example();
      final back = SavedSearch.fromJson(s.toJson());
      expect(back.sameAs(s), isTrue);
      expect(back.name, 'Real Madrid Vivo');
      expect(back.kind, Kind.live);
      expect(back.filters, {SearchFilter.active});
      expect(back.inGuide && back.guideFirst, isTrue);
      expect(back.updatedAt, 1, reason: 'any real change wins over the example');
    });

    test('filters', () {
      final movie = CatalogItem(kind: Kind.movie, id: 'm', name: 'Película HD', categoryId: '');
      final ch = CatalogItem(kind: Kind.live, id: 'c', name: 'DAZN 1 FHD', categoryId: '');
      const none = ItemState();
      expect(
        passesFilters(
          SavedSearch(id: '', filters: {SearchFilter.active}),
          movie,
          state: none,
        ),
        isFalse,
      );
      expect(
        passesFilters(
          SavedSearch(id: '', filters: {SearchFilter.active}),
          ch,
          state: none,
        ),
        isTrue,
      );
      expect(
        passesFilters(
          SavedSearch(id: '', filters: {SearchFilter.active}),
          ch,
          state: none,
          down: true,
        ),
        isFalse,
      );
      expect(
        passesFilters(
          SavedSearch(id: '', quality: Quality.fhd),
          ch,
          state: none,
        ),
        isTrue,
      );
      expect(
        passesFilters(
          SavedSearch(id: '', quality: Quality.hd),
          ch,
          state: none,
        ),
        isFalse,
      );
      expect(
        passesFilters(
          SavedSearch(id: '', filters: {SearchFilter.neverSeen}),
          movie,
          state: none,
        ),
        isTrue,
      );
      expect(
        passesFilters(
          SavedSearch(id: '', filters: {SearchFilter.seen}),
          movie,
          state: const ItemState(seen: true, started: true),
        ),
        isTrue,
      );
      expect(
        passesFilters(
          SavedSearch(id: '', kind: Kind.series),
          movie,
          state: none,
        ),
        isFalse,
      );
      expect(
        passesFilters(
          SavedSearch(id: '', filters: {SearchFilter.onNow}),
          ch,
          state: none,
          onNow: true,
        ),
        isTrue,
      );
    });

    test('merge: the newest change wins, a deletion too', () {
      final local = {
        'p0': {'a': SavedSearch(id: 'a', name: 'A', updatedAt: 5)},
      };
      final n = mergeSaved(local, {
        'p0': {
          'a': SavedSearch(id: 'a', name: 'A', updatedAt: 9, deleted: true),
          'b': SavedSearch(id: 'b', name: 'B', updatedAt: 2),
        },
        'p1': {'c': SavedSearch(id: 'c', name: 'C', updatedAt: 3)},
      });
      expect(n, 3);
      expect(local['p0']!['a']!.deleted, isTrue);
      expect(local['p1']!['c']!.name, 'C');
      expect(
        mergeSaved(local, {
          'p0': {'a': SavedSearch(id: 'a', name: 'viejo', updatedAt: 4)},
        }),
        0,
      );
    });

    test('programme progress', () {
      final e = EpgEntry(title: 'x', start: DateTime(2026, 1, 1, 10), end: DateTime(2026, 1, 1, 11));
      expect(programmeProgress(e, DateTime(2026, 1, 1, 10, 24)), closeTo(0.4, 0.001));
      expect(programmeProgress(e, DateTime(2026, 1, 1, 12)), 1);
    });
  });

  test('probeLive: video arriving is up, an error or nothing is down, 509 is unknown', () async {
    final creds = Credentials(server: 'http://x:8080', username: 'u', password: 'p');
    Future<bool?> probe(int status, List<int> body) => XtreamClient(
      creds,
      client: MockClient.streaming((req, _) async {
        expect(req.url.path, '/live/u/p/7.ts');
        return http.StreamedResponse(Stream.value(body), status);
      }),
    ).probeLive('7', wait: const Duration(seconds: 1));
    expect(await probe(200, List.filled(2000, 0x47)), isTrue);
    expect(await probe(200, const []), isFalse);
    expect(await probe(404, const []), isFalse);
    expect(await probe(509, const []), isNull);
  });

  group('AppState', () {
    late AppState s;
    late AppDatabase db;
    final now = DateTime.now();
    final dazn = CatalogItem(kind: Kind.live, id: '1', name: 'DAZN LaLiga', categoryId: 'd', epgId: 'dazn.es');
    final rmtv = CatalogItem(kind: Kind.live, id: '2', name: 'Real Madrid TV', categoryId: 'd', epgId: '');
    final news = CatalogItem(kind: Kind.live, id: '3', name: 'Noticias 24', categoryId: 'd', epgId: 'n24.es');
    final caido = CatalogItem(kind: Kind.live, id: '4', name: 'Real Madrid Plus', categoryId: 'd', epgId: 'rmp.es');

    setUp(() async {
      SharedPreferences.setMockInitialValues({'lastRefresh': now.millisecondsSinceEpoch});
      FlutterSecureStorage.setMockInitialValues({});
      db = AppDatabase(
        await databaseFactoryFfi.openDatabase(
          inMemoryDatabasePath,
          options: OpenDatabaseOptions(singleInstance: false),
        ),
      );
      await AppDatabase.createTables(db.db);
      await db.replaceCatalog(Kind.live, [Category(Kind.live, 'd', 'Deportes')], [rmtv, dazn, news, caido]);
      await db.replaceCatalog(
        Kind.movie,
        [Category(Kind.movie, 'm', 'Cine')],
        [CatalogItem(kind: Kind.movie, id: 'm1', name: 'Real Madrid: la película', categoryId: 'm')],
      );
      final p = _NoPlayer();
      s = AppState(db: db, prefs: await SharedPreferences.getInstance(), deviceId: 't', vlc: p, own: p);
      await s.init();
    });

    Future<void> guide() => s.ensureGuide(
      fetch: (from, to, ids) async {
        expect(ids, containsAll(['dazn.es', 'n24.es']));
        final a = now.subtract(const Duration(minutes: 30)).millisecondsSinceEpoch;
        final b = now.add(const Duration(minutes: 60)).millisecondsSinceEpoch;
        return [
          GuideRow('dazn.es', a, b, 'LaLiga: Real Madrid - Sevilla'),
          GuideRow('n24.es', a, b, 'Telediario'),
          GuideRow('rmp.es', a, b, 'Real Madrid: Previa'),
        ];
      },
    );

    test('every profile gets «Real Madrid Vivo» once; deleting it keeps it away', () async {
      expect(s.savedSearches.map((x) => x.name), ['Real Madrid Vivo']);
      await s.deleteSearch(SavedSearch.exampleId);
      expect(s.savedSearches, isEmpty);
      final p = await s.addProfile('Niños', '🐶');
      await s.selectProfile(p!.id);
      expect(s.savedSearches.map((x) => x.name), ['Real Madrid Vivo']);
      await s.selectProfile(defaultProfile);
      expect(s.savedSearches, isEmpty);
    });

    test('«Real Madrid Vivo»: name or what is on now, not the down ones, the ones with the bar first', () async {
      await guide();
      await s.markChannel('4', false);
      final r = await s.runSearch(SavedSearch.example());
      expect(r.map((c) => c.name), ['DAZN LaLiga', 'Real Madrid TV']);
      expect(s.onNowIds, contains('1'));
      // Without the guide only the names count.
      final names = await s.runSearch(SavedSearch.example()..inGuide = false);
      expect(names.map((c) => c.name), ['Real Madrid TV']);
    });

    test('filters without words pick from the library', () async {
      final m = (await db.search('pelicula')).single;
      await s.toggleFavorite(m);
      final r = await s.runSearch(SavedSearch(id: '', filters: {SearchFilter.myList}));
      expect(r.map((c) => c.id), ['m1']);
      final none = await s.runSearch(SavedSearch(id: '', kind: Kind.live, filters: {SearchFilter.myList}));
      expect(none, isEmpty);
    });

    test('saved searches and channel marks travel with the snapshot', () async {
      final mine = SavedSearch(id: s.newSearchId(), name: 'Noticias', text: 'noticias', kind: Kind.live);
      await s.saveSearch(mine);
      await s.markChannel('3', false);
      final snap = s.exportSnapshot();

      SharedPreferences.setMockInitialValues({});
      final p = _NoPlayer();
      final other = AppState(db: db, prefs: await SharedPreferences.getInstance(), deviceId: 'o', vlc: p, own: p);
      await other.init();
      expect(await other.mergeSnapshot(snap), greaterThan(0));
      expect(other.savedSearches.map((x) => x.name), containsAll(['Noticias', 'Real Madrid Vivo']));
      expect(other.channelStatus('3'), ChannelStatus.down);
    });

    test('a channel is checked once; a recent mark is not checked again', () async {
      var asked = 0;
      Future<bool?> probe(String id) async {
        asked++;
        return true;
      }

      await s.probeChannel('1', probe: probe);
      expect(s.channelStatus('1'), ChannelStatus.up);
      await s.probeChannel('1', probe: probe);
      expect(asked, 1);
      // Unknown (connection limit): no mark.
      await s.probeChannel('3', probe: (_) async => null);
      expect(s.channelStatus('3'), ChannelStatus.unknown);
    });

    test('the short guide comes from the full one when there is one', () async {
      await guide();
      final g = await s.epgFor('1', epgId: 'dazn.es');
      expect(g.first.title, 'LaLiga: Real Madrid - Sevilla');
    });

    testWidgets('Buscar: elegir «Real Madrid Vivo», guardar otra y borrarla', (tester) async {
      await tester.runAsync(guide);
      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: s,
          child: const MaterialApp(home: SearchScreen(autofocus: false)),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('Real Madrid Vivo'));
      for (var i = 0; i < 5; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pump();
      }
      expect(find.text('DAZN LaLiga'), findsOneWidget);
      expect(find.text('Real Madrid TV'), findsOneWidget);
      expect(find.text('Noticias 24'), findsNothing);

      await tester.enterText(find.byType(TextField), 'noticias');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump();
      await tester.tap(find.text('Guardar búsqueda'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'Noticias');
      await tester.tap(find.text('Guardar'));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pumpAndSettle();
      expect(s.savedSearches.map((x) => x.name), ['Noticias', 'Real Madrid Vivo']);
      expect(s.savedSearches.first.text, 'noticias');
      expect(s.savedSearches.first.filters, {SearchFilter.active}, reason: 'kept the filters it came from');

      await tester.longPress(find.text('Noticias').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Borrar esta búsqueda'));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pumpAndSettle();
      expect(s.savedSearches.map((x) => x.name), ['Real Madrid Vivo']);
    });
  });
}
