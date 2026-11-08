import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

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

/// Categories of one kind. Wide screens (PC, TV) show categories on the left
/// and items on the right; phones go one level at a time.
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
      if (mounted) setState(() => _cats = c);
    });
  }

  @override
  Widget build(BuildContext context) {
    final cats = _cats;
    final wide = MediaQuery.sizeOf(context).width >= 800;
    final list = cats == null
        ? const Center(child: CircularProgressIndicator())
        : cats.isEmpty
            ? const Center(child: Text('Todavía no hay nada aquí. Actualiza la lista en Ajustes.'))
            : FocusTraversalGroup(
                child: ListView.builder(
                  itemCount: cats.length,
                  itemBuilder: (_, i) => ListTile(
                    autofocus: i == 0,
                    selected: wide && _selected?.id == cats[i].id,
                    title: Text(cats[i].name),
                    onFocusChange: wide ? (f) { if (f) setState(() => _selected = cats[i]); } : null,
                    onTap: () => wide
                        ? setState(() => _selected = cats[i])
                        : Navigator.push(context,
                            MaterialPageRoute(builder: (_) => ItemsScreen(category: cats[i]))),
                  ),
                ),
              );
    return Scaffold(
      appBar: AppBar(title: Text(kindTitle(widget.kind))),
      body: !wide
          ? list
          : Row(children: [
              SizedBox(width: 300, child: list),
              const VerticalDivider(width: 1),
              Expanded(
                child: _selected == null
                    ? const SizedBox.shrink()
                    : ItemsView(key: ValueKey(_selected!.id), category: _selected!),
              ),
            ]),
    );
  }
}

class ItemsScreen extends StatelessWidget {
  const ItemsScreen({super.key, required this.category});
  final Category category;

  @override
  Widget build(BuildContext context) =>
      Scaffold(appBar: AppBar(title: Text(category.name)), body: ItemsView(category: category, autofocus: true));
}

class ItemsView extends StatefulWidget {
  const ItemsView({super.key, required this.category, this.autofocus = false});
  final Category category;
  final bool autofocus;

  @override
  State<ItemsView> createState() => _ItemsViewState();
}

class _ItemsViewState extends State<ItemsView> {
  List<CatalogItem>? _items;

  @override
  void initState() {
    super.initState();
    context.read<AppState>().db.itemsIn(widget.category.kind, widget.category.id).then((v) {
      if (mounted) setState(() => _items = v);
    });
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    if (items == null) return const Center(child: CircularProgressIndicator());
    if (items.isEmpty) return const Center(child: Text('Categoría vacía'));
    if (widget.category.kind == Kind.live) {
      return FocusTraversalGroup(
        child: ListView.builder(
          itemCount: items.length,
          itemBuilder: (_, i) => ChannelTile(item: items[i], autofocus: widget.autofocus && i == 0),
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
        itemBuilder: (_, i) => PosterTile(item: items[i], autofocus: widget.autofocus && i == 0),
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
      leading: SizedBox(width: 56, height: 40, child: NetImage(item.icon, icon: Icons.live_tv, fit: BoxFit.contain)),
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
