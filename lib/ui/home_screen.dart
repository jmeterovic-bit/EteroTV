import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../iptv/xtream.dart';
import '../state/app_state.dart';
import 'browse_screen.dart' show catalogItemOf;
import 'cards.dart';
import 'lost_screen.dart';
import 'rows.dart';
import 'search_screen.dart';
import 'settings_screen.dart';
import 'theme.dart';
import 'widgets.dart';

/// Main frame: bottom bar on phones, side rail on wide screens and TV.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;

  /// Folders opened with the PIN lock again after an hour away from the app.
  static const relockAfter = Duration(hours: 1);
  late final AppLifecycleListener _life;
  DateTime? _hiddenAt;

  @override
  void initState() {
    super.initState();
    _life = AppLifecycleListener(
      onHide: () => _hiddenAt = DateTime.now(),
      onShow: () {
        final t = _hiddenAt;
        if (t != null && DateTime.now().difference(t) > relockAfter) context.read<AppState>().lockAll();
      },
    );
  }

  @override
  void dispose() {
    _life.dispose();
    super.dispose();
  }

  static const _dest = [
    (Icons.home_outlined, Icons.home, 'Inicio'),
    (Icons.video_library_outlined, Icons.video_library, 'Series'),
    (Icons.movie_outlined, Icons.movie, 'Películas'),
    (Icons.live_tv_outlined, Icons.live_tv, 'Canales'),
    (Icons.search, Icons.search, 'Buscar'),
  ];

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 800;
    final pages = [
      const HomeTab(),
      const KindTab(kind: Kind.series),
      const KindTab(kind: Kind.movie),
      const KindTab(kind: Kind.live),
      const SearchScreen(autofocus: false),
    ];
    final body = IndexedStack(index: _tab, children: pages);
    if (wide) {
      return Scaffold(
        body: Row(
          children: [
            FocusTraversalGroup(
              child: NavigationRail(
                backgroundColor: const Color(0xFF101010),
                selectedIndex: _tab,
                onDestinationSelected: (i) => setState(() => _tab = i),
                labelType: NavigationRailLabelType.all,
                indicatorColor: accent.withValues(alpha: 0.25),
                leading: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Image.asset('assets/icon.png', width: 40, height: 40),
                ),
                trailing: Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: IconButton(
                    tooltip: 'Ajustes',
                    icon: const Icon(Icons.settings_outlined),
                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())),
                  ),
                ),
                destinations: [
                  for (final d in _dest)
                    NavigationRailDestination(
                      icon: Icon(d.$1),
                      selectedIcon: Icon(d.$2, color: accent),
                      label: Text(d.$3),
                    ),
                ],
              ),
            ),
            const VerticalDivider(width: 1),
            Expanded(child: FocusTraversalGroup(child: body)),
          ],
        ),
      );
    }
    return Scaffold(
      extendBody: true,
      body: body,
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(32),
            child: NavigationBar(
              height: 64,
              backgroundColor: const Color(0xEE1F1F1F),
              indicatorColor: accent.withValues(alpha: 0.25),
              labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
              selectedIndex: _tab,
              onDestinationSelected: (i) => setState(() => _tab = i),
              destinations: [
                for (final d in _dest)
                  NavigationDestination(
                    icon: Icon(d.$1),
                    selectedIcon: Icon(d.$2, color: accent),
                    label: d.$3,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Inicio: last thing watched, Continuar viendo, Mi lista, Canales favoritos
/// and the first categories of series and movies.
class HomeTab extends StatefulWidget {
  const HomeTab({super.key});

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  List<Category> _rows = const [];
  DateTime? _loadedFor;

  static const rowsPerKind = 5;

  Future<void> _loadRows(AppState s) async {
    _loadedFor = s.lastRefresh;
    final series = await s.db.categories(Kind.series);
    final movies = await s.db.categories(Kind.movie);
    if (!mounted) return;
    setState(() => _rows = [...series.take(rowsPerKind), ...movies.take(rowsPerKind)]);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    if (_loadedFor != s.lastRefresh || (_rows.isEmpty && !s.refreshing && _loadedFor == null)) {
      _loadRows(s);
    }
    final cont = s.continueWatching;
    final wide = MediaQuery.sizeOf(context).width >= 800;
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        titleSpacing: 16,
        title: Row(
          children: [
            if (!wide) ...[Image.asset('assets/icon.png', width: 32, height: 32), const SizedBox(width: 10)],
            const Text('Inicio', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        actions: [
          if (!wide)
            IconButton(
              tooltip: 'Ajustes',
              icon: const Icon(Icons.settings_outlined),
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 96),
        children: [
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
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: ListTile(
                leading: const Icon(Icons.find_replace),
                title: Text('${s.lost.length} favoritos o progresos no aparecen en la lista nueva'),
                subtitle: const Text('Te sugiero los más parecidos para reemplazarlos.'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LostScreen())),
              ),
            ),
          if (cont.isNotEmpty) HeroBanner(entry: cont.first),
          Shelf(
            title: 'Continuar viendo',
            height: 200,
            children: [for (final e in cont) ContinueCard(entry: e)],
          ),
          Shelf(
            title: 'Mi lista',
            height: posterRowHeight,
            children: [for (final e in s.myList) PosterCard(item: catalogItemOf(e))],
          ),
          Shelf(
            title: 'Canales favoritos',
            height: channelRowHeight,
            children: [for (final e in s.favorites(Kind.live)) ChannelCard(item: catalogItemOf(e))],
          ),
          if (cont.isEmpty && s.myList.isEmpty && s.favorites(Kind.live).isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Marca series, películas y canales con la estrella para tenerlos aquí. '
                'Lo que dejes a medias aparece en «Continuar viendo».',
              ),
            ),
          for (final c in _rows.where((c) => !s.isLocked(c)))
            CategoryRow(
              key: ValueKey('${c.kind.name}:${c.id}'),
              category: c,
              titlePrefix: c.kind == Kind.series ? 'Series · ' : 'Películas · ',
            ),
        ],
      ),
    );
  }
}
