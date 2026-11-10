import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../iptv/xtream.dart';
import '../player/vlc.dart';
import '../state/app_state.dart';
import 'google_sync.dart';
import 'pin.dart';
import 'profiles_screen.dart';
import 'i18n.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  AccountInfo? _account;
  String? _accountError;
  bool? _vlc;
  final Map<Kind, int> _counts = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = context.read<AppState>();
    s.vlc.available().then((v) {
      if (mounted) setState(() => _vlc = v);
    });
    for (final k in [Kind.live, Kind.movie, Kind.series]) {
      final n = await s.db.count(k);
      if (mounted) setState(() => _counts[k] = n);
    }
    try {
      final a = await s.account();
      if (mounted) setState(() => _account = a);
    } catch (e) {
      if (mounted) setState(() => _accountError = e.toString());
    }
  }

  /// 'own' (EteroTV), or an outside player: VLC, and on Android Just Player
  /// and MX Player.
  Future<void> _choosePlayer(AppState s) async {
    final android = s.androidPlayer;
    final values = [
      'own',
      ...android != null ? AndroidPlayer.values.map((p) => p.name) : ['vlc'],
    ];
    final current = s.useOwnPlayer ? 'own' : (android?.name ?? 'vlc');
    final v = await _choose(
      tr('Reproducir con'),
      values,
      current,
      (v) => v == 'own' ? tr('EteroTV (propio)') : AndroidPlayer.fromName(v).label,
    );
    if (v == null) return;
    if (v == 'own') {
      await s.setUseOwnPlayer(true);
    } else if (android != null) {
      await s.setAndroidPlayer(AndroidPlayer.fromName(v));
    } else {
      await s.setUseOwnPlayer(false);
    }
  }

  Future<T?> _choose<T>(String title, List<T> values, T current, String Function(T) label) => showDialog<T>(
    context: context,
    builder: (c) => SimpleDialog(
      title: Text(title),
      children: [
        for (final v in values)
          ListTile(
            autofocus: v == current,
            leading: Icon(v == current ? Icons.radio_button_checked : Icons.radio_button_unchecked),
            title: Text(label(v)),
            onTap: () => Navigator.pop(c, v),
          ),
      ],
    ),
  );

  /// Android: the players take no language from another app, so this says
  /// where to set it in the one this device uses.
  void _playerLanguageHelp(AndroidPlayer p) => showDialog<void>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(tr('Audio y subtítulos en {0}', [p.label])),
      content: SingleChildScrollView(
        child: Text(switch (p) {
          AndroidPlayer.vlc => tr(
            'Se configura una vez en VLC:\n\n'
            '1. Abre VLC y entra a Ajustes (⚙, o «Más» → Ajustes).\n'
            '2. Audio → «Idioma de audio preferido».\n'
            '3. Subtítulos → «Idioma de subtítulos preferido».\n\n'
            'Si el video no tiene ese idioma, VLC usa el que trae el video. '
            'Los nombres pueden cambiar un poco según la versión de VLC.',
          ),
          AndroidPlayer.just => tr(
            'Se configura una vez:\n\n'
            '1. Audio: abre Just Player, entra a sus ajustes (⚙) y elige el idioma en «Idioma del audio» '
            '(por defecto usa el idioma del aparato).\n'
            '2. Subtítulos: Just Player sigue los subtítulos de Android. En la TV: Ajustes → Accesibilidad → '
            'Subtítulos → Idioma.\n\n'
            'Si el video no tiene ese idioma, se usa el que trae el video.',
          ),
          AndroidPlayer.mx => tr(
            'Se configura una vez en MX Player:\n\n'
            '1. Ajustes → Audio → «Idioma de audio».\n'
            '2. Ajustes → Subtítulos → «Idioma preferido».\n\n'
            'Si el video no tiene ese idioma, se usa el que trae el video.',
          ),
        }),
      ),
      actions: [TextButton(autofocus: true, onPressed: () => Navigator.pop(c), child: Text(tr('Entendido')))],
    ),
  );

  String _trackLabel(TrackLang l) => switch (l) {
    TrackLang.original => tr('Original del video'),
    TrackLang.none => tr('Sin subtítulos'),
    TrackLang.es => tr('Español'),
    TrackLang.en => tr('Inglés'),
    TrackLang.fr => tr('Francés'),
  };

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final a = _account;
    final last = s.lastRefresh;
    String date(DateTime d) =>
        '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} '
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    return Scaffold(
      appBar: AppBar(title: Text(tr('Ajustes'))),
      body: ListView(
        children: [
          ListTile(
            leading: AvatarCircle(avatar: s.profile.avatar, size: 40),
            title: Text(tr('Perfil: {0}', [AppState.profileName(s.profile)])),
            subtitle: Text(tr('Cambiar de perfil, o agregar y editar perfiles')),
            onTap: () => switchProfile(context),
          ),
          const Divider(),
          ListTile(
            title: Text(tr('Cuenta IPTV'), style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          ListTile(
            leading: const Icon(Icons.dns),
            title: Text(s.creds?.server ?? ''),
            subtitle: Text(tr('Usuario: {0}', [s.creds?.username ?? ''])),
          ),
          if (a != null) ...[
            ListTile(
              leading: const Icon(Icons.verified_user),
              title: Text(tr('Estado: {0}', [a.status])),
              subtitle: a.expires == null ? null : Text(tr('Vence: {0}', [date(a.expires!)])),
            ),
            ListTile(
              leading: const Icon(Icons.devices),
              title: Text(tr('Reproducciones en uso: {0} de {1}', [a.activeConnections, a.maxConnections])),
            ),
          ] else if (_accountError != null)
            ListTile(leading: const Icon(Icons.error_outline), title: Text(_accountError!)),
          const Divider(),
          ListTile(
            title: Text(tr('Lista'), style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          ListTile(
            leading: const Icon(Icons.list),
            title: Text(
              tr('{0} canales, {1} películas, {2} series', [
                _counts[Kind.live] ?? '…',
                _counts[Kind.movie] ?? '…',
                _counts[Kind.series] ?? '…',
              ]),
            ),
            subtitle: Text(
              last == null
                  ? tr('Nunca actualizada')
                  : tr('Actualizada el {0} (se actualiza sola cada 24 h)', [date(last)]),
            ),
          ),
          ListTile(
            leading: s.refreshing
                ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.refresh),
            title: Text(s.refreshing ? s.refreshStep : tr('Actualizar la lista ahora')),
            enabled: !s.refreshing,
            onTap: () async {
              await s.refreshCatalog();
              _load();
            },
          ),
          const Divider(),
          ListTile(
            title: Text(tr('Reproductor'), style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          ListTile(
            leading: const Icon(Icons.play_circle_outline),
            title: Text(tr('Reproducir con: {0}', [s.player.name])),
            subtitle: Text(
              s.androidPlayer != null
                  ? tr(
                      'Solo en este aparato. EteroTV es el normal; VLC, Just Player o MX Player son alternativas (tienen que estar instalados). Todos guardan hasta dónde viste.',
                    )
                  : tr(
                      'Solo en este aparato. EteroTV es el normal; VLC es la alternativa (tiene que estar instalado).',
                    ),
            ),
            onTap: () => _choosePlayer(s),
          ),
          if (s.useOwnPlayer)
            SwitchListTile(
              secondary: const Icon(Icons.memory),
              title: Text(tr('Decodificar con el chip del aparato')),
              subtitle: Text(
                tr('Más fluido. Apágalo si la imagen se ve negra, verde o se corta (vale para el próximo video).'),
              ),
              value: s.hardwareDecoding,
              onChanged: s.setHardwareDecoding,
            )
          else if (s.androidPlayer == null)
            ListTile(
              leading: Icon(_vlc == true ? Icons.check_circle : Icons.warning_amber),
              title: Text(
                _vlc == null ? tr('Buscando VLC…') : (_vlc! ? tr('VLC encontrado') : tr('VLC no está instalado')),
              ),
            ),
          const Divider(),
          ListTile(
            title: Text(tr('Idioma'), style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
          ListTile(
            leading: const Icon(Icons.translate),
            title: Text(tr('Idioma de la app: {0}', [s.uiLanguage.label])),
            subtitle: Text(tr('De este perfil, en todos tus aparatos.')),
            onTap: () async {
              final l = await _choose(tr('Idioma de la app'), UiLang.values, s.uiLanguage, (l) => l.label);
              if (l != null) await s.setUiLanguage(l);
            },
          ),
          if (s.androidPlayer case final p? when !s.useOwnPlayer)
            ListTile(
              leading: const Icon(Icons.subtitles_outlined),
              title: Text(tr('Audio y subtítulos en {0}', [p.label])),
              subtitle: Text(tr('Se eligen en el reproductor: toca para ver cómo.')),
              onTap: () => _playerLanguageHelp(p),
            )
          else ...[
            ListTile(
              leading: const Icon(Icons.record_voice_over_outlined),
              title: Text(tr('Audio: {0}', [_trackLabel(s.audioLang)])),
              subtitle: Text(tr('Si el video no lo tiene, se usa su audio original.')),
              onTap: () async {
                const v = [TrackLang.original, TrackLang.es, TrackLang.en, TrackLang.fr];
                final l = await _choose(tr('Idioma del audio'), v, s.audioLang, _trackLabel);
                if (l != null) await s.setAudioLang(l);
              },
            ),
            ListTile(
              leading: const Icon(Icons.subtitles_outlined),
              title: Text(tr('Subtítulos: {0}', [_trackLabel(s.subLang)])),
              subtitle: Text(tr('Si el video no los tiene en ese idioma, no se muestran.')),
              onTap: () async {
                const v = [TrackLang.none, TrackLang.es, TrackLang.en, TrackLang.fr];
                final l = await _choose(tr('Idioma de los subtítulos'), v, s.subLang, _trackLabel);
                if (l != null) await s.setSubLang(l);
              },
            ),
          ],
          const Divider(),
          ListTile(
            title: Text(tr('Control remoto'), style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          ListTile(
            leading: Icon(Icons.settings_remote_outlined),
            title: Text(tr('Más opciones: mantén OK medio segundo, o el botón ≡ del control de Fire TV')),
            subtitle: Text(
              tr(
                'Sirve en pósters, «Continuar viendo» y carpetas (proteger con PIN). Es lo mismo que mantener presionado en el celular.',
              ),
            ),
          ),
          ListTile(
            leading: Icon(Icons.arrow_back),
            title: Text(tr('Atrás vuelve a Inicio; en Inicio, Atrás dos veces cierra la app')),
            subtitle: Text(tr('En los buscadores, OK abre el teclado y las flechas arriba y abajo salen del campo.')),
          ),
          const Divider(),
          const SyncSection(),
          const Divider(),
          ListTile(
            title: Text(tr('Carpetas con PIN'), style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          ListTile(
            leading: const Icon(Icons.lock_outline),
            title: Text(
              s.lockedCount == 0
                  ? tr('Ninguna carpeta protegida')
                  : (s.lockedCount == 1 ? tr('1 carpeta protegida') : tr('{0} carpetas protegidas', [s.lockedCount])),
            ),
            subtitle: Text(
              tr(
                'Para proteger una carpeta, ábrela desde «Carpetas y búsqueda» y toca el candado (o mantenla presionada: en el control, mantén OK).',
              ),
            ),
          ),
          if (s.hasPin) ...[
            ListTile(
              leading: const Icon(Icons.pin_outlined),
              title: Text(tr('Cambiar el PIN')),
              onTap: () async {
                final old = await askPin(context, title: tr('PIN actual'), forgot: true);
                if (old == null || !context.mounted) return;
                if (old == 'forgot') {
                  await resetPin(context);
                } else if (s.checkPin(old)) {
                  await createPin(context, title: tr('PIN nuevo'));
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('PIN incorrecto.'))));
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.lock),
              title: Text(tr('Bloquear ya las carpetas abiertas')),
              onTap: () async {
                await s.lockAll();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('Carpetas bloqueadas.'))));
                }
              },
            ),
          ],
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout),
            title: Text(tr('Cambiar de cuenta IPTV')),
            subtitle: Text(
              tr('Borra el usuario y la contraseña de este dispositivo. Favoritos y progreso se conservan.'),
            ),
            onTap: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (c) => AlertDialog(
                  title: Text(tr('¿Cambiar de cuenta?')),
                  content: Text(tr('Tendrás que volver a escribir la URL, el usuario y la contraseña.')),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr('Cancelar'))),
                    TextButton(onPressed: () => Navigator.pop(c, true), child: Text(tr('Cambiar'))),
                  ],
                ),
              );
              if (ok == true) {
                await s.signOut();
                if (context.mounted) Navigator.popUntil(context, (r) => r.isFirst);
              }
            },
          ),
          const AboutListTile(applicationName: 'EteroTV', applicationVersion: '1.1.0'),
        ],
      ),
    );
  }
}
