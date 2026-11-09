import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../iptv/xtream.dart';
import '../state/app_state.dart';
import 'browse_screen.dart';
import 'movie_screen.dart';
import 'series_screen.dart';
import 'widgets.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key, this.autofocus = true});
  final bool autofocus;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  List<CatalogItem> _results = const [];
  Timer? _debounce;

  void _changed(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      final r = await context.read<AppState>().db.search(q);
      if (mounted) setState(() => _results = r);
    });
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
        title: TextField(
          autofocus: widget.autofocus,
          onChanged: _changed,
          decoration: const InputDecoration(hintText: 'Buscar canales, películas y series', border: InputBorder.none),
        ),
      ),
      body: ListView.builder(
        itemCount: _results.length,
        itemBuilder: (_, i) {
          final it = _results[i];
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
      ),
    );
  }
}
