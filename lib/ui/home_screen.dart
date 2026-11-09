import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/library.dart';
import '../iptv/xtream.dart';
import '../logic/progress.dart';
import '../state/app_state.dart';
import 'browse_screen.dart';
import 'lost_screen.dart';
import 'movie_screen.dart';
import 'play.dart';
import 'search_screen.dart';
import 'series_screen.dart';
import 'settings_screen.dart';
import 'widgets.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final cont = s.continueWatching;
    return Scaffold(
      appBar: AppBar(
        title: const Text('EteroTV'),
        actions: [
          IconButton(
            tooltip: 'Buscar',
            icon: const Icon(Icons.search),
            onPressed: () => _push(context, const SearchScreen()),
          ),
          IconButton(
            tooltip: 'Ajustes',
            icon: const Icon(Icons.settings),
            onPressed: () => _push(context, const SettingsScreen()),
          ),
        ],
      ),
      body: ListView(children: [
        if (s.refreshing)
          ListTile(
            leading: const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
            title: Text(s.refreshStep),
            subtitle: const Text('La primera vez puede tardar un par de minutos.'),
          ),
        if (s.error != null)
          ListTile(
            leading: const Icon(Icons.error_outline, color: Colors.redAccent),
            title: Text(s.error!),
            trailing: TextButton(onPressed: s.refreshCatalog, child: const Text('Reintentar')),
          ),
        if (s.lost.isNotEmpty)
          Card(
            margin: const EdgeInsets.all(16),
            child: ListTile(
              leading: const Icon(Icons.find_replace),
              title: Text('${s.lost.length} favoritos o progresos no aparecen en la lista nueva'),
              subtitle: const Text('Te sugiero los más parecidos para reemplazarlos.'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _push(context, const LostScreen()),
            ),
          ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: FocusTraversalGroup(
            child: Wrap(spacing: 12, runSpacing: 12, children: [
              _BigButton(Icons.live_tv, 'Canales', autofocus: cont.isEmpty,
                  onTap: () => _push(context, const BrowseScreen(kind: Kind.live))),
              _BigButton(Icons.movie, 'Películas', onTap: () => _push(context, const BrowseScreen(kind: Kind.movie))),
              _BigButton(Icons.video_library, 'Series', onTap: () => _push(context, const BrowseScreen(kind: Kind.series))),
            ]),
          ),
        ),
        Shelf(title: 'Seguir viendo', height: 210, children: [
          for (final (i, e) in cont.indexed)
            FocusCard(
              autofocus: i == 0,
              width: 240,
              aspect: 16 / 9,
              title: e.title,
              subtitle: progressLabel(e.positionSecs, e.durationSecs),
              image: e.icon,
              progress: fraction(e.positionSecs, e.durationSecs),
              onTap: () => playWithChecks(context, (st) => st.resume(e)),
            ),
        ]),
        Shelf(title: 'Canales recientes', height: 190, children: [
          for (final e in s.recentChannels.take(20)) _channelCard(context, e),
        ]),
        Shelf(title: 'Canales favoritos', height: 190, children: [
          for (final e in s.favorites(Kind.live)) _channelCard(context, e),
        ]),
        Shelf(title: 'Películas favoritas', children: [
          for (final e in s.favorites(Kind.movie))
            FocusCard(
              title: e.name,
              image: e.icon,
              progress: e.positionSecs > 0 && !e.watched ? fraction(e.positionSecs, e.durationSecs) : null,
              badge: e.watched ? Icons.check_circle : null,
              onTap: () => _push(context, MovieScreen(item: _asItem(e))),
            ),
        ]),
        Shelf(title: 'Series favoritas', children: [
          for (final e in s.favorites(Kind.series))
            FocusCard(
              title: e.name,
              image: e.icon,
              icon: Icons.video_library,
              onTap: () => _push(context, SeriesScreen(item: _asItem(e))),
            ),
        ]),
        if (s.favorites(Kind.live).isEmpty && s.favorites(Kind.movie).isEmpty && s.favorites(Kind.series).isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text('Marca canales, películas y series con la estrella para tenerlos aquí.'),
          ),
        const SizedBox(height: 32),
      ]),
    );
  }

  Widget _channelCard(BuildContext context, LibraryEntry e) => FocusCard(
        width: 150,
        aspect: 16 / 10,
        title: e.name,
        image: e.icon,
        icon: Icons.live_tv,
        onTap: () => playWithChecks(context, (st) => st.playLive(_asItem(e))),
      );

  static CatalogItem _asItem(LibraryEntry e) => CatalogItem(
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
}

void _push(BuildContext context, Widget w) => Navigator.push(context, MaterialPageRoute(builder: (_) => w));

class _BigButton extends StatelessWidget {
  const _BigButton(this.icon, this.label, {required this.onTap, this.autofocus = false});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool autofocus;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 170,
        height: 64,
        child: FilledButton.tonalIcon(
          autofocus: autofocus,
          onPressed: onTap,
          icon: Icon(icon),
          label: Text(label, style: const TextStyle(fontSize: 16)),
        ),
      );
}
