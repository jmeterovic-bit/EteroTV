import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../iptv/xtream.dart';
import '../state/app_state.dart';
import 'browse_screen.dart';
import 'cards.dart';
import 'widgets.dart';

const posterRowHeight = 236.0;
const channelRowHeight = 134.0;

/// One category as a horizontal row (first 20 items) with "Ver todo".
class CategoryRow extends StatefulWidget {
  const CategoryRow({super.key, required this.category, this.titlePrefix = ''});
  final Category category;
  final String titlePrefix;

  @override
  State<CategoryRow> createState() => _CategoryRowState();
}

class _CategoryRowState extends State<CategoryRow> {
  List<CatalogItem>? _items;

  @override
  void initState() {
    super.initState();
    context.read<AppState>().db.itemsIn(widget.category.kind, widget.category.id, limit: 20).then((v) {
      if (mounted) setState(() => _items = v);
    });
  }

  @override
  Widget build(BuildContext context) {
    final locked = context.select<AppState, bool>((s) => s.isLocked(widget.category));
    if (locked) {
      return ListTile(
        leading: const Icon(Icons.lock, color: Colors.white54),
        title: Text('${widget.titlePrefix}${widget.category.name}'),
        subtitle: const Text('Protegida con PIN'),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ItemsScreen(category: widget.category))),
      );
    }
    final items = _items;
    final live = widget.category.kind == Kind.live;
    if (items == null) return SizedBox(height: (live ? channelRowHeight : posterRowHeight) + 50);
    return Shelf(
      title: '${widget.titlePrefix}${widget.category.name}',
      height: live ? channelRowHeight : posterRowHeight,
      onSeeAll: () =>
          Navigator.push(context, MaterialPageRoute(builder: (_) => ItemsScreen(category: widget.category))),
      children: [for (final it in items) live ? ChannelCard(item: it) : PosterCard(item: it)],
    );
  }
}

/// Netflix-style page for one kind: "Seguir viendo", "Favoritos", then a row per
/// category. The folder list (with search) is one tap away.
class KindTab extends StatefulWidget {
  const KindTab({super.key, required this.kind});
  final Kind kind;

  @override
  State<KindTab> createState() => _KindTabState();
}

class _KindTabState extends State<KindTab> {
  List<Category>? _cats;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final c = await context.read<AppState>().db.categories(widget.kind);
    if (mounted) setState(() => _cats = c);
  }

  void _folders() => Navigator.push(context, MaterialPageRoute(builder: (_) => BrowseScreen(kind: widget.kind)));

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final kind = widget.kind;
    final live = kind == Kind.live;
    final cats = _cats;
    final fav = [for (final e in s.favorites(kind)) catalogItemOf(e)];
    final started = live ? const <CatalogItem>[] : s.inProgress(kind);
    Widget card(CatalogItem it) => live ? ChannelCard(item: it) : PosterCard(item: it);
    final h = live ? channelRowHeight : posterRowHeight;
    return Scaffold(
      appBar: AppBar(
        title: Text(kindTitle(kind), style: const TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          TextButton.icon(
            onPressed: _folders,
            icon: const Icon(Icons.folder_open),
            label: const Text('Carpetas y búsqueda'),
          ),
        ],
      ),
      body: cats == null
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              padding: const EdgeInsets.only(bottom: 96),
              itemCount: cats.length + 2,
              itemBuilder: (_, i) {
                if (i == 0) {
                  return Shelf(
                    title: 'Seguir viendo',
                    height: h,
                    onSeeAll: () => _open(Category(kind, inProgressFolder, 'Seguir viendo')),
                    children: [for (final it in started) card(it)],
                  );
                }
                if (i == 1) {
                  return Shelf(
                    title: 'Favoritos',
                    height: h,
                    onSeeAll: () => _open(Category(kind, favoritesFolder, 'Favoritos')),
                    children: [for (final it in fav) card(it)],
                  );
                }
                return CategoryRow(key: ValueKey(cats[i - 2].id), category: cats[i - 2]);
              },
            ),
    );
  }

  void _open(Category c) => Navigator.push(context, MaterialPageRoute(builder: (_) => ItemsScreen(category: c)));
}
