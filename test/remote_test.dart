import 'package:eterotv/ui/remote.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RemoteMenu', () {
    late int taps;
    late int menus;

    Future<void> pump(WidgetTester tester) async {
      taps = 0;
      menus = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RemoteMenu(
              onSelect: () => taps++,
              onMenu: () => menus++,
              child: InkWell(autofocus: true, onTap: () => taps++, child: const Text('Póster')),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('a short OK opens the item, once', (tester) async {
      await pump(tester);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
      await tester.pump();
      expect(taps, 1);
      expect(menus, 0);
    });

    testWidgets('holding OK opens the menu and not the item', (tester) async {
      await pump(tester);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.select);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
      await tester.pump();
      expect(menus, 1);
      expect(taps, 0);
    });

    testWidgets('the OK still held does not press the menu\'s first option', (tester) async {
      var picked = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => RemoteMenu(
                onSelect: () {},
                onMenu: () => showModalBottomSheet<void>(
                  context: context,
                  builder: (c) => ListTile(autofocus: true, title: const Text('Quitar'), onTap: () => picked++),
                ),
                child: InkWell(autofocus: true, onTap: () {}, child: const Text('Póster')),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      expect(find.text('Quitar'), findsOneWidget);
      for (var i = 0; i < 3; i++) {
        await tester.sendKeyRepeatEvent(LogicalKeyboardKey.select);
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(picked, 0);
      expect(find.text('Quitar'), findsOneWidget);
      // A new OK chooses it.
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(picked, 1);
    });

    testWidgets('the menu key opens the menu', (tester) async {
      await pump(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.contextMenu);
      await tester.pump();
      expect(menus, 1);
      expect(taps, 0);
    });
  });

  testWidgets('TV search field: arrows pass through, OK starts typing', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              RemoteTextField(tv: true, autofocus: true, onChanged: (_) {}),
              TextButton(onPressed: () {}, child: const Text('Abajo')),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    TextField field() => tester.widget<TextField>(find.byType(TextField));
    expect(field().readOnly, isTrue, reason: 'no keyboard while just passing through');

    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    expect(field().readOnly, isFalse);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(Focus.of(tester.element(find.text('Abajo'))).hasFocus, isTrue);
    expect(field().readOnly, isTrue, reason: 'leaving the field stops typing');
  });

  testWidgets('the player takes the whole TV screen, also when the next episode replaces it', (tester) async {
    final nav = GlobalKey<NavigatorState>();
    EdgeInsetsGeometry margin() => tester
        .widget<Padding>(find.descendant(of: find.byType(TvSafeArea), matching: find.byType(Padding)).first)
        .padding;
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: nav,
        builder: (_, child) => TvSafeArea(child: child!),
        home: const Text('Canales'),
      ),
    );
    expect(margin(), isNot(EdgeInsets.zero));

    Future<void> open(String name) async {
      nav.currentState!.push(MaterialPageRoute<void>(builder: (_) => _FakePlayer(name)));
      await tester.pumpAndSettle();
    }

    await open('T1 E1');
    expect(margin(), EdgeInsets.zero);
    // «Ver siguiente»: the episode closes and the next one opens right away.
    nav.currentState!.pop();
    nav.currentState!.push(MaterialPageRoute<void>(builder: (_) => const _FakePlayer('T1 E2')));
    await tester.pumpAndSettle();
    expect(margin(), EdgeInsets.zero);
    nav.currentState!.pop();
    await tester.pumpAndSettle();
    expect(margin(), isNot(EdgeInsets.zero), reason: 'back in the app: margins again');
    await open('T1 E3');
    expect(margin(), EdgeInsets.zero, reason: 'not stuck');
    nav.currentState!.pop();
    await tester.pumpAndSettle();
  });
}

class _FakePlayer extends StatefulWidget {
  const _FakePlayer(this.name);
  final String name;
  @override
  State<_FakePlayer> createState() => _FakePlayerState();
}

class _FakePlayerState extends State<_FakePlayer> {
  @override
  void initState() {
    super.initState();
    enterTvFullScreen();
  }

  @override
  void dispose() {
    leaveTvFullScreen();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Text(widget.name);
}
