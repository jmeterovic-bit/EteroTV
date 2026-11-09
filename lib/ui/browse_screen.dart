import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/database.dart';
import '../data/library.dart';
import '../iptv/xtream.dart';
import '../state/app_state.dart';
import 'movie_screen.dart';
import 'play.dart';
import 'series_screen.dart';
import 'widgets.dart';

String kindTitle(Kind k) => switch (k) {
  Kind.live => 'Canales',
  Kind.movie => 'Películas',
  Kind.series => 'Series',
  Kind.episode => 'Episodios',
};

/// Id of the "Favourites" folder shown first in every kind.
const favoritesFolder = '__favoritos__';

/// Id of the "Seguir viendo" folder (movies and series started but not finished).
const inProgressFolder = '__a_medias__';

String folderTitle(Category c) => switch (c.id) {
  favoritesFolder => 'Favoritos',
  inProgressFolder => 'Seguir viendo',
  _ => c.name,
};

/// Categories of one kind (with "Favoritos" first). Wide screens (PC, TV)
/// show categories on the left and items on the right; phones go one level
/// at a time.
class BrowseScreen extends StatefulWidget {
  const BrowseScreen({super.key, required this.kind});
  final Kind kind;

  @override
  State<BrowseScreen> createState() => _BrowseScreenState();
}

class _BrowseScreenState extends State<BrowseScreen> {
  List<Category>? _cats;
  Category? _selected;

  @override
  void initState() {
    super.initState();
    context.read<AppState>().db.categories(widget.kind).then((c) {
      if (!mounted) return;
      final fav = Category(widget.kind, favoritesFolder, 'Favoritos');
      setState(() {
        _cats = [if (widget.kind != Kind.live) Category(widget.kind, inProgressFolder, 'Seguir viendo'), fav, ...c];
        _selected = fav;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final cats = _cats;
    final wide = MediaQuery.sizeOf(context).width >= 800;
    final list = cats == null
        ? const Center(child: CircularProgressIndicator())
        : FocusTraversalGroup(
            child: ListView.builder(
              itemCount: cats.length,
              itemBuilder: (_, i) => ListTile(
                autofocus: i == 0,
                selected: wide && _selected?.id == cats[i].id,
                leading: switch (cats[i].id) {
                  favoritesFolder => const Icon(Icons.star, color: Colors.amber),
                  inProgressFolder => const Icon(Icons.play_circle_outline, color: Colors.amber),
                  _ => null,
                },
                title: Text(folderTitle(cats[i])),
                onFocusChange: wide
                    ? (f) {
                        if (f) setState(() => _selected = cats[i]);
                      }
                    : null,
                onTap: () => wide
                    ? setState(() => _selected = cats[i])
                    : Navigator.push(context, MaterialPageRoute(builder: (_) => ItemsScreen(category: cats[i]))),
              ),
            ),
          );
    return Scaffold(
      appBar: AppBar(title: Text(kindTitle(widget.kind))),
      body: !wide
          ? Column(
              children: [
                // Phone: search the whole kind from the folder list.
                Expanded(
                  child: _KindSearch(kind: widget.kind, child: list),
                ),
              ],
            )
          : Row(
              children: [
                SizedBox(width: 300, child: list),
                const VerticalDivider(width: 1),
                Expanded(
                  child: _selected == null
                      ? const SizedBox.shrink()
                      : ItemsView(key: ValueKey(_selected!.id), category: _selected!),
                ),
              ],
            ),
    );
  }
}

/// Search box over the folder list (phone): searches the whole kind.
class _KindSearch extends StatefulWidget {
  const _KindSearch({required this.kind, required this.child});
  final Kind kind;
  final Widget child;

  @override
  State<_KindSearch> createState() => _KindSearchState();
}

class _KindSearchState extends State<_KindSearch> {
  String _q = '';
  List<CatalogItem> _results = const [];
  Timer? _debounce;

  void _changed(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      final r = await context.read<AppState>().db.search(q, kind: widget.kind);
      if (!mounted) return;
      setState(() {
        _q = q.trim();
        _results = r;
      });
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      _SearchField(hint: 'Buscar en ${kindTitle(widget.kind)}', onChanged: _changed),
      Expanded(
        child: _q.isEmpty ? widget.child : ItemsList(kind: widget.kind, items: _results),
      ),
    ],
  );
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.hint, required this.onChanged});
  final String hint;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
    child: TextField(
      onChanged: onChanged,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: const Icon(Icons.search),
        isDense: true,
        border: const OutlineInputBorder(),
      ),
    ),
  );
}

class ItemsScreen extends StatelessWidget {
  const ItemsScreen({super.key, required this.category});
  final Category category;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(folderTitle(category))),
    body: ItemsView(category: category, autofocus: true),
  );
}

/// Items of one folder, with a search box that searches this folder or the
/// whole kind (all folders), as the user chooses.
class ItemsView extends StatefulWidget {
  const ItemsView({super.key, required this.category, this.autofocus = false});
  final Category category;
  final bool autofocus;

  @override
  State<ItemsView> createState() => _ItemsViewState();
}

class _ItemsViewState extends State<ItemsView> {
  List<CatalogItem>? _items;
  String _q = '';
  bool _everywhere = false;
  List<CatalogItem> _everywhereResults = const [];
  Timer? _debounce;

