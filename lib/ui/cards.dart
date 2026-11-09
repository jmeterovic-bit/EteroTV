import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/library.dart';
import '../iptv/xtream.dart';
import '../logic/progress.dart';
import '../state/app_state.dart';
import 'browse_screen.dart' show catalogItemOf;
import 'movie_screen.dart';
import 'play.dart';
import 'series_screen.dart';
import 'theme.dart';
import 'widgets.dart';

void openDetails(BuildContext context, CatalogItem item) => Navigator.push(
  context,
  MaterialPageRoute(
    builder: (_) => item.kind == Kind.series ? SeriesScreen(item: item) : MovieScreen(item: item),
  ),
);

/// The series (or the movie itself) an entry belongs to, to open its page.
CatalogItem detailsItemOf(LibraryEntry e) => e.kind == Kind.episode
    ? CatalogItem(kind: Kind.series, id: e.seriesId, name: e.seriesName, categoryId: '', icon: e.icon, year: e.year)
    : catalogItemOf(e);

String remainingLabel(LibraryEntry e) {
  final left = e.durationSecs - e.positionSecs;
  final ep = e.kind == Kind.episode ? 'T${e.season} E${e.episode} · ' : '';
  if (e.durationSecs <= 0) return '${ep}en ${formatTime(e.positionSecs)}';
  return '${ep}quedan ${(left / 60).ceil()} min';
}

