// Drives the screens with the arrows of a TV remote, with a catalog the
// size of a real one, and checks that the focus is always somewhere visible.
import 'dart:io';

import 'package:eterotv/data/database.dart';
import 'package:eterotv/data/library.dart';
import 'package:eterotv/iptv/xtream.dart';
import 'package:eterotv/platform/device.dart';
import 'package:eterotv/player/vlc.dart';
import 'package:eterotv/state/app_state.dart';
import 'package:eterotv/sync/sync_service.dart';
import 'package:eterotv/ui/browse_screen.dart';
import 'package:eterotv/ui/cards.dart';
import 'package:eterotv/ui/home_screen.dart';
import 'package:eterotv/ui/theme.dart';
import 'package:eterotv/ui/tv_focus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
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

Future<void> _font(String family, String path) async {
  final f = File(path);
  if (!f.existsSync()) return;
  final loader = FontLoader(family)..addFont(Future.value(ByteData.sublistView(f.readAsBytesSync())));
  await loader.load();
}

/// A TV at 1080p is 960×540 for Flutter (density 2).
const tv = Size(960, 540);

void main() {
  sqfliteFfiInit();

  Future<AppState> bigCatalog() async {
    await _font('Roboto', '/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf');
    await _font('MaterialIcons', '/opt/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
    SharedPreferences.setMockInitialValues({'lastRefresh': 1});
    final db = AppDatabase(
      await databaseFactoryFfi.openDatabase(inMemoryDatabasePath, options: OpenDatabaseOptions(singleInstance: false)),
    );
    await AppDatabase.createTables(db.db);
    for (final (kind, p) in [(Kind.series, 's'), (Kind.movie, 'm')]) {
      await db.replaceCatalog(
        kind,
        [for (var c = 0; c < 12; c++) Category(kind, '$p$c', 'Categoría $p$c')],
        [
          for (var c = 0; c < 12; c++)
            for (var i = 0; i < 60; i++)
              CatalogItem(kind: kind, id: '$p$c-$i', name: 'Título $p$c-$i', categoryId: '$p$c'),
        ],
      );
    }
    await db.replaceCatalog(
      Kind.live,
      [Category(Kind.live, 'l1', 'Noticias')],
      [for (var i = 0; i < 30; i++) CatalogItem(kind: Kind.live, id: 'c$i', name: 'Canal $i', categoryId: 'l1')],
    );
    final now = DateTime.now().millisecondsSinceEpoch;
    for (var i = 0; i < 12; i++) {
      await db.saveEntry(
        LibraryEntry(
          kind: Kind.movie,
          id: 'm1-$i',
          name: 'Título m1-$i',
          positionSecs: 600,
          durationSecs: 6000,
          lastPlayed: now - i,
          updatedAt: now,
          favorite: true,
        ),
      );
      await db.saveEntry(
        LibraryEntry(kind: Kind.series, id: 's2-$i', name: 'Título s2-$i', favorite: true, updatedAt: now),
      );
    }
    final st = AppState(db: db, prefs: await SharedPreferences.getInstance(), deviceId: 't', vlc: _NoVlc());
    for (final e in await db.library()) {
      st.debugAdd(e);
    }
    return st;
  }

  late AppState state;

  Future<void> wait(WidgetTester tester) async {
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
      await tester.pump(const Duration(milliseconds: 300));
    }
  }

  Future<void> open(WidgetTester tester, Widget home) async {
    await tester.runAsync(() async => state = await bigCatalog());
    tester.view.physicalSize = tv;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: state),
          ChangeNotifierProvider.value(value: SyncService(state)),
        ],
        child: MaterialApp(theme: eteroTheme(), actions: tvActions, home: home),
      ),
    );
    await wait(tester);
    await wait(tester);
  }

  FocusNode focus() => FocusManager.instance.primaryFocus!;
  bool inRail() => focus().context!.findAncestorWidgetOfExactType<NavigationRail>() != null;
  String label() {
    final t = focus().context!.findAncestorWidgetOfExactType<Tooltip>()?.message;
    final texts = <String>[];
    void visit(Element e) {
      final w = e.widget;
      if (w is Text && w.data != null) texts.add(w.data!);
      e.visitChildren(visit);
    }

    (focus().context! as Element).visitChildren(visit);
    return texts.isEmpty ? (t ?? '?') : texts.first;
  }

  Future<void> press(WidgetTester tester, LogicalKeyboardKey k, String why) async {
    await tester.sendKeyEvent(k);
    await tester.pump();
    await wait(tester);
    expect(focus(), isNot(isA<FocusScopeNode>()), reason: '$why: nada tiene el foco');
    final r = focus().rect;
    expect(
      (Offset.zero & tv).contains(r.center),
      isTrue,
      reason: '$why: el foco quedó fuera de la pantalla ($r, ${label()})',
    );
  }

  testWidgets('Inicio: bajar y subir por todas las filas, también desde la derecha', (tester) async {
    await open(tester, const HomeScreen());
    final down = <String>[];
    for (var i = 0; i < 16; i++) {
      await press(tester, LogicalKeyboardKey.arrowDown, 'abajo $i');
      if (i > 0 && i.isEven && down.last != label()) {
        // Down from the middle of a row: the first item of the row below.
        expect(focus().rect.left, lessThan(200), reason: 'abajo $i: primer elemento (${label()})');
      }
      if (i.isOdd) {
        for (var j = 0; j < 7; j++) {
          await press(tester, LogicalKeyboardKey.arrowRight, 'derecha $i.$j');
        }
      }
      expect(inRail(), isFalse);
      down.add(label());
    }
    expect(down.toSet().length, greaterThan(10), reason: 'bajó fila por fila: $down');
    // Up: from a row to its «Ver todo», then to the first item of the row
    // above (Jose's idea, 2026-11-10).
    final ups = <String>[];
    for (var i = 0; i < 40 && focus().context!.findAncestorWidgetOfExactType<HeroBanner>() == null; i++) {
      final wasCard = label() != 'Ver todo';
      await press(tester, LogicalKeyboardKey.arrowUp, 'arriba $i');
      expect(inRail(), isFalse, reason: 'arriba no salta al menú');
      ups.add(label());
      if (!wasCard) {
        // Came from «Ver todo»: first item of the row above.
        final r = focus().rect;
        expect(r.left, lessThan(200), reason: 'primer elemento de la fila de arriba (${label()}, $r)');
      }
    }
    expect(focus().context!.findAncestorWidgetOfExactType<HeroBanner>(), isNotNull, reason: 'llegó arriba: $ups');
    expect(label(), startsWith('Continuar'), reason: 'el primer botón del destacado');
    expect(ups.where((l) => l == 'Ver todo').length, greaterThan(5), reason: 'pasó por los «Ver todo»: $ups');
    // At the end of a row, right reaches its «Ver todo», and down leaves it.
    // Down to the first category row (Mi lista has no «Ver todo»).
    for (var i = 0; i < 6; i++) {
      await press(tester, LogicalKeyboardKey.arrowDown, 'abajo a una fila');
    }
    for (var i = 0; i < 25 && label() != 'Ver todo'; i++) {
      await press(tester, LogicalKeyboardKey.arrowRight, 'hasta el final de la fila');
    }
    expect(label(), 'Ver todo');
    await press(tester, LogicalKeyboardKey.arrowDown, 'abajo desde Ver todo');
    expect(label(), isNot('Ver todo'));
  });

  testWidgets('Inicio: si el elemento enfocado desaparece, una flecha devuelve el foco', (tester) async {
    await open(tester, const HomeScreen());
    await press(tester, LogicalKeyboardKey.arrowDown, 'abajo');
    focus().unfocus();
    await tester.pump();
    expect(focus(), isA<FocusScopeNode>());
    await press(tester, LogicalKeyboardKey.arrowDown, 'flecha sin foco');
  });

  testWidgets('Ajustes y el menú de un póster se manejan con las flechas', (tester) async {
    await open(tester, const HomeScreen());
    for (var i = 0; i < 4 && !inRail(); i++) {
      await press(tester, LogicalKeyboardKey.arrowLeft, 'izquierda');
    }
    await tester.tap(find.byTooltip('Ajustes'));
    await wait(tester);
    await press(tester, LogicalKeyboardKey.arrowDown, 'Ajustes: abajo');
    final first = focus();
    await press(tester, LogicalKeyboardKey.arrowDown, 'Ajustes: abajo otra vez');
    expect(focus(), isNot(first));
    await tester.binding.handlePopRoute();
    await wait(tester);
    // Hold OK on a card of «Continuar viendo»: its menu takes the arrows.
    await press(tester, LogicalKeyboardKey.arrowRight, 'al contenido');
    await press(tester, LogicalKeyboardKey.arrowDown, 'a Continuar viendo');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
    await tester.pump(const Duration(milliseconds: 700));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
    await wait(tester);
    expect(find.text('Ver ficha'), findsOneWidget);
    expect(label(), 'Ver ficha');
    await press(tester, LogicalKeyboardKey.arrowDown, 'menú: abajo');
    expect(label(), isNot('Ver ficha'));
  });

  testWidgets('Buscar en una carpeta: se llega a «Solo en…» y «En todo…» y se cambia entre ellos', (tester) async {
    runningOnTv = true;
    addTearDown(() => runningOnTv = false);
    await open(tester, ItemsScreen(category: Category(Kind.live, 'l1', 'Noticias')));
    for (var i = 0; i < 3 && focus().context!.findAncestorWidgetOfExactType<TextField>() == null; i++) {
      await press(tester, LogicalKeyboardKey.arrowUp, 'arriba al buscador');
    }
    expect(focus().context!.findAncestorWidgetOfExactType<TextField>(), isNotNull);
    await press(tester, LogicalKeyboardKey.select, 'OK para escribir');
    await tester.enterText(find.byType(TextField), 'canal');
    await wait(tester);
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await wait(tester);
    await press(tester, LogicalKeyboardKey.arrowDown, 'abajo a las opciones');
    final a = label();
    expect(a, startsWith('Solo en'));
    await press(tester, LogicalKeyboardKey.arrowRight, 'a «En todo»');
    expect(label(), startsWith('En todo'));
    await press(tester, LogicalKeyboardKey.select, 'elegir «En todo»');
    await press(tester, LogicalKeyboardKey.arrowLeft, 'de vuelta');
    expect(label(), a);
    await press(tester, LogicalKeyboardKey.arrowDown, 'a los resultados');
    expect(label(), startsWith('Canal'));
  });

  testWidgets('Buscar desde el menú: el cursor queda listo y se elige dónde buscar', (tester) async {
    runningOnTv = true;
    addTearDown(() => runningOnTv = false);
    await open(tester, const HomeScreen());
    await tester.tap(find.text('Buscar').last);
    await wait(tester);
    expect(focus().context!.findAncestorWidgetOfExactType<TextField>(), isNotNull, reason: label());
    expect(tester.widget<TextField>(find.byType(TextField).last).readOnly, isFalse, reason: 'listo para escribir');
    expect(find.text('Películas'), findsOneWidget, reason: 'sin texto no hay opciones (solo el menú)');
    await tester.enterText(find.byType(TextField).last, 'título m1');
    await wait(tester);
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await wait(tester);
    await press(tester, LogicalKeyboardKey.arrowDown, 'abajo a las opciones');
    for (var i = 0; i < 3 && label() != 'Todo'; i++) {
      await press(tester, LogicalKeyboardKey.arrowLeft, 'a Todo');
    }
    expect(label(), 'Todo');
    await press(tester, LogicalKeyboardKey.arrowRight, 'a Series');
    expect(label(), 'Series');
    await press(tester, LogicalKeyboardKey.select, 'solo series');
    await wait(tester);
    expect(find.textContaining('Título m1'), findsNothing, reason: 'solo series');
    await press(tester, LogicalKeyboardKey.arrowRight, 'a Películas');
    await press(tester, LogicalKeyboardKey.select, 'solo películas');
    await wait(tester);
    expect(find.textContaining('Título m1'), findsWidgets);
  });

  testWidgets('Series: subir pasa por cada fila antes de «Carpetas y búsqueda»', (tester) async {
    await open(tester, const HomeScreen());
    // To the side menu, down to Series, and back into the page.
    for (var i = 0; i < 4 && !inRail(); i++) {
      await press(tester, LogicalKeyboardKey.arrowLeft, 'izquierda');
    }
    expect(inRail(), isTrue);
    await tester.tap(find.text('Series').last);
    await wait(tester);
    await press(tester, LogicalKeyboardKey.arrowRight, 'al contenido');
    for (var i = 0; i < 8; i++) {
      await press(tester, LogicalKeyboardKey.arrowDown, 'abajo $i');
    }
    final ups = <String>[];
    for (var i = 0; i < 12 && label() != 'Carpetas y búsqueda'; i++) {
      await press(tester, LogicalKeyboardKey.arrowUp, 'arriba $i');
      ups.add(label());
    }
    expect(ups.length, greaterThanOrEqualTo(8), reason: 'subió fila por fila: $ups');
  });

  testWidgets('Carpeta: subir por la cuadrícula llega a la primera fila antes que a «Buscar»', (tester) async {
    await open(tester, const BrowseScreen(kind: Kind.series));
    // Down the folder list to a big folder, then into its grid.
    for (var i = 0; i < 3; i++) {
      await press(tester, LogicalKeyboardKey.arrowDown, 'carpetas $i');
    }
    await press(tester, LogicalKeyboardKey.arrowRight, 'a la cuadrícula');
    while (focus().context!.findAncestorWidgetOfExactType<GridView>() == null) {
      await press(tester, LogicalKeyboardKey.arrowDown, 'hasta la cuadrícula');
    }
    final first = label();
    for (var i = 0; i < 6; i++) {
      await press(tester, LogicalKeyboardKey.arrowDown, 'abajo $i');
    }
    for (var i = 0; i < 6; i++) {
      await press(tester, LogicalKeyboardKey.arrowUp, 'arriba $i');
      expect(
        focus().context!.findAncestorWidgetOfExactType<GridView>(),
        isNotNull,
        reason: 'arriba $i salió de la cuadrícula (${label()})',
      );
    }
    expect(label(), first);
  });

  // Holding the arrow or pressing it quickly (Jose, 2026-11-10: the focus
  // got lost on Inicio).
  for (final gap in [16, 50, 100]) {
    testWidgets('Inicio: subir rápido ($gap ms)', (tester) async {
      await open(tester, const HomeScreen());
      for (var i = 0; i < 18; i++) {
        await press(tester, LogicalKeyboardKey.arrowDown, 'abajo $i');
      }
      final ups = <String>[];
      for (var i = 0; i < 40; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 2)));
        await tester.pump(Duration(milliseconds: gap));
        expect(focus(), isNot(isA<FocusScopeNode>()), reason: 'arriba $i: nada tiene el foco');
        expect((Offset.zero & tv).contains(focus().rect.center), isTrue, reason: 'arriba $i: fuera (${focus().rect})');
        ups.add(label());
      }
      await wait(tester);
      expect(focus(), isNot(isA<FocusScopeNode>()));
      expect(focus().context!.findAncestorWidgetOfExactType<HeroBanner>(), isNotNull, reason: '$ups');
    });
  }
}
