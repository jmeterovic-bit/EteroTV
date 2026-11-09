import 'package:eterotv/data/library.dart';
import 'package:eterotv/iptv/xtream.dart';
import 'package:eterotv/logic/progress.dart';
import 'package:eterotv/logic/rematch.dart';
import 'package:eterotv/player/vlc.dart';
import 'package:eterotv/state/app_state.dart';
import 'package:flutter_test/flutter_test.dart';

CatalogItem movie(String id, String name, {String year = '', String tmdb = ''}) =>
    CatalogItem(kind: Kind.movie, id: id, name: name, categoryId: '1', year: year, tmdbId: tmdb);

void main() {
  group('progress', () {
    test('watched near the end', () {
      expect(isWatched(5400, 6000), isTrue); // 90 %
      expect(isWatched(5000, 6000), isFalse);
      expect(isWatched(2500, 2640), isTrue); // < 3 min left
      expect(isWatched(100, 0), isFalse);
    });

    test('resume point', () {
      expect(resumeFrom(20, 6000, watched: false), 0);
      expect(resumeFrom(1200, 6000, watched: false), 1195);
      expect(resumeFrom(1200, 6000, watched: true), 0);
      expect(resumeFrom(5900, 6000, watched: false), 0);
    });

    test('time format', () {
      expect(formatTime(65), '1:05');
      expect(formatTime(3725), '1:02:05');
    });

    test('VLC result updates the entry', () {
      final e = LibraryEntry(kind: Kind.movie, id: '1', name: 'x', updatedAt: 0);
      AppState.applyResult(e, PlayResult(positionSecs: 1800, durationSecs: 6000));
      expect(e.positionSecs, 1800);
      expect(e.watched, isFalse);
      AppState.applyResult(e, PlayResult(positionSecs: 5900));
      expect(e.watched, isTrue);
      expect(e.durationSecs, 6000);
    });
  });

  group('VLC on PC: position from status polling', () {
    test('keeps the last time seen', () {
      final t = VlcStatusTracker()
        ..add({'state': 'playing', 'time': 30, 'length': 6000})
        ..add({'state': 'paused', 'time': 1250, 'length': 6000});
      final r = t.result()!;
      expect(r.positionSecs, 1250);
      expect(r.durationSecs, 6000);
    });

    test('end of video: VLC resets to 0, we keep the end', () {
      final t = VlcStatusTracker()
        ..add({'state': 'playing', 'time': 5990, 'length': 6000})
        ..add({'state': 'stopped', 'time': 0, 'length': 0});
      expect(t.result()!.positionSecs, 6000);
    });

    test('stopped early stays where it was', () {
      final t = VlcStatusTracker()
        ..add({'state': 'playing', 'time': 900, 'length': 6000})
        ..add({'state': 'stopped', 'time': 0, 'length': 0});
      expect(t.result()!.positionSecs, 900);
    });

    test('no sample at all', () {
      expect(VlcStatusTracker().result(), isNull);
    });
  });

  group('rematch after a list update', () {
    test('names are cleaned of provider noise', () {
      expect(normalizeName('ES | El Señor de los Anillos (2001) [4K]'), 'el señor de los anillos');
      expect(normalizeName('[LAT] Película FHD'), 'pelicula');
      expect(normalizeName('|ES| Canal Uno HD'), 'canal uno');
    });

    test('same movie under a new prefix ranks first', () {
      final lost = LostItem(kind: Kind.movie, name: 'ES | Dune (2021) HD', year: '2021');
      final pool = [
        movie('1', 'Dune Part Two', year: '2024'),
        movie('2', 'ES - Dune [4K]', year: '2021'),
        movie('3', 'Dunkirk', year: '2017'),
      ];
      final best = bestByName(lost, pool);
      expect(best.first.item.id, '2');
    });

    test('duration breaks a tie between versions', () {
      final lost = LostItem(kind: Kind.movie, name: 'Dune', durationSecs: 9300);
      final a = scoreCandidate(lost, movie('1', 'Dune'), candidateDuration: 8220); // 1984, 137 min
      final b = scoreCandidate(lost, movie('2', 'Dune'), candidateDuration: 9360); // 2021, 156 min
      expect(b.score, greaterThan(a.score));
      expect(b.reasons, contains('misma duración'));
      expect(a.reasons, contains('duración distinta'));
    });

    test('same TMDB id is a sure match', () {
      final lost = LostItem(kind: Kind.movie, name: 'Algo', tmdbId: '438631');
      final c = scoreCandidate(lost, movie('9', 'Completely different', tmdb: '438631'));
      expect(c.score, 1);
      expect(c.safe, isTrue);
    });

    test('channels match by guide id', () {
      final lost = LostItem(kind: Kind.live, name: 'Canal 1', epgId: 'c1.es');
      final ch = CatalogItem(kind: Kind.live, id: '5', name: 'ES: La Uno FHD', categoryId: '', epgId: 'c1.es');
      expect(scoreCandidate(lost, ch).safe, isTrue);
    });

    test('other kinds and weak matches are left out', () {
      final lost = LostItem(kind: Kind.movie, name: 'Matrix');
      final pool = [
        CatalogItem(kind: Kind.series, id: '1', name: 'Matrix', categoryId: ''),
        movie('2', 'Toy Story'),
      ];
      expect(bestByName(lost, pool), isEmpty);
    });
  });
}
