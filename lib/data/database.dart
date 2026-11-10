import 'package:sqflite/sqflite.dart';

import '../iptv/xtream.dart';
import '../logic/rematch.dart' show stripAccents;
import 'library.dart';
import 'profiles.dart';

/// Local SQLite: the catalog (downloaded from the provider, never synced)
/// and the library (favourites and progress).
class AppDatabase {
  AppDatabase(this.db);
  final Database db;

  static Future<AppDatabase> open(String path) async {
    final db = await openDatabase(
      path,
      version: 2,
      onCreate: (db, _) => createTables(db),
      onUpgrade: (db, from, _) async {
        if (from < 2) await _libraryByProfile(db);
      },
    );
    return AppDatabase(db);
  }

  static Future<void> createTables(Database db) async {
    {
      await db.execute('''
        CREATE TABLE catalog(
          kind TEXT NOT NULL, id TEXT NOT NULL, name TEXT NOT NULL,
          name_lc TEXT NOT NULL, category_id TEXT, icon TEXT, ext TEXT,
          epg_id TEXT, tmdb_id TEXT, year TEXT, num INTEGER,
          PRIMARY KEY(kind, id))''');
      await db.execute('CREATE INDEX catalog_cat ON catalog(kind, category_id, num)');
      await db.execute('''
        CREATE TABLE categories(
          kind TEXT NOT NULL, id TEXT NOT NULL, name TEXT NOT NULL, pos INTEGER,
          PRIMARY KEY(kind, id))''');
      await _createLibrary(db);
    }
  }

  static const _libraryColumns =
      'key, kind, id, name, icon, ext, series_id, series_name, season, episode, tmdb_id, year, epg_id, '
      'favorite, position, duration, watched, last_played, updated_at, device';

  static Future<void> _createLibrary(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE library(
        profile TEXT NOT NULL, key TEXT NOT NULL, kind TEXT NOT NULL, id TEXT NOT NULL,
        name TEXT, icon TEXT, ext TEXT, series_id TEXT, series_name TEXT,
        season INTEGER, episode INTEGER, tmdb_id TEXT, year TEXT, epg_id TEXT,
        favorite INTEGER, position INTEGER, duration INTEGER, watched INTEGER,
        last_played INTEGER, updated_at INTEGER, device TEXT,
        PRIMARY KEY(profile, key))''');
    await db.execute('CREATE INDEX library_series ON library(profile, series_id)');
  }

  /// 1.0.0: one library per profile. What there was goes to the first one.
  static Future<void> _libraryByProfile(Database db) async {
    await db.transaction((t) async {
      await t.execute('DROP INDEX IF EXISTS library_series');
      await t.execute('ALTER TABLE library RENAME TO library_v1');
      await _createLibrary(t);
      await t.execute(
        "INSERT INTO library(profile, $_libraryColumns) SELECT '$defaultProfile', $_libraryColumns FROM library_v1",
      );
      await t.execute('DROP TABLE library_v1');
    });
  }

  // ---- Catalog ----

  /// Replaces the whole list of one kind in one transaction, in batches so
  /// that big lists (100 000+ entries) do not hold everything twice.
  Future<void> replaceCatalog(Kind kind, List<Category> cats, List<CatalogItem> items) async {
    await db.transaction((t) async {
      await t.delete('catalog', where: 'kind = ?', whereArgs: [kind.name]);
      await t.delete('categories', where: 'kind = ?', whereArgs: [kind.name]);
      var b = t.batch();
      for (var i = 0; i < cats.length; i++) {
        b.insert('categories', {
          'kind': kind.name,
          'id': cats[i].id,
          'name': cats[i].name,
          'pos': i,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await b.commit(noResult: true);
      for (var i = 0; i < items.length; i += 2000) {
        b = t.batch();
        for (final it in items.skip(i).take(2000)) {
          b.insert('catalog', {
            ...it.toRow(),
            'name_lc': searchKey(it.name),
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
        await b.commit(noResult: true);
      }
    });
  }

  Future<int> count(Kind kind) async =>
      Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM catalog WHERE kind = ?', [kind.name])) ?? 0;

  Future<List<Category>> categories(Kind kind) async {
    final rows = await db.query('categories', where: 'kind = ?', whereArgs: [kind.name], orderBy: 'pos');
    return [for (final r in rows) Category(kind, r['id'] as String, r['name'] as String)];
  }

  Future<List<CatalogItem>> itemsIn(Kind kind, String categoryId, {int? limit}) async {
    final rows = await db.query(
      'catalog',
      where: 'kind = ? AND category_id = ?',
      whereArgs: [kind.name, categoryId],
      orderBy: kind == Kind.live ? 'num, name_lc' : 'name_lc',
      limit: limit,
    );
    return rows.map(CatalogItem.fromRow).toList();
  }

  /// Lower case without accents, so "pelicula" finds "Película".
  static String searchKey(String s) => stripAccents(s.toLowerCase());

  /// Every word must appear, in any order. [kind] limits it to one kind.
  Future<List<CatalogItem>> search(String text, {Kind? kind, int limit = 300}) async {
    final words = searchKey(text).split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return const [];
    final where = [if (kind != null) 'kind = ?', for (final _ in words) 'name_lc LIKE ?'].join(' AND ');
    final rows = await db.query(
      'catalog',
      where: where,
      whereArgs: [if (kind != null) kind.name, for (final w in words) '%$w%'],
      orderBy: 'kind, name_lc',
      limit: limit,
    );
    return rows.map(CatalogItem.fromRow).toList();
  }

  Future<List<String>> idsIn(Kind kind, String categoryId) async => [
    for (final r in await db.query(
      'catalog',
      columns: ['id'],
      where: 'kind = ? AND category_id = ?',
      whereArgs: [kind.name, categoryId],
    ))
      r['id'] as String,
  ];

  Future<CatalogItem?> item(Kind kind, String id) async {
    final rows = await db.query('catalog', where: 'kind = ? AND id = ?', whereArgs: [kind.name, id], limit: 1);
    return rows.isEmpty ? null : CatalogItem.fromRow(rows.first);
  }

  Future<List<CatalogItem>> allOf(Kind kind) async =>
      (await db.query('catalog', where: 'kind = ?', whereArgs: [kind.name])).map(CatalogItem.fromRow).toList();

  // ---- Library ----

  Future<List<LibraryEntry>> library() async => (await db.query('library')).map(LibraryEntry.fromRow).toList();

  Future<void> saveEntry(LibraryEntry e) =>
      db.insert('library', e.toRow(), conflictAlgorithm: ConflictAlgorithm.replace);

  Future<void> deleteEntry(String profile, String key) =>
      db.delete('library', where: 'profile = ? AND key = ?', whereArgs: [profile, key]);

  Future<void> deleteProfile(String profile) => db.delete('library', where: 'profile = ?', whereArgs: [profile]);
}
