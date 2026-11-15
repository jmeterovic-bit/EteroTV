import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../iptv/xtream.dart';
import '../logic/saved_search.dart';
import '../state/app_state.dart';
import 'browse_screen.dart';
import 'movie_screen.dart';
import 'remote.dart';
import 'series_screen.dart';
import 'widgets.dart';
import 'i18n.dart';

/// Search, with filters and saved searches (2.2.0, pedido de Jose
/// 2026-11-15). A saved search keeps the words, where to look and the
/// filters; each profile has its own, and they travel with it.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key, this.autofocus = true, this.typeNow});
  final bool autofocus;

  /// Ticks when the «Buscar» tab is chosen: the cursor goes to the field.
  final Listenable? typeNow;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _field = TextEditingController();
  List<CatalogItem> _results = const [];
  Timer? _debounce;
  bool _loading = false;
  int _run = 0;

  /// What is searched now. [_active] is the saved search it came from.
  SavedSearch _spec = SavedSearch(id: '');
  SavedSearch? _active;

  bool get _showOptions => _spec.text.trim().isNotEmpty || _active != null || !_onlyText;
  bool get _onlyText => _spec.filters.isEmpty && _spec.quality == null && !_spec.inGuide && !_spec.guideFirst;

  void _changed(String q) {
    final shown = _showOptions;
    _spec.text = q;
    if (shown != _showOptions) setState(() {});
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _search);
  }

  Future<void> _search() async {
    final st = context.read<AppState>();
    final run = ++_run;
    if (!_spec.canRun) {
      // No words and no filter (a kind alone is not enough): nothing yet.
      setState(() {
        _results = const [];
        _loading = false;
      });
      return;
    }
    setState(() => _loading = true);
    final r = await st.runSearch(_spec);
    if (!mounted || run != _run) return;
    setState(() {
      _results = r;
      _loading = false;
    });
    if (_spec.filters.contains(SearchFilter.active)) unawaited(_checkSome(r));
  }

  /// «Canal activo»: the first channels found that nobody opened lately are
  /// checked, one at a time (each takes a connection for a moment).
  Future<void> _checkSome(List<CatalogItem> found) async {
    final st = context.read<AppState>();
    final run = _run;
    final todo = [
      for (final it in found)
        if (it.kind == Kind.live && st.channelStatus(it.id) == ChannelStatus.unknown) it,
    ].take(8);
    for (final it in todo) {
      if (!mounted || run != _run) return;
      await st.probeChannel(it.id);
    }
  }

  void _pick(SavedSearch s) {
    _debounce?.cancel();
    setState(() {
      if (_active?.id == s.id) {
        _active = null;
        _spec = SavedSearch(id: '');
      } else {
        _active = s;
        _spec = s.copy();
      }
      _field.text = _spec.text;
    });
    _search();
  }

  void _setKind(Kind? k) {
    setState(() {
      _spec.kind = k;
      if (k != null && k != Kind.live) {
        // Movies and series: the channel filters do not apply.
        _spec
          ..filters.removeAll({SearchFilter.active, SearchFilter.onNow})
          ..quality = null
          ..inGuide = false
          ..guideFirst = false;
      }
    });
    _search();
  }

  Future<void> _filters() async {
    final s = await showDialog<SavedSearch>(
      context: context,
      builder: (_) => FiltersDialog(spec: _spec.copy()),
    );
    if (s == null || !mounted) return;
    setState(() => _spec = s);
    _search();
  }

  Future<void> _save() async {
    final st = context.read<AppState>();
    final messenger = ScaffoldMessenger.of(context);
    final name = await askSearchName(context, initial: _active?.name ?? _spec.text.trim());
    if (name == null || !mounted) return;
    final same = st.savedSearches.where((x) => x.name.toLowerCase() == name.toLowerCase()).firstOrNull;
    final s = _spec.copy(id: same?.id ?? st.newSearchId(), name: name);
    await st.saveSearch(s);
    if (!mounted) return;
    setState(() {
      _active = s;
      _spec = s.copy();
    });
    messenger.showSnackBar(SnackBar(content: Text(tr('Búsqueda guardada: {0}', [name]))));
  }

  Future<void> _menu(SavedSearch s) async {
    final st = context.read<AppState>();
    final messenger = ScaffoldMessenger.of(context);
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(s.name, style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
            ListTile(
              autofocus: true,
              leading: const Icon(Icons.edit_outlined),
              title: Text(tr('Cambiar el nombre')),
              onTap: () => Navigator.pop(c, 'rename'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: Text(tr('Borrar esta búsqueda')),
              onTap: () => Navigator.pop(c, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    switch (action) {
      case 'rename':
        final name = await askSearchName(context, initial: s.name);
        if (name == null) return;
        await st.saveSearch(s..name = name);
      case 'delete':
        await st.deleteSearch(s.id);
        if (_active?.id == s.id && mounted) setState(() => _active = null);
        messenger.showSnackBar(
          SnackBar(
            content: Text(tr('Búsqueda borrada: {0}', [s.name])),
            action: SnackBarAction(label: tr('Deshacer'), onPressed: () => st.saveSearch(s)),
          ),
        );
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _field.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    final saved = st.savedSearches;
    final changed = _active == null ? !_onlyText || _spec.text.trim().isNotEmpty : !_active!.sameAs(_spec);
    final nFilters =
        _spec.filters.length + (_spec.quality == null ? 0 : 1) + (_spec.inGuide ? 1 : 0) + (_spec.guideFirst ? 1 : 0);
    return Scaffold(
      appBar: AppBar(
        title: RemoteTextField(
          controller: _field,
          autofocus: widget.autofocus,
          typeNow: widget.typeNow,
          onChanged: _changed,
          decoration: InputDecoration(hintText: tr('Buscar canales, películas y series'), border: InputBorder.none),
        ),
      ),
      body: Column(
        children: [
          if (_showOptions)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: SegmentedButton<Kind?>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(value: null, label: Text(tr('Todo'))),
                  for (final k in [Kind.series, Kind.movie, Kind.live])
                    ButtonSegment(value: k, label: Text(kindTitle(k))),
                ],
                selected: {_spec.channelsOnly ? Kind.live : _spec.kind},
                onSelectionChanged: (v) => _setKind(v.first),
              ),
            ),
          if (_spec.channelsOnly && _qualities.length > 1)
            QualityChips(
              selected: _qualities.contains(_quality) ? _quality : null,
              available: _qualities,
              onSelected: (q) => setState(() => _quality = q),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  ActionChip(
                    avatar: const Icon(Icons.tune, size: 18),
                    label: Text(nFilters == 0 ? tr('Filtros') : tr('Filtros ({0})', [nFilters])),
                    onPressed: _filters,
                  ),
                  if (changed && _spec.canRun)
                    ActionChip(
                      avatar: const Icon(Icons.bookmark_add_outlined, size: 18),
                      label: Text(tr('Guardar búsqueda')),
                      onPressed: _save,
                    ),
                  for (final s in saved)
                    RemoteMenu(
                      onSelect: () => _pick(s),
                      onMenu: () => _menu(s),
                      child: GestureDetector(
                        onLongPress: () => _menu(s),
                        onSecondaryTap: () => _menu(s),
                        child: ChoiceChip(
                          avatar: const Icon(Icons.bookmark_outline, size: 18),
                          label: Text(s.name),
                          selected: _active?.id == s.id,
                          onSelected: (_) => _pick(s),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (st.guideLoading) ...[
            const LinearProgressIndicator(),
            Padding(padding: const EdgeInsets.all(8), child: Text(tr('Descargando la guía de programas…'))),
          ] else if (_spec.inGuide && st.guideFailed)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Text(
                tr('El proveedor no entregó su guía completa: se busca solo en el nombre de los canales.'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          Expanded(child: _list()),
        ],
      ),
    );
  }

  /// Channels: the qualities found in the names, to search only those.
  Quality? _quality;
  List<Quality> get _qualities {
    final present = {for (final it in _results) qualityOf(it.name)};
    return [
      for (final q in Quality.values)
        if (present.contains(q)) q,
    ];
  }

  List<CatalogItem> get _shown => _spec.channelsOnly && _quality != null && _qualities.contains(_quality)
      ? [
          for (final it in _results)
            if (qualityOf(it.name) == _quality) it,
        ]
      : _results;

  Widget _list() {
    final shown = _shown;
    if (shown.isEmpty) {
      if (_loading) return const Center(child: CircularProgressIndicator());
      if (_spec.canRun) return Center(child: Text(tr('Sin resultados')));
      return const SizedBox.shrink();
    }
    return ListView.builder(
      itemCount: shown.length,
      itemBuilder: (_, i) {
        final it = shown[i];
        if (it.kind == Kind.live) return ChannelTile(item: it);
        return ListTile(
          leading: SizedBox(width: 40, height: 60, child: NetImage(it.icon)),
          title: Text(it.name),
          subtitle: Text([kindTitle(it.kind), if (it.year.isNotEmpty) it.year].join(' · ')),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => it.kind == Kind.series ? SeriesScreen(item: it) : MovieScreen(item: it),
            ),
          ),
        );
      },
    );
  }
}

/// The name of a saved search. Null when cancelled.
Future<String?> askSearchName(BuildContext context, {String initial = ''}) async {
  final c = TextEditingController(text: initial);
  final name = await showDialog<String>(
    context: context,
    builder: (d) => AlertDialog(
      title: Text(tr('Guardar búsqueda')),
      content: RemoteTextField(
        controller: c,
        autofocus: true,
        decoration: InputDecoration(labelText: tr('Nombre')),
        onSubmitted: (v) => Navigator.pop(d, v),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d), child: Text(tr('Cancelar'))),
        TextButton(onPressed: () => Navigator.pop(d, c.text), child: Text(tr('Guardar'))),
      ],
    ),
  );
  final n = name?.trim() ?? '';
  return n.isEmpty ? null : n;
}

String filterLabel(SearchFilter f) => switch (f) {
  SearchFilter.active => tr('Canal activo (no falló hace poco)'),
  SearchFilter.onNow => tr('Con guía ahora (muestra el avance)'),
  SearchFilter.neverSeen => tr('Nunca visto'),
  SearchFilter.seen => tr('Ya visto'),
  SearchFilter.inProgress => tr('A medias'),
  SearchFilter.myList => tr('En «Mi lista» o favoritos'),
};

/// Where to look and the filters of a search. Everything is a chip, a
/// check box or a switch, so the remote reaches it all with the arrows.
class FiltersDialog extends StatefulWidget {
  const FiltersDialog({super.key, required this.spec});
  final SavedSearch spec;

  @override
  State<FiltersDialog> createState() => _FiltersDialogState();
}

class _FiltersDialogState extends State<FiltersDialog> {
  SavedSearch get s => widget.spec;

  static const _channelFilters = {SearchFilter.active, SearchFilter.onNow};

  @override
  Widget build(BuildContext context) {
    final live = s.kind == Kind.live || s.channelsOnly;
    final head = Theme.of(context).textTheme.titleSmall;
    return AlertDialog(
      title: Text(tr('Filtros')),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(tr('Buscar en'), style: head),
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                children: [
                  for (final (k, label) in [
                    (null, tr('Todo')),
                    (Kind.live, tr('Canales en vivo')),
                    (Kind.movie, tr('Películas')),
                    (Kind.series, tr('Series')),
                  ])
                    ChoiceChip(
                      label: Text(label),
                      selected: (live ? Kind.live : s.kind) == k,
                      onSelected: (_) => setState(() {
                        s.kind = k;
                        if (k != Kind.live) {
                          s
                            ..filters.removeAll(_channelFilters)
                            ..quality = null
                            ..inGuide = false
                            ..guideFirst = false;
                        }
                      }),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              for (final f in SearchFilter.values)
                if (live || !_channelFilters.contains(f))
                  CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    value: s.filters.contains(f),
                    title: Text(filterLabel(f)),
                    onChanged: (v) => setState(() {
                      if (v == true) {
                        s.filters.add(f);
                        if (_channelFilters.contains(f)) s.kind = Kind.live;
                        // «Nunca visto» and «Ya visto» exclude each other.
                        if (f == SearchFilter.neverSeen) s.filters.remove(SearchFilter.seen);
                        if (f == SearchFilter.seen) s.filters.remove(SearchFilter.neverSeen);
                      } else {
                        s.filters.remove(f);
                      }
                    }),
                  ),
              if (live) ...[
                SwitchListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  value: s.inGuide,
                  title: Text(tr('Buscar también en lo que dan ahora (guía)')),
                  onChanged: (v) => setState(() => s.inGuide = v),
                ),
                SwitchListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  value: s.guideFirst,
                  title: Text(tr('Primero los que muestran el avance')),
                  onChanged: (v) => setState(() => s.guideFirst = v),
                ),
                const SizedBox(height: 4),
                Text(tr('Calidad'), style: head),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  children: [
                    ChoiceChip(
                      label: Text(tr('Todas')),
                      selected: s.quality == null,
                      onSelected: (_) => setState(() => s.quality = null),
                    ),
                    for (final q in Quality.values)
                      ChoiceChip(
                        label: Text(q.label),
                        selected: s.quality == q,
                        onSelected: (_) => setState(() {
                          s
                            ..quality = q
                            ..kind = Kind.live;
                        }),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => setState(() {
            s
              ..filters.clear()
              ..quality = null
              ..inGuide = false
              ..guideFirst = false
              ..kind = null;
          }),
          child: Text(tr('Quitar filtros')),
        ),
        TextButton(autofocus: true, onPressed: () => Navigator.pop(context, s), child: Text(tr('Listo'))),
      ],
    );
  }
}
