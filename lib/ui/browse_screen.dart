import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/database.dart';
import '../data/library.dart';
import '../iptv/xtream.dart';
import '../state/app_state.dart';
import 'cards.dart' show showItemMenu, toggleFavoriteWithNote;
import 'movie_screen.dart';
import 'pin.dart';
import 'play.dart';
import 'remote.dart';
import 'series_screen.dart';
import 'widgets.dart';
import 'i18n.dart';

String kindTitle(Kind k) => switch (k) {
  Kind.live => tr('Canales'),
  Kind.movie => tr('Películas'),
  Kind.series => tr('Series'),
  Kind.episode => tr('Episodios'),
};

/// Id of the "Favourites" folder shown first in every kind.
const favoritesFolder = '__favoritos__';

/// Id of the "Seguir viendo" folder (movies and series started but not finished).
const inProgressFolder = '__a_medias__';

bool isSpecialFolder(Category c) => c.id == favoritesFolder || c.id == inProgressFolder;

String folderTitle(Category c) => switch (c.id) {
  favoritesFolder => tr('Favoritos'),
  inProgressFolder => tr('Seguir viendo'),
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
      final fav = Category(widget.kind, favoritesFolder, tr('Favoritos'));
      setState(() {
        _cats = [if (widget.kind != Kind.live) Category(widget.kind, inProgressFolder, tr('Seguir viendo')), fav, ...c];
        _selected = fav;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final cats = _cats;
    final st = context.watch<AppState>();
    final wide = MediaQuery.sizeOf(context).width >= 800;
    final list = cats == null
        ? const Center(child: CircularProgressIndicator())
        : FocusTraversalGroup(
            child: ListView.builder(
              itemCount: cats.length,
              itemBuilder: (_, i) {
                void open() => wide
                    ? setState(() => _selected = cats[i])
                    : Navigator.push(context, MaterialPageRoute(builder: (_) => ItemsScreen(category: cats[i])));
                final protect = isSpecialFolder(cats[i])
                    ? null
                    : () => toggleProtection(context, cats[i], cats[i].name);
                return RemoteMenu(
                  onSelect: open,
                  onMenu: protect,
                  child: ListTile(
                    autofocus: i == 0,
                    selected: wide && _selected?.id == cats[i].id,
                    leading: switch (cats[i].id) {
                      favoritesFolder => const Icon(Icons.star, color: Colors.amber),
                      inProgressFolder => const Icon(Icons.play_circle_outline, color: Colors.amber),
                      _ => null,
                    },
                    title: Text(folderTitle(cats[i])),
                    trailing: st.isProtected(cats[i])
                        ? Icon(st.isLocked(cats[i]) ? Icons.lock : Icons.lock_open, size: 18, color: Colors.white54)
                        : null,
                    onLongPress: protect,
                    onFocusChange: wide
                        ? (f) {
                            if (f) setState(() => _selected = cats[i]);
                          }
                        : null,
                    onTap: open,
                  ),
                );
              },
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
      final st = context.read<AppState>();
      final r = (await st.db.search(q, kind: widget.kind)).where((it) => !st.isHiddenItem(it)).toList();
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
      _SearchField(hint: tr('Buscar en {0}', [kindTitle(widget.kind)]), onChanged: _changed),
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
    child: RemoteTextField(
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
    final st = context.read<AppState>();
    final r = (await st.db.search(_q, kind: kind)).where((it) => !st.isHiddenItem(it)).toList();
    if (mounted) setState(() => _everywhereResults = r);
  }

  static bool _matches(CatalogItem it, List<String> words) {
    final key = AppDatabase.searchKey(it.name);
    return words.every(key.contains);
  }

  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    final folderName = folderTitle(widget.category);
    if (!isSpecialFolder(widget.category) && st.isLocked(widget.category)) {
      return LockedFolder(category: widget.category, name: folderName);
    }
    // The library folders follow the library live (unstarring removes it).
    final items = isFavorites
        ? [for (final e in st.favorites(kind)) catalogItemOf(e)]
        : isInProgress
        ? st.inProgress(kind)
        : _items;
    final words = AppDatabase.searchKey(_q).split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    final shown = items == null
        ? null
        : words.isEmpty
        ? items
        : (_everywhere ? _everywhereResults : items.where((it) => _matches(it, words)).toList());
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _SearchField(hint: tr('Buscar'), onChanged: _changed),
            ),
            if (!isSpecialFolder(widget.category))
              Padding(
                padding: const EdgeInsets.only(right: 8, top: 4),
                child: IconButton(
                  tooltip: st.isProtected(widget.category)
                      ? tr('Quitar el PIN de esta carpeta')
                      : tr('Proteger con PIN'),
                  icon: Icon(st.isProtected(widget.category) ? Icons.lock : Icons.lock_outline),
                  onPressed: () => toggleProtection(context, widget.category, folderName),
                ),
              ),
          ],
        ),
        if (_q.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: SegmentedButton<bool>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(
                  value: false,
                  label: Text(tr('Solo en {0}', [folderName]), overflow: TextOverflow.ellipsis),
                ),
                ButtonSegment(value: true, label: Text(tr('En todo {0}', [kindTitle(kind)]))),
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
                        ? tr('Sin resultados')
                        : (isFavorites
                              ? tr('Marca con la estrella para tenerlos aquí.')
                              : isInProgress
                              ? tr('Aquí aparece lo que empezaste y no terminaste.')
                              : tr('Carpeta vacía')),
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
    if (kind == Kind.live) return ChannelList(items: items, autofocus: autofocus);
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

/// Channels, with «Todas · 4K · FHD · HD · SD» on top when the list has
/// more than one quality (taken from the names).
class ChannelList extends StatefulWidget {
  const ChannelList({super.key, required this.items, this.autofocus = false});
  final List<CatalogItem> items;
  final bool autofocus;

  @override
  State<ChannelList> createState() => _ChannelListState();
}

class _ChannelListState extends State<ChannelList> {
  Quality? _only;

  @override
  Widget build(BuildContext context) {
    final present = {for (final it in widget.items) qualityOf(it.name)};
    final filter = present.length > 1;
    final only = filter && present.contains(_only) ? _only : null;
    final items = only == null
        ? widget.items
        : [
            for (final it in widget.items)
              if (qualityOf(it.name) == only) it,
          ];
    return Column(
      children: [
        if (filter)
          QualityChips(
            selected: only,
            available: [
              for (final q in Quality.values)
                if (present.contains(q)) q,
            ],
            onSelected: (q) => setState(() => _only = q),
          ),
        Expanded(
          child: FocusTraversalGroup(
            child: ListView.builder(
              itemCount: items.length,
              itemBuilder: (_, i) => ChannelTile(item: items[i], autofocus: widget.autofocus && i == 0),
            ),
          ),
        ),
      ],
    );
  }
}

/// «Todas · 4K · FHD · HD · SD».
class QualityChips extends StatelessWidget {
  const QualityChips({super.key, required this.selected, required this.available, required this.onSelected});
  final Quality? selected;
  final List<Quality> available;
  final ValueChanged<Quality?> onSelected;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
    child: Align(
      alignment: Alignment.centerLeft,
      child: Wrap(
        spacing: 8,
        children: [
          ChoiceChip(label: Text(tr('Todas')), selected: selected == null, onSelected: (_) => onSelected(null)),
          for (final q in available)
            ChoiceChip(label: Text(q.label), selected: selected == q, onSelected: (_) => onSelected(q)),
        ],
      ),
    ),
  );
}

/// The quality written in a channel's name, as a small coloured tag.
class QualityTag extends StatelessWidget {
  const QualityTag(this.quality, {super.key});
  final Quality quality;

  static Color colorOf(Quality q) => switch (q) {
    Quality.uhd => const Color(0xFF8E24AA),
    Quality.fhd => const Color(0xFF1E88E5),
    Quality.hd => const Color(0xFF43A047),
    Quality.sd => const Color(0xFF757575),
  };

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(color: colorOf(quality), borderRadius: BorderRadius.circular(4)),
    child: Text(
      quality.label,
      style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
    ),
  );
}

class ChannelTile extends StatefulWidget {
  const ChannelTile({super.key, required this.item, this.autofocus = false});
  final CatalogItem item;
  final bool autofocus;

  /// The remote stays this long on a channel before it is checked.
  static const probeAfter = Duration(seconds: 2);

  @override
  State<ChannelTile> createState() => _ChannelTileState();
}

class _ChannelTileState extends State<ChannelTile> {
  Timer? _probe;

  CatalogItem get item => widget.item;

  @override
  void dispose() {
    _probe?.cancel();
    super.dispose();
  }

  /// Remote or keyboard (not touch): staying on a channel checks it once.
  void _focused(bool f) {
    _probe?.cancel();
    if (!f || FocusManager.instance.highlightMode != FocusHighlightMode.traditional) return;
    final st = context.read<AppState>();
    _probe = Timer(ChannelTile.probeAfter, () => st.probeChannel(item.id));
  }

  @override
  Widget build(BuildContext context) {
    final fav = context.select<AppState, bool>((s) => s.isFavorite(Kind.live, item.id));
    final status = context.select<AppState, ChannelStatus>((s) => s.channelStatus(item.id));
    final down = status == ChannelStatus.down;
    void play() => playWithChecks(context, (s) => s.playLive(item));
    // Holding OK (TV) or a long press stars it; the star on the right too.
    return RemoteMenu(
      onSelect: play,
      onMenu: () => toggleFavoriteWithNote(context, item),
      child: ListTile(
        autofocus: widget.autofocus,
        onFocusChange: _focused,
        leading: Opacity(
          opacity: down ? 0.35 : 1,
          child: SizedBox(
            width: 56,
            height: 40,
            child: NetImage(item.icon, icon: Icons.live_tv, fit: BoxFit.contain),
          ),
        ),
        title: Text(item.name, style: down ? const TextStyle(color: Colors.white38) : null),
        subtitle: down
            ? Text(
                _downNote(context.read<AppState>().channelCheckedAt(item.id)),
                style: const TextStyle(color: Colors.white38),
              )
            : EpgLine(channelId: item.id, epgId: item.epgId, number: item.number),
        onTap: play,
        onLongPress: () => toggleFavoriteWithNote(context, item),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ChannelStatusDot(status),
            if (qualityOf(item.name) case final q?) QualityTag(q),
            IconButton(
              tooltip: fav ? tr('Quitar de favoritos') : tr('Agregar a favoritos'),
              icon: Icon(fav ? Icons.star : Icons.star_border, color: fav ? Colors.amber : null),
              onPressed: () => context.read<AppState>().toggleFavorite(item),
            ),
          ],
        ),
      ),
    );
  }

  static String _downNote(DateTime? at) {
    final mins = at == null ? 0 : DateTime.now().difference(at).inMinutes;
    return mins < 1 ? tr('No cargó recién') : tr('No cargó hace {0} min', [mins]);
  }
}

