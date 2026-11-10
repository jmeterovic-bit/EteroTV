import 'package:eterotv/iptv/xtream.dart';
import 'package:eterotv/ui/play.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final ep = Episode(
    id: 'e',
    season: 3,
    number: 4,
    title: 'The Stress of Her Regard',
    extension: 'mkv',
    durationSecs: 0,
  );

  testWidgets('starts by itself after 30 s', (tester) async {
    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (c) =>
              TextButton(onPressed: () async => result = await showNextEpisode(c, ep), child: const Text('x')),
        ),
      ),
    );
    await tester.tap(find.text('x'));
    await tester.pump();
    expect(find.text('Siguiente: T3 E4'), findsOneWidget);
    expect(find.text('30'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    expect(find.text('25'), findsOneWidget);
    await tester.pump(const Duration(seconds: 26));
    await tester.pumpAndSettle();
    expect(find.text('Siguiente: T3 E4'), findsNothing);
    expect(result, isTrue);
  });

  testWidgets('Cancelar closes it without playing', (tester) async {
    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (c) =>
              TextButton(onPressed: () async => result = await showNextEpisode(c, ep), child: const Text('x')),
        ),
      ),
    );
    await tester.tap(find.text('x'));
    await tester.pump();
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(result, isFalse);
    await tester.pump(const Duration(seconds: 31));
    expect(result, isFalse);
  });
}
