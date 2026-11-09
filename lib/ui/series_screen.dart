import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../iptv/xtream.dart';
import '../logic/progress.dart';
import '../state/app_state.dart';
import 'play.dart';
import 'widgets.dart';

class SeriesScreen extends StatefulWidget {
  const SeriesScreen({super.key, required this.item});
  final CatalogItem item;

  @override
  State<SeriesScreen> createState() => _SeriesScreenState();
}

class _SeriesScreenState extends State<SeriesScreen> {
  SeriesInfo? _info;
  Object? _error;
  int? _season;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = context.read<AppState>();
    final x = s.client;
    if (x == null) return;
    try {
      final info = await x.seriesInfo(widget.item.id);
      if (!mounted) return;
      // Open on the season of the next episode to watch.
      final next = nextEpisode(info, s);
      setState(() {
        _info = info;
        _season = next?.season ?? (info.seasons.keys.isEmpty ? null : (info.seasons.keys.toList()..sort()).first);
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      x.close();
    }
  }

  /// First episode not watched after the last one played.
  static Episode? nextEpisode(SeriesInfo info, AppState s) {
    final all = [for (final k in (info.seasons.keys.toList()..sort())) ...info.seasons[k]!];
    var lastIdx = -1, lastAt = 0;
    for (var i = 0; i < all.length; i++) {
      final e = s.entry(Kind.episode, all[i].id);
      if (e != null && e.lastPlayed > lastAt) {
        lastAt = e.lastPlayed;
        lastIdx = i;
      }
    }
    if (lastIdx < 0) return all.isEmpty ? null : all.first;
    final last = s.entry(Kind.episode, all[lastIdx].id)!;
    if (!last.watched) return all[lastIdx];
    return lastIdx + 1 < all.length ? all[lastIdx + 1] : null;
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final fav = s.isFavorite(Kind.series, widget.item.id);
    final info = _info;
    final next = info == null ? null : nextEpisode(info, s);
    final seasons = info == null ? <int>[] : (info.seasons.keys.toList()..sort());
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.item.name),
        actions: [
          IconButton(
            tooltip: fav ? 'Quitar de favoritos' : 'Agregar a favoritos',
            icon: Icon(fav ? Icons.star : Icons.star_border, color: fav ? Colors.amber : null),
            onPressed: () => s.toggleFavorite(widget.item),
          ),
        ],
      ),
      body: _error != null
          ? Center(child: Text('No se pudo cargar la serie: $_error'))
          : info == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (info.plot.isNotEmpty) Text(info.plot, maxLines: 4, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 12),
                if (next != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FilledButton.icon(
                      autofocus: true,
                      icon: const Icon(Icons.play_arrow),
                      label: Text('Ver T${next.season} E${next.number}'),
                      onPressed: () => playWithChecks(context, (st) => st.playEpisode(widget.item, next)),
                    ),
                  ),
                const SizedBox(height: 12),
                FocusTraversalGroup(
                  child: Wrap(
                    spacing: 8,
                    children: [
                      for (final n in seasons)
                        ChoiceChip(
                          label: Text('Temporada $n'),
                          selected: n == _season,
                          onSelected: (_) => setState(() => _season = n),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                for (final ep in info.seasons[_season] ?? const <Episode>[]) _EpisodeTile(series: widget.item, ep: ep),
              ],
            ),
    );
  }
}

class _EpisodeTile extends StatelessWidget {
  const _EpisodeTile({required this.series, required this.ep});
  final CatalogItem series;
  final Episode ep;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final e = s.entry(Kind.episode, ep.id);
    final dur = (e?.durationSecs ?? 0) > 0 ? e!.durationSecs : ep.durationSecs;
    final started = e != null && e.positionSecs > 0 && !e.watched;
    return ListTile(
      leading: CircleAvatar(child: Text('${ep.number}')),
      title: Text(ep.title.isEmpty ? 'Episodio ${ep.number}' : ep.title),
      subtitle: started
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                LinearProgressIndicator(value: fraction(e.positionSecs, dur)),
                Text(progressLabel(e.positionSecs, dur)),
              ],
            )
          : (dur > 0 ? Text(formatTime(dur)) : null),
      onTap: () => playWithChecks(context, (st) => st.playEpisode(series, ep)),
      trailing: e == null
          ? null
          : IconButton(
              tooltip: e.watched ? 'Marcar como no visto' : 'Marcar como visto',
              icon: Icon(
                e.watched ? Icons.check_circle : Icons.check_circle_outline,
                color: e.watched ? Colors.greenAccent : null,
              ),
              onPressed: () => s.setWatched(e, !e.watched),
            ),
    );
  }
}
