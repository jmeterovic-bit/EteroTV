import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../iptv/xtream.dart';
import '../state/app_state.dart';
import 'browse_screen.dart';
import 'movie_screen.dart';
import 'remote.dart';
import 'series_screen.dart';
import 'widgets.dart';
import 'i18n.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key, this.autofocus = true, this.typeNow});
  final bool autofocus;

  /// Ticks when the «Buscar» tab is chosen: the cursor goes to the field.
  final Listenable? typeNow;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  List<CatalogItem> _results = const [];
  Timer? _debounce;
  String _text = '';

  /// Where to look: everything (null), or only series, movies or channels.
  Kind? _kind;

  void _changed(String q) {
    final shown = q.trim().isNotEmpty;
    if (shown != _text.trim().isNotEmpty) setState(() {});
    _text = q;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _search);
  }

  Future<void> _search() async {
    final st = context.read<AppState>();
    final r = (await st.db.search(_text, kind: _kind)).where((it) => !st.isHiddenItem(it)).toList();
    if (mounted) setState(() => _results = r);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: RemoteTextField(
          autofocus: widget.autofocus,
          typeNow: widget.typeNow,
          onChanged: _changed,
          decoration: InputDecoration(hintText: tr('Buscar canales, películas y series'), border: InputBorder.none),
        ),
      ),
      body: Column(
        children: [
          if (_text.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: SegmentedButton<Kind?>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(value: null, label: Text(tr('Todo'))),
                  for (final k in [Kind.series, Kind.movie, Kind.live])
                    ButtonSegment(value: k, label: Text(kindTitle(k))),
                ],
                selected: {_kind},
                onSelectionChanged: (v) {
                  setState(() => _kind = v.first);
                  _search();
                },
              ),
            ),
          if (_kind == Kind.live && _qualities.length > 1)
            QualityChips(
              selected: _qualities.contains(_quality) ? _quality : null,
              available: _qualities,
              onSelected: (q) => setState(() => _quality = q),
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

  List<CatalogItem> get _shown => _kind == Kind.live && _quality != null && _qualities.contains(_quality)
      ? [
          for (final it in _results)
            if (qualityOf(it.name) == _quality) it,
        ]
      : _results;

  Widget _list() {
    final shown = _shown;
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
