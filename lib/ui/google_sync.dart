import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../platform/device.dart';
import '../sync/google_auth.dart';
import '../sync/sync_service.dart';
import 'theme.dart';

/// Connects this device to Google Drive: browser on phone and PC, a code on
/// screen on TV (or when chosen). Returns true when connected.
Future<bool> connectGoogle(BuildContext context) async {
  final sync = context.read<SyncService>();
  final tv = await isTv();
  if (!context.mounted) return false;
  var useCode = tv || !GoogleAuth.browserAvailable;
  if (!useCode && GoogleAuth.codeAvailable) {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
              title: Text('Conectar con Google', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            ListTile(
              leading: const Icon(Icons.open_in_browser),
              title: const Text('En este dispositivo'),
              subtitle: const Text('Se abre el navegador para elegir tu cuenta.'),
              onTap: () => Navigator.pop(c, 'browser'),
            ),
            ListTile(
              leading: const Icon(Icons.pin),
              title: const Text('Con un código'),
              subtitle: const Text('Escribes un código en google.com/device desde otro equipo.'),
              onTap: () => Navigator.pop(c, 'code'),
            ),
          ],
        ),
      ),
    );
    if (choice == null) return false;
    useCode = choice == 'code';
  }
  if (!context.mounted) return false;
  if (useCode) {
    final ok = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => const DeviceCodeScreen()));
    return ok ?? false;
  }
  final messenger = ScaffoldMessenger.of(context);
  try {
    await sync.signInWithBrowser();
    messenger.showSnackBar(const SnackBar(content: Text('Google conectado.')));
    return true;
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('No se pudo conectar: $e')));
    return false;
  }
}

/// TV: shows the address and the code, and waits for the approval.
class DeviceCodeScreen extends StatefulWidget {
  const DeviceCodeScreen({super.key});

  @override
  State<DeviceCodeScreen> createState() => _DeviceCodeScreenState();
}

class _DeviceCodeScreenState extends State<DeviceCodeScreen> {
  DeviceCode? _code;
  String? _error;
  bool _closed = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _closed = true;
    super.dispose();
  }

  Future<void> _start() async {
    final sync = context.read<SyncService>();
    setState(() {
      _code = null;
      _error = null;
    });
    try {
      final d = await sync.startDeviceFlow();
      if (!mounted) return;
      setState(() => _code = d);
      await sync.finishDeviceFlow(d, cancelled: () => _closed);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted && !_closed) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _code;
    final big = Theme.of(context).textTheme.displaySmall
        ?.copyWith(color: accent, fontWeight: FontWeight.bold, letterSpacing: 4);
    return Scaffold(
      appBar: AppBar(title: const Text('Conectar con Google')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: _error != null
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_error!, textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    FilledButton(autofocus: true, onPressed: _start, child: const Text('Pedir otro código')),
                  ],
                )
              : d == null
              ? const CircularProgressIndicator()
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('En el celular o el PC, entra a', textAlign: TextAlign.center),
                    const SizedBox(height: 8),
                    SelectableText(
                      d.url.replaceFirst('https://', ''),
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 16),
                    const Text('y escribe este código:'),
                    const SizedBox(height: 8),
                    SelectableText(d.userCode, style: big),
                    const SizedBox(height: 24),
                    const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                        SizedBox(width: 12),
                        Text('Esperando que lo apruebes…'),
                      ],
                    ),
                    const SizedBox(height: 24),
                    OutlinedButton(
                      autofocus: true,
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancelar'),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

/// Settings section: state of the sync and its buttons.
class SyncSection extends StatelessWidget {
  const SyncSection({super.key});

  String _ago(DateTime t) {
    final m = DateTime.now().difference(t).inMinutes;
    if (m < 1) return 'hace un momento';
    if (m < 60) return 'hace $m min';
    return 'a las ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final sync = context.watch<SyncService>();
    final header = const ListTile(
      title: Text('Sincronización (Google Drive)', style: TextStyle(fontWeight: FontWeight.bold)),
    );
    if (!GoogleAuth.configured) {
      return Column(
        children: [
          header,
          const ListTile(
            leading: Icon(Icons.cloud_off),
            title: Text('Esta versión se compiló sin la conexión con Google.'),
          ),
        ],
      );
    }
    if (!sync.signedIn) {
      return Column(
        children: [
          header,
          ListTile(
            leading: const Icon(Icons.cloud_outlined),
            title: const Text('Conectar con Google'),
            subtitle: const Text(
              'Favoritos, avance, cuenta IPTV, PIN y carpetas protegidas quedan iguales en todos tus dispositivos. '
              'Se guardan en una carpeta oculta de tu Drive que solo EteroTV puede leer.',
            ),
            onTap: () => connectGoogle(context),
          ),
        ],
      );
    }
    final last = sync.lastSync;
    return Column(
      children: [
        header,
        ListTile(
          leading: sync.syncing
              ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
              : Icon(
                  sync.error == null ? Icons.cloud_done : Icons.cloud_off,
                  color: sync.error == null ? null : Colors.redAccent,
                ),
          title: Text(
            sync.syncing
                ? 'Sincronizando…'
                : sync.error != null
                ? 'No se pudo sincronizar'
                : last == null
                ? 'Conectado'
                : 'Sincronizado ${_ago(last)}',
          ),
          subtitle: Text(
            sync.error ??
                (sync.lastDevices == 0
                    ? 'Aún no hay otros dispositivos conectados.'
                    : sync.lastDevices == 1
                    ? 'Con 1 dispositivo más.'
                    : 'Con ${sync.lastDevices} dispositivos más.'),
          ),
          onTap: sync.syncing ? null : sync.syncNow,
          trailing: TextButton(onPressed: sync.syncing ? null : sync.syncNow, child: const Text('Sincronizar')),
        ),
        ListTile(
          leading: const Icon(Icons.link_off),
          title: const Text('Desconectar Google en este dispositivo'),
          subtitle: const Text('Lo de este dispositivo se queda; deja de compartirse.'),
          onTap: () async {
            final ok = await showDialog<bool>(
              context: context,
              builder: (c) => AlertDialog(
                title: const Text('¿Desconectar Google?'),
                content: const Text('Este dispositivo deja de sincronizar. Puedes volver a conectarlo cuando quieras.'),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
                  TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Desconectar')),
                ],
              ),
            );
            if (ok == true) await sync.signOut();
          },
        ),
      ],
    );
  }
}
