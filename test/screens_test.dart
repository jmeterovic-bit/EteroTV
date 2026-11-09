// Draws the main screens with sample data. Writes PNGs only when the
// SCREENSHOTS environment variable names a folder (for reviewing design).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:eterotv/data/database.dart';
import 'package:eterotv/data/library.dart';
import 'package:eterotv/iptv/xtream.dart';
import 'package:eterotv/player/vlc.dart';
import 'package:eterotv/state/app_state.dart';
import 'package:eterotv/ui/home_screen.dart';
import 'package:eterotv/ui/rows.dart';
import 'package:eterotv/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _NoVlc extends VlcLauncher {
  @override
  Future<bool> available() async => false;
  @override
  Future<PlayResult?> play(String url, {required String title, int startSecs = 0}) async => null;
}

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump(const Duration(milliseconds: 350));
  }
}

Future<void> _font(String family, String path) async {
  final f = File(path);
  if (!f.existsSync()) return;
  final loader = FontLoader(family)..addFont(Future.value(ByteData.sublistView(f.readAsBytesSync())));
  await loader.load();
}

void main() {
  sqfliteFfiInit();
  final out = Platform.environment['SCREENSHOTS'];

  Future<AppState> sample() async {
    SharedPreferences.setMockInitialValues({'lastRefresh': 1});
    final db = AppDatabase(
      await databaseFactoryFfi.openDatabase(inMemoryDatabasePath, options: OpenDatabaseOptions(singleInstance: false)),
    );
    await AppDatabase.createTables(db.db);
    final scifi = Category(Kind.series, 's1', 'Ciencia ficción');
    final drama = Category(Kind.series, 's2', 'Drama');
    await db.replaceCatalog(
      Kind.series,
      [scifi, drama],
      [
        for (var i = 0; i < 8; i++) CatalogItem(kind: Kind.series, id: 'sf$i', name: 'Serie $i', categoryId: 's1'),
        for (var i = 0; i < 8; i++) CatalogItem(kind: Kind.series, id: 'dr$i', name: 'Drama $i', categoryId: 's2'),
      ],
    );
    await db.replaceCatalog(
      Kind.movie,
      [Category(Kind.movie, 'm1', 'Acción')],
      [for (var i = 0; i < 8; i++) CatalogItem(kind: Kind.movie, id: 'm$i', name: 'Película $i', categoryId: 'm1')],
    );
    await db.replaceCatalog(
      Kind.live,
      [Category(Kind.live, 'l1', 'Noticias')],
      [for (var i = 0; i < 6; i++) CatalogItem(kind: Kind.live, id: 'c$i', name: 'Canal $i', categoryId: 'l1')],
    );
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.saveEntry(
      LibraryEntry(
        kind: Kind.episode,
        id: 'e1',
        name: 'Episodio',
        seriesId: 'sf1',
        seriesName: 'Foundation',
        season: 3,
        episode: 3,
        positionSecs: 1200,
        durationSecs: 3060,
        lastPlayed: now,
        updatedAt: now,
      ),
    );
    await db.saveEntry(
      LibraryEntry(
        kind: Kind.movie,
        id: 'm2',
        name: 'Dune',
        positionSecs: 2000,
        durationSecs: 9300,
        lastPlayed: now - 1000,
        updatedAt: now,
        favorite: true,
      ),
    );
    await db.saveEntry(LibraryEntry(kind: Kind.series, id: 'sf3', name: 'Serie 3', favorite: true, updatedAt: now));
    await db.saveEntry(LibraryEntry(kind: Kind.live, id: 'c1', name: 'Canal 1', favorite: true, updatedAt: now));
    final st = AppState(db: db, prefs: await SharedPreferences.getInstance(), deviceId: 't', vlc: _NoVlc());
    for (final e in await db.library()) {
      st.debugAdd(e);
    }
    return st;
  }

  for (final (name, size) in [('celular', const Size(412, 1900)), ('tv', const Size(1280, 720))]) {
    testWidgets('Inicio se dibuja ($name)', (tester) async {
      late AppState state;
      await tester.runAsync(() async {
        await _font('Roboto', '/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf');
        await _font('MaterialIcons', '/opt/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
        state = await sample();
      });
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final key = GlobalKey();
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: state,
          child: RepaintBoundary(
            key: key,
            child: MaterialApp(theme: eteroTheme(), debugShowCheckedModeBanner: false, home: const HomeScreen()),
          ),
        ),
      );
      await settle(tester);
      expect(tester.takeException(), isNull);
      expect(find.text('Continuar viendo'), findsWidgets);
      expect(find.text('Mi lista'), findsWidgets);
      if (out != null) {
        await tester.runAsync(() async {
          final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final img = await boundary.toImage();
          final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
          File('$out/inicio-$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
        });
      }
      // Series tab.
      await tester.tap(find.text('Series').last);
      await settle(tester);
      expect(tester.takeException(), isNull);
      expect(find.text('Seguir viendo'), findsWidgets);
      if (out != null) {
        await tester.runAsync(() async {
          final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final img = await boundary.toImage();
          final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
          File('$out/series-$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
        });
      }
    });
  }

  testWidgets('Series se llena cuando termina de bajar la lista', (tester) async {
    late AppState state;
    late AppDatabase db;
    await tester.runAsync(() async {
      SharedPreferences.setMockInitialValues({});
      db = AppDatabase(
        await databaseFactoryFfi.openDatabase(
          inMemoryDatabasePath,
          options: OpenDatabaseOptions(singleInstance: false),
        ),
      );
      await AppDatabase.createTables(db.db);
      state = AppState(db: db, prefs: await SharedPreferences.getInstance(), deviceId: 't', vlc: _NoVlc());
    });
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: MaterialApp(
          theme: eteroTheme(),
          home: const Scaffold(body: KindTab(kind: Kind.series)),
        ),
      ),
    );
    await settle(tester);
    expect(find.textContaining('No hay categorías'), findsOneWidget);

    // The first download finishes after the tab was built.
    await tester.runAsync(() async {
      await db.replaceCatalog(
        Kind.series,
        [Category(Kind.series, 's1', 'Ciencia ficción')],
        [CatalogItem(kind: Kind.series, id: 'a', name: 'Serie A', categoryId: 's1')],
      );
      await state.prefs.setInt('lastRefresh', 5);
      await state.toggleFavorite(CatalogItem(kind: Kind.series, id: 'a', name: 'Serie A', categoryId: 's1'));
    });
    await settle(tester);
    expect(find.text('Ciencia ficción'), findsOneWidget);
  });
}