/// Green: it played or answered lately. Checking: a small circle.
/// Down channels show grey instead (see [ChannelTile]).
class ChannelStatusDot extends StatelessWidget {
  const ChannelStatusDot(this.status, {super.key});
  final ChannelStatus status;

  @override
  Widget build(BuildContext context) => switch (status) {
    ChannelStatus.up => Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Tooltip(
        message: tr('Funciona'),
        child: const Icon(Icons.circle, size: 10, color: Color(0xFF43A047)),
      ),
    ),
    ChannelStatus.checking => const Padding(
      padding: EdgeInsets.only(right: 8),
      child: SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2)),
    ),
    ChannelStatus.down => Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Tooltip(
        message: tr('No cargó'),
        child: const Icon(Icons.portable_wifi_off, size: 16, color: Colors.white38),
      ),
    ),
    ChannelStatus.unknown => const SizedBox.shrink(),
  };
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
      onLongPress: () => showItemMenu(context, item),
    );
  }
}

/// Under a channel: what it shows now with a bar of how far it went and
/// when it ends, and what comes next, from the provider's guide (its
/// number only when the provider has none).
class EpgLine extends StatefulWidget {
  const EpgLine({super.key, required this.channelId, this.epgId = '', this.number = 0});
  final String channelId;
  final String epgId;
  final int number;

