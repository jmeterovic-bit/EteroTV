import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../iptv/xtream.dart';
import '../state/app_state.dart';
import 'google_sync.dart';
import 'pin.dart';

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

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final a = _account;
    final last = s.lastRefresh;
    String date(DateTime d) =>
        '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} '
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    return Scaffold(
      appBar: AppBar(title: const Text('Ajustes')),
      body: ListView(
        children: [
          const ListTile(
            title: Text('Cuenta IPTV', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          ListTile(
            leading: const Icon(Icons.dns),
            title: Text(s.creds?.server ?? ''),
            subtitle: Text('Usuario: ${s.creds?.username ?? ''}'),
          ),
          if (a != null) ...[
            ListTile(
              leading: const Icon(Icons.verified_user),
              title: Text('Estado: ${a.status}'),
              subtitle: a.expires == null ? null : Text('Vence: ${date(a.expires!)}'),
            ),
            ListTile(
              leading: const Icon(Icons.devices),
              title: Text('Reproducciones en uso: ${a.activeConnections} de ${a.maxConnections}'),
            ),
          ] else if (_accountError != null)
            ListTile(leading: const Icon(Icons.error_outline), title: Text(_accountError!)),
          const Divider(),
          const ListTile(
            title: Text('Lista', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          ListTile(
            leading: const Icon(Icons.list),
            title: Text(
              '${_counts[Kind.live] ?? '…'} canales, ${_counts[Kind.movie] ?? '…'} películas, '
              '${_counts[Kind.series] ?? '…'} series',
            ),
            subtitle: Text(
              last == null ? 'Nunca actualizada' : 'Actualizada el ${date(last)} (se actualiza sola cada 24 h)',
            ),
          ),
          ListTile(
            leading: s.refreshing
                ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.refresh),
            title: Text(s.refreshing ? s.refreshStep : 'Actualizar la lista ahora'),
            enabled: !s.refreshing,
            onTap: () async {
              await s.refreshCatalog();
              _load();
            },
          ),
          const Divider(),
          const ListTile(
            title: Text('Reproductor', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          ListTile(
            leading: Icon(_vlc == true ? Icons.check_circle : Icons.warning_amber),
            title: Text(_vlc == null ? 'Buscando VLC…' : (_vlc! ? 'VLC encontrado' : 'VLC no está instalado')),
          ),
          const Divider(),
          const ListTile(
            title: Text('Control remoto', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          const ListTile(
            leading: Icon(Icons.settings_remote_outlined),
            title: Text('Más opciones: mantén OK medio segundo, o el botón ≡ del control de Fire TV'),
            subtitle: Text(
              'Sirve en pósters, «Continuar viendo» y carpetas (proteger con PIN). Es lo mismo que mantener '
              'presionado en el celular.',
            ),
          ),
          const ListTile(
            leading: Icon(Icons.arrow_back),
            title: Text('Atrás vuelve a Inicio; en Inicio, Atrás dos veces cierra la app'),
            subtitle: Text('En los buscadores, OK abre el teclado y las flechas arriba y abajo salen del campo.'),
          ),
          const Divider(),
          const SyncSection(),
          const Divider(),
          const ListTile(
            title: Text('Carpetas con PIN', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          ListTile(
            leading: const Icon(Icons.lock_outline),
            title: Text(
              s.lockedCount == 0
                  ? 'Ninguna carpeta protegida'
                  : (s.lockedCount == 1 ? '1 carpeta protegida' : '${s.lockedCount} carpetas protegidas'),
            ),
            subtitle: const Text(
              'Para proteger una carpeta, ábrela desde «Carpetas y búsqueda» y toca el candado '
              '(o mantenla presionada: en el control, mantén OK).',
            ),
          ),
          if (s.hasPin) ...[
            ListTile(
              leading: const Icon(Icons.pin_outlined),
              title: const Text('Cambiar el PIN'),
              onTap: () async {
                final old = await askPin(context, title: 'PIN actual', forgot: true);
                if (old == null || !context.mounted) return;
                if (old == 'forgot') {
                  await resetPin(context);
                } else if (s.checkPin(old)) {
                  await createPin(context, title: 'PIN nuevo');
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('PIN incorrecto.')));
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.lock),
              title: const Text('Bloquear ya las carpetas abiertas'),
              onTap: () async {
                await s.lockAll();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Carpetas bloqueadas.')));
                }
              },
            ),
          ],
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('Cambiar de cuenta IPTV'),
            subtitle: const Text(
              'Borra el usuario y la contraseña de este dispositivo. Favoritos y progreso se conservan.',
            ),
            onTap: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (c) => AlertDialog(
                  title: const Text('¿Cambiar de cuenta?'),
                  content: const Text('Tendrás que volver a escribir la URL, el usuario y la contraseña.'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
                    TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Cambiar')),
                  ],
                ),
              );
              if (ok == true) {
                await s.signOut();
                if (context.mounted) Navigator.popUntil(context, (r) => r.isFirst);
              }
            },
          ),
          const AboutListTile(applicationName: 'EteroTV', applicationVersion: '0.6.4'),
        ],
      ),
    );
  }
}
