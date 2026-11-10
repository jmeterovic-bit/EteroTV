import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../iptv/xtream.dart';
import '../state/app_state.dart';
import 'browse_screen.dart' show catalogItemOf;
import 'cards.dart';
import 'lost_screen.dart';
import 'profiles_screen.dart';
import 'rows.dart';
import 'search_screen.dart';
import 'settings_screen.dart';
import 'theme.dart';
import 'tv_focus.dart';
import 'widgets.dart';
import 'i18n.dart';

/// Main frame: bottom bar on phones, side rail on wide screens and TV.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;
  DateTime? _lastBack;

  /// One focus scope per tab: it remembers the last item (for Atrás and for
  /// coming back from the side menu), and the arrows can leave it.
  final _scopes = List.generate(5, (i) => TvRegionScope(debugLabel: 'tab $i'));

  /// Choosing «Buscar» puts the cursor in its field (Jose, 2026-11-10).
  final _typeSearch = ChangeNotifier();
  static const _searchTab = 4;

  void _select(int i) {
    setState(() => _tab = i);
    if (i == _searchTab) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
        if (mounted) _typeSearch.notifyListeners();
      });
    }
  }

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
    _typeSearch.dispose();
    for (final s in _scopes) {
      s.dispose();
    }
    super.dispose();
  }

  /// Atrás: from another tab, back to Inicio; on Inicio, a second Atrás
  /// within 2 s closes the app (so one press too many does not).
  void _back() {
    if (_tab != 0) {
      final home = _scopes[0];
      final hadFocus = home.focusedChild != null;
      setState(() => _tab = 0);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        home.requestFocus();
        if (!hadFocus) home.nextFocus();
      });
      return;
    }
    final now = DateTime.now();
    final last = _lastBack;
    if (last != null && now.difference(last) < const Duration(seconds: 2)) {
      SystemNavigator.pop();
      return;
    }
    _lastBack = now;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(tr('Pulsa Atrás otra vez para salir.')), duration: Duration(seconds: 2)));
  }

  static List<(IconData, IconData, String)> get _dest => [
    (Icons.home_outlined, Icons.home, tr('Inicio')),
    (Icons.video_library_outlined, Icons.video_library, tr('Series')),
    (Icons.movie_outlined, Icons.movie, tr('Películas')),
    (Icons.live_tv_outlined, Icons.live_tv, tr('Canales')),
    (Icons.search, Icons.search, tr('Buscar')),
  ];

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 800;
    final pages = [
      const HomeTab(),
      const KindTab(kind: Kind.series),
      const KindTab(kind: Kind.movie),
      const KindTab(kind: Kind.live),
      SearchScreen(autofocus: false, typeNow: _typeSearch),
    ];
    final body = IndexedStack(
      index: _tab,
      children: [for (var i = 0; i < pages.length; i++) FocusScope(node: _scopes[i], child: pages[i])],
    );
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: wide ? _wide(body) : _narrow(body),
    );
  }

  Widget _wide(Widget body) => Scaffold(
    body: Row(
      children: [
        FocusTraversalGroup(
          child: NavigationRail(
            backgroundColor: const Color(0xFF101010),
            selectedIndex: _tab,
            onDestinationSelected: _select,
            labelType: NavigationRailLabelType.all,
            indicatorColor: accent.withValues(alpha: 0.25),
            leading: const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: ProfileButton()),
            trailing: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: IconButton(
                tooltip: tr('Ajustes'),
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

  Widget _narrow(Widget body) => Scaffold(
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
            onDestinationSelected: _select,
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
            Text(tr('Inicio'), style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        actions: [
          if (!wide) const Padding(padding: EdgeInsets.symmetric(horizontal: 4), child: ProfileButton(size: 32)),
          if (!wide)
            IconButton(
              tooltip: tr('Ajustes'),
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
              subtitle: Text(tr('La primera vez puede tardar un par de minutos.')),
            ),
          if (s.error != null)
            ListTile(
              leading: const Icon(Icons.error_outline, color: Colors.redAccent),
              title: Text(s.error!),
              trailing: TextButton(onPressed: s.refreshCatalog, child: Text(tr('Reintentar'))),
            ),
          if (s.lost.isNotEmpty)
            Card(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: ListTile(
                leading: const Icon(Icons.find_replace),
                title: Text(tr('{0} favoritos o progresos no aparecen en la lista nueva', [s.lost.length])),
                subtitle: Text(tr('Te sugiero los más parecidos para reemplazarlos.')),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LostScreen())),
              ),
            ),
          if (cont.isNotEmpty) HeroBanner(entry: cont.first),
          Shelf(
            title: tr('Continuar viendo'),
            height: 200,
            children: [for (final e in cont) ContinueCard(entry: e)],
          ),
          Shelf(
            title: tr('Lo nuevo'),
            height: posterRowHeight,
            children: [for (final (item, kind) in s.whatsNew) PosterCard(item: item, news: kind)],
          ),
          Shelf(
            title: tr('Mi lista'),
            height: posterRowHeight,
            children: [for (final e in s.myList) PosterCard(item: catalogItemOf(e))],
          ),
          Shelf(
            title: tr('Canales favoritos'),
            height: channelRowHeight,
            children: [for (final e in s.favorites(Kind.live)) ChannelCard(item: catalogItemOf(e))],
          ),
          if (cont.isEmpty && s.myList.isEmpty && s.favorites(Kind.live).isEmpty)
            Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                tr(
                  'Marca series, películas y canales con la estrella para tenerlos aquí. Lo que dejes a medias aparece en «Continuar viendo».',
                ),
              ),
            ),
          for (final c in _rows.where((c) => !s.isLocked(c)))
            CategoryRow(
              key: ValueKey('${c.kind.name}:${c.id}@${s.lastRefresh}'),
              category: c,
              titlePrefix: c.kind == Kind.series ? tr('Series · ') : tr('Películas · '),
            ),
        ],
      ),
    );
  }
}