  Kind get kind => widget.category.kind;
  bool get isFavorites => widget.category.id == favoritesFolder;
  bool get isInProgress => widget.category.id == inProgressFolder;
  bool get isLive => isFavorites || isInProgress;

  @override
  void initState() {
    super.initState();
    if (!isLive) {
      context.read<AppState>().db.itemsIn(kind, widget.category.id).then((v) {
        if (mounted) setState(() => _items = v);
      });
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _changed(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      setState(() => _q = q.trim());
      if (_everywhere) _searchEverywhere();
    });
  }

  Future<void> _searchEverywhere() async {
    final r = await context.read<AppState>().db.search(_q, kind: kind);
    if (mounted) setState(() => _everywhereResults = r);
  }

  static bool _matches(CatalogItem it, List<String> words) {
    final key = AppDatabase.searchKey(it.name);
    return words.every(key.contains);
  }

  @override
  Widget build(BuildContext context) {
    // The favourites folder follows the library live (unstarring removes it).
    final items = isFavorites ? [for (final e in context.watch<AppState>().favorites(kind)) catalogItemOf(e)] : _items;
    final words = AppDatabase.searchKey(_q).split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    final shown = items == null
        ? null
        : words.isEmpty
        ? items
        : (_everywhere ? _everywhereResults : items.where((it) => _matches(it, words)).toList());
    final folderName = folderTitle(widget.category);
    return Column(
      children: [
        _SearchField(hint: 'Buscar', onChanged: _changed),
        if (_q.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: SegmentedButton<bool>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(value: false, label: Text('Solo en $folderName', overflow: TextOverflow.ellipsis)),
                ButtonSegment(value: true, label: Text('En todo ${kindTitle(kind)}')),
              ],
              selected: {_everywhere},
              onSelectionChanged: (v) {
                setState(() => _everywhere = v.first);
                if (_everywhere) _searchEverywhere();
              },
            ),
          ),
        Expanded(
          child: shown == null
              ? const Center(child: CircularProgressIndicator())
              : shown.isEmpty
              ? Center(
                  child: Text(
                    _q.isNotEmpty
                        ? 'Sin resultados'
                        : (isFavorites
                              ? 'Marca con la estrella para tenerlos aquí.'
                              : isInProgress
                              ? 'Aquí aparece lo que empezaste y no terminaste.'
                              : 'Carpeta vacía'),
                  ),
                )
              : ItemsList(kind: kind, items: shown, autofocus: widget.autofocus && _q.isEmpty),
        ),
      ],
    );
  }
}

/// Library entry back to a catalog item, to open or play it.
CatalogItem catalogItemOf(LibraryEntry e) => CatalogItem(
  kind: e.kind,
  id: e.id,
  name: e.name,
  categoryId: '',
  icon: e.icon,
  extension: e.extension,
  epgId: e.epgId,
  tmdbId: e.tmdbId,
  year: e.year,
);

/// Channels as a list; movies and series as a poster grid.
class ItemsList extends StatelessWidget {
  const ItemsList({super.key, required this.kind, required this.items, this.autofocus = false});
  final Kind kind;
  final List<CatalogItem> items;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    if (kind == Kind.live) {
      return FocusTraversalGroup(
        child: ListView.builder(
          itemCount: items.length,
          itemBuilder: (_, i) => ChannelTile(item: items[i], autofocus: autofocus && i == 0),
        ),
      );
    }
    return FocusTraversalGroup(
      child: GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 170,
          childAspectRatio: 0.52,
          crossAxisSpacing: 14,
          mainAxisSpacing: 14,
        ),
        itemCount: items.length,
        itemBuilder: (_, i) => PosterTile(item: items[i], autofocus: autofocus && i == 0),
      ),
    );
  }
}

class ChannelTile extends StatelessWidget {
  const ChannelTile({super.key, required this.item, this.autofocus = false});
  final CatalogItem item;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final fav = context.select<AppState, bool>((s) => s.isFavorite(Kind.live, item.id));
    return ListTile(
      autofocus: autofocus,
      leading: SizedBox(
        width: 56,
        height: 40,
        child: NetImage(item.icon, icon: Icons.live_tv, fit: BoxFit.contain),
      ),
      title: Text(item.name),
      subtitle: item.number > 0 ? Text('${item.number}') : null,
      onTap: () => playWithChecks(context, (s) => s.playLive(item)),
      trailing: IconButton(
        tooltip: fav ? 'Quitar de favoritos' : 'Agregar a favoritos',
        icon: Icon(fav ? Icons.star : Icons.star_border, color: fav ? Colors.amber : null),
        onPressed: () => context.read<AppState>().toggleFavorite(item),
      ),
    );
  }
}

class PosterTile extends StatelessWidget {
  const PosterTile({super.key, required this.item, this.autofocus = false});
  final CatalogItem item;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final e = s.entry(item.kind, item.id);
    return FocusCard(
      autofocus: autofocus,
      title: item.name,
      subtitle: item.year.isEmpty ? null : item.year,
      image: item.icon,
      icon: item.kind == Kind.series ? Icons.video_library : Icons.movie_outlined,
      badge: e?.favorite == true ? Icons.star : (e?.watched == true ? Icons.check_circle : null),
      progress: e != null && e.positionSecs > 0 && !e.watched && e.durationSecs > 0
          ? e.positionSecs / e.durationSecs
          : null,
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => item.kind == Kind.series ? SeriesScreen(item: item) : MovieScreen(item: item),
        ),
      ),
    );
  }
}