/// Big header on Inicio: the last thing watched, ready to continue.
class HeroBanner extends StatelessWidget {
  const HeroBanner({super.key, required this.entry});
  final LibraryEntry entry;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final details = detailsItemOf(entry);
    final fav = s.isFavorite(details.kind, details.id);
    final wide = MediaQuery.sizeOf(context).width >= 800;
    final title = entry.kind == Kind.episode ? entry.seriesName : entry.name;
    final epLabel = entry.kind == Kind.episode ? 'Continuar T${entry.season} E${entry.episode}' : 'Continuar';
    return Container(
      height: wide ? 260 : 300,
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), color: const Color(0xFF1E1E1E)),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Opacity(opacity: 0.55, child: NetImage(entry.icon, icon: Icons.movie)),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Color(0xEE0C0C0C)],
                stops: [0.3, 1],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title.toUpperCase(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(remainingLabel(entry), style: const TextStyle(color: Colors.white70)),
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: fraction(entry.positionSecs, entry.durationSecs),
                  color: accent,
                  backgroundColor: Colors.white24,
                  minHeight: 3,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      flex: wide ? 0 : 3,
                      child: FilledButton.icon(
                        autofocus: true,
                        style: FilledButton.styleFrom(backgroundColor: accent, foregroundColor: Colors.black),
                        icon: const Icon(Icons.play_arrow),
                        label: Text(epLabel, overflow: TextOverflow.ellipsis),
                        onPressed: () => playWithChecks(context, (st) => st.resume(entry)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: wide ? 0 : 2,
                      child: FilledButton.tonalIcon(
                        icon: Icon(fav ? Icons.check : Icons.add),
                        label: const Text('Mi lista'),
                        onPressed: () => s.toggleFavorite(details),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filledTonal(
                      tooltip: 'Ficha',
                      icon: const Icon(Icons.info_outline),
                      onPressed: () => openDetails(context, details),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// "Continuar viendo" card: landscape image, play, progress, ⓘ and ⋮.
class ContinueCard extends StatefulWidget {
  const ContinueCard({super.key, required this.entry});
  final LibraryEntry entry;

  @override
  State<ContinueCard> createState() => _ContinueCardState();
}

class _ContinueCardState extends State<ContinueCard> {
  bool _focused = false;

  Future<void> _menu() async {
    final s = context.read<AppState>();
    final e = widget.entry;
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(e.title, style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('Ver ficha'),
              onTap: () => Navigator.pop(c, 'info'),
            ),
            ListTile(
              leading: const Icon(Icons.check_circle_outline),
              title: const Text('Marcar como visto'),
              onTap: () => Navigator.pop(c, 'watched'),
            ),
            ListTile(
              leading: const Icon(Icons.close),
              title: const Text('Quitar de Seguir viendo'),
              onTap: () => Navigator.pop(c, 'remove'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    switch (action) {
      case 'info':
        openDetails(context, detailsItemOf(e));
      case 'watched':
        await s.setWatched(e, true);
      case 'remove':
        await s.removeFromContinue(e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.entry;
    return SizedBox(
      width: 220,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1D1D1D),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: _focused ? accent : Colors.transparent, width: 3),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              onFocusChange: (f) => setState(() => _focused = f),
              onTap: () => playWithChecks(context, (st) => st.resume(e)),
              onLongPress: _menu,
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    NetImage(e.icon, icon: Icons.movie),
                    Center(
                      child: Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.black54,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                        child: const Icon(Icons.play_arrow, color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            LinearProgressIndicator(
              value: fraction(e.positionSecs, e.durationSecs),
              color: accent,
              backgroundColor: Colors.white24,
              minHeight: 3,
            ),
            Row(
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 4, 0, 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          e.kind == Kind.episode ? e.seriesName : e.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12),
                        ),
                        Text(
                          remainingLabel(e),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11, color: Colors.white60),
                        ),
                      ],
                    ),
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Ficha',
                  icon: const Icon(Icons.info_outline, size: 20),
                  onPressed: () => openDetails(context, detailsItemOf(e)),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Más',
                  icon: const Icon(Icons.more_vert, size: 20),
                  onPressed: _menu,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Long-press menu of a movie or series poster.
Future<void> showItemMenu(BuildContext context, CatalogItem item) async {
  final s = context.read<AppState>();
  final fav = s.isFavorite(item.kind, item.id);
  final started = s.isInProgress(item);
  final watched = item.kind == Kind.movie && (s.entry(Kind.movie, item.id)?.watched ?? false);
  final action = await showModalBottomSheet<String>(
    context: context,
    builder: (c) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: Text(item.name, style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('Ver ficha'),
            onTap: () => Navigator.pop(c, 'info'),
          ),
          ListTile(
            leading: Icon(fav ? Icons.star : Icons.star_border),
            title: Text(fav ? 'Quitar de favoritos' : 'Agregar a favoritos'),
            onTap: () => Navigator.pop(c, 'fav'),
          ),
          if (item.kind == Kind.movie)
            ListTile(
              leading: Icon(watched ? Icons.remove_done : Icons.check_circle_outline),
              title: Text(watched ? 'Marcar como no vista' : 'Marcar como vista'),
              onTap: () => Navigator.pop(c, 'watched'),
            ),
          if (started)
            ListTile(
              leading: const Icon(Icons.close),
              title: const Text('Quitar de Seguir viendo'),
              onTap: () => Navigator.pop(c, 'remove'),
            ),
        ],
      ),
    ),
  );
  if (!context.mounted) return;
  switch (action) {
    case 'info':
      openDetails(context, item);
    case 'fav':
      await s.toggleFavorite(item);
    case 'watched':
      await s.setMovieWatched(item, !watched);
    case 'remove':
      await s.removeFromInProgress(item);
  }
}

/// Poster for "Mi lista" and category rows.
class PosterCard extends StatelessWidget {
  const PosterCard({super.key, required this.item, this.autofocus = false});
  final CatalogItem item;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final e = context.select<AppState, LibraryEntry?>((s) => s.entry(item.kind, item.id));
    return FocusCard(
      autofocus: autofocus,
      width: 120,
      title: item.name,
      image: item.icon,
      icon: item.kind == Kind.series ? Icons.video_library : Icons.movie_outlined,
      badge: e?.watched == true ? Icons.check_circle : null,
      progress: e != null && e.positionSecs > 0 && !e.watched && e.durationSecs > 0
          ? fraction(e.positionSecs, e.durationSecs)
          : null,
      onTap: () => openDetails(context, item),
      onLongPress: () => showItemMenu(context, item),
    );
  }
}

/// Channel logo card: OK plays it.
class ChannelCard extends StatelessWidget {
  const ChannelCard({super.key, required this.item});
  final CatalogItem item;

  @override
  Widget build(BuildContext context) => FocusCard(
    width: 140,
    aspect: 16 / 10,
    title: item.name,
    image: item.icon,
    icon: Icons.live_tv,
    onTap: () => playWithChecks(context, (st) => st.playLive(item)),
  );
}
