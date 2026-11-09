import 'package:eterotv/data/database.dart';
import 'package:eterotv/iptv/xtream.dart';
import 'package:eterotv/player/vlc.dart';
import 'package:eterotv/state/app_state.dart';
import 'package:eterotv/ui/browse_screen.dart';
import 'package:flutter/material.dart';
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

/// The database answers from another isolate: let real time pass, then draw.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump(const Duration(milliseconds: 350));
  }
}

void main() {
  sqfliteFfiInit();

  testWidgets('folders: Seguir viendo, Favoritos, categories; search here or everywhere', (tester) async {
    late AppState state;
    await tester.runAsync(() async {
      SharedPreferences.setMockInitialValues({});
      final db = AppDatabase((await databaseFactoryFfi.openDatabase(inMemoryDatabasePath)));
      await AppDatabase.createTables(db.db);
      await db.replaceCatalog(
        Kind.movie,
        [Category(Kind.movie, '1', 'Acción'), Category(Kind.movie, '2', 'Drama')],
        [
          CatalogItem(kind: Kind.movie, id: 'a', name: 'Película Uno', categoryId: '1'),
          CatalogItem(kind: Kind.movie, id: 'b', name: 'Otra cosa', categoryId: '1'),
          CatalogItem(kind: Kind.movie, id: 'c', name: 'Pelicula Dos', categoryId: '2'),
        ],
      );
      state = AppState(db: db, prefs: await SharedPreferences.getInstance(), deviceId: 't', vlc: _NoVlc());
      await state.toggleFavorite(CatalogItem(kind: Kind.movie, id: 'c', name: 'Pelicula Dos', categoryId: '2'));
    });
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: const MaterialApp(home: BrowseScreen(kind: Kind.movie)),
      ),
    );
    await settle(tester);
    expect(find.text('Seguir viendo'), findsWidgets);
    expect(find.text('Favoritos'), findsWidgets);
    expect(find.text('Acción'), findsOneWidget);

    // Open "Acción" and search only there: "pelicula" (no accent) finds "Película Uno".
    await tester.tap(find.text('Acción'));
    await settle(tester);
    await tester.enterText(find.byType(TextField).last, 'pelicula');
    await tester.pump(const Duration(milliseconds: 400));
    await settle(tester);
    expect(find.text('Película Uno'), findsOneWidget);
    expect(find.text('Pelicula Dos'), findsNothing);

    // Everywhere in Películas also finds the one in Drama.
    await tester.tap(find.text('En todo Películas'));
    await settle(tester);
    expect(find.text('Pelicula Dos'), findsOneWidget);
  });
}
