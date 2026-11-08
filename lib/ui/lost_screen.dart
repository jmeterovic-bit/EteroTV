import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/library.dart';
import '../iptv/xtream.dart';
import '../logic/progress.dart';
import '../logic/rematch.dart';
import '../state/app_state.dart';
import 'browse_screen.dart';
import 'widgets.dart';

/// After a list update: favourites and progress whose item disappeared,
/// each with the closest matches. Nothing changes until the user picks.
class LostScreen extends StatelessWidget {
  const LostScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final lost = context.watch<AppState>().lost;
    return Scaffold(
      appBar: AppBar(title: const Text('Revisar favoritos perdidos')),
      body: lost.isEmpty
          ? const Center(child: Text('Todo en orden.'))
          : ListView(children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('Tu proveedor cambió estos elementos en la lista nueva. Elige el reemplazo correcto '
                    'o descártalos. El progreso pasa al que elijas.'),
              ),
              for (final e in lost) _LostTile(key: ValueKey(e.key), entry: e),
            ]),
    );
  }
}

class _LostTile extends StatefulWidget {
  const _LostTile({super.key, required this.entry});
  final LibraryEntry entry;

  @override
  State<_LostTile> createState() => _LostTileState();
}

class _LostTileState extends State<_LostTile> {
  List<Candidate>? _candidates;

  @override
  void initState() {
    super.initState();
    context.read<AppState>().candidatesFor(widget.entry).then((c) {
      if (mounted) setState(() => _candidates = c);
    });
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.entry;
    final s = context.read<AppState>();
    final name = e.kind == Kind.episode ? e.seriesName : e.name;
    final kind = e.kind == Kind.episode ? Kind.series : e.kind;
    final detail = [
      kindTitle(kind),
      if (e.year.isNotEmpty) e.year,
      if (e.kind == Kind.movie && e.durationSecs > 0) formatTime(e.durationSecs),
      if (e.favorite) 'favorito',
      if (e.positionSecs > 0 && !e.watched) 'en ${formatTime(e.positionSecs)}',
    ].join(' · ');
    final c = _candidates;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(name, style: Theme.of(context).textTheme.titleMedium),
          Text(detail, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 8),
          if (c == null)
            const LinearProgressIndicator()
          else if (c.isEmpty)
            const Text('No encontré nada parecido.')
          else
            for (final cand in c)
              ListTile(
                dense: true,
                leading: SizedBox(width: 36, height: 50, child: NetImage(cand.item.icon)),
                title: Text(cand.item.name),
                subtitle: Text([
                  '${(cand.score * 100).round()} % parecido',
                  if (cand.item.year.isNotEmpty) cand.item.year,
                  if (cand.durationSecs > 0) formatTime(cand.durationSecs),
                  ...cand.reasons,
                ].join(' · ')),
                trailing: cand.safe ? const Icon(Icons.verified, color: Colors.greenAccent) : null,
                onTap: () => s.replaceLost(e, cand.item),
              ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(onPressed: () => s.dismissLost(e), child: const Text('Descartar')),
          ),
        ]),
      ),
    );
  }
}
