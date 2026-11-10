import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../iptv/xtream.dart';
import '../logic/progress.dart';
import '../state/app_state.dart';
import 'play.dart';
import 'widgets.dart';
import 'i18n.dart';

class MovieScreen extends StatefulWidget {
  const MovieScreen({super.key, required this.item});
  final CatalogItem item;

  @override
  State<MovieScreen> createState() => _MovieScreenState();
}

class _MovieScreenState extends State<MovieScreen> {
  MovieInfo? _info;

  @override
  void initState() {
    super.initState();
    final x = context.read<AppState>().client;
    x
        ?.movieInfo(widget.item.id)
        .then((i) {
          if (mounted) setState(() => _info = i);
        })
        .catchError((_) {})
        .whenComplete(x.close);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final e = s.entry(Kind.movie, widget.item.id);
    final pos = e?.positionSecs ?? 0;
    final dur = (e?.durationSecs ?? 0) > 0 ? e!.durationSecs : (_info?.durationSecs ?? 0);
    final canResume = e != null && !e.watched && resumeFrom(pos, dur, watched: false) > 0;
    final fav = e?.favorite ?? false;
    return Scaffold(
      appBar: AppBar(title: Text(widget.item.name)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Wrap(
          spacing: 24,
          runSpacing: 16,
          children: [
            SizedBox(
              width: 200,
              child: AspectRatio(aspectRatio: 2 / 3, child: NetImage(widget.item.icon)),
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.item.name, style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 4),
                  Text([if (widget.item.year.isNotEmpty) widget.item.year, if (dur > 0) formatTime(dur)].join(' · ')),
                  if (canResume) ...[
                    const SizedBox(height: 8),
                    LinearProgressIndicator(value: fraction(pos, dur)),
                    Text(tr('Vas en {0}', [progressLabel(pos, dur)])),
                  ],
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      FilledButton.icon(
                        autofocus: true,
                        icon: const Icon(Icons.play_arrow),
                        label: Text(canResume ? tr('Continuar') : tr('Ver')),
                        onPressed: () => playWithChecks(context, (st) => st.playMovie(widget.item)),
                      ),
                      if (canResume)
                        OutlinedButton.icon(
                          icon: const Icon(Icons.replay),
                          label: Text(tr('Desde el principio')),
                          onPressed: () async {
                            await s.setWatched(e, false);
                            if (context.mounted) await playWithChecks(context, (st) => st.playMovie(widget.item));
                          },
                        ),
                      OutlinedButton.icon(
                        icon: Icon(fav ? Icons.star : Icons.star_border),
                        label: Text(fav ? tr('En favoritos') : tr('Favorito')),
                        onPressed: () => s.toggleFavorite(widget.item),
                      ),
                      OutlinedButton.icon(
                        icon: Icon(e?.watched == true ? Icons.check_circle : Icons.check_circle_outline),
                        label: Text(e?.watched == true ? tr('Vista (desmarcar)') : tr('Marcar como vista')),
                        onPressed: () => s.setMovieWatched(widget.item, !(e?.watched ?? false)),
                      ),
                      if (canResume)
                        OutlinedButton.icon(
                          icon: const Icon(Icons.close),
                          label: Text(tr('Quitar de Seguir viendo')),
                          onPressed: () => s.removeFromInProgress(widget.item),
                        ),
                    ],
                  ),
                  if ((_info?.plot ?? '').isNotEmpty) ...[const SizedBox(height: 16), Text(_info!.plot)],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