  @override
  State<EpgLine> createState() => _EpgLineState();
}

class _EpgLineState extends State<EpgLine> {
  late Future<List<EpgEntry>> _epg = _load();
  Timer? _tick;

  Future<List<EpgEntry>> _load() => context.read<AppState>().epgFor(widget.channelId, epgId: widget.epgId);

  @override
  void initState() {
    super.initState();
    // The bar moves; when the programme ends, the guide is asked again.
    _tick = Timer.periodic(const Duration(seconds: 30), (_) async {
      if (!mounted) return;
      final (on, _) = nowAndNext(await _epg, DateTime.now());
      if (!mounted) return;
      setState(() {
        if (on == null) _epg = _load();
      });
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<EpgEntry>>(
    future: _epg,
    builder: (context, snap) {
      final now = DateTime.now();
      final (on, next) = nowAndNext(snap.data ?? const [], now);
      String hm(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
      final small = Theme.of(context).textTheme.bodySmall;
      if (on == null && next == null) {
        return widget.number > 0 ? Text('${widget.number}') : const SizedBox.shrink();
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (on != null) ...[
            Text(tr('Ahora: {0}', [on.title]), maxLines: 1, overflow: TextOverflow.ellipsis),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Expanded(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 360),
                      child: LinearProgressIndicator(
                        value: programmeProgress(on, now),
                        minHeight: 4,
                        borderRadius: BorderRadius.circular(2),
                        backgroundColor: Colors.white12,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(tr('hasta {0}', [hm(on.end)]), style: small),
                ],
              ),
            ),
          ],
          if (next != null)
            Text(
              tr('Después, {0}: {1}', [hm(next.start), next.title]),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: small,
            ),
        ],
      );
    },
  );
}

/// How far a programme went, from 0 to 1.
double programmeProgress(EpgEntry e, DateTime now) {
  final total = e.end.difference(e.start).inSeconds;
  if (total <= 0) return 0;
  return (now.difference(e.start).inSeconds / total).clamp(0.0, 1.0);
}
