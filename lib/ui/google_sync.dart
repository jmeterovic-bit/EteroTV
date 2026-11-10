import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../platform/device.dart';
import '../sync/google_auth.dart';
import '../sync/sync_service.dart';
import '../sync/tv_link.dart';
import 'remote.dart';
import 'theme.dart';

/// Connects this device to Google Drive: the browser on phone and PC; on a
/// TV (or when chosen), the session comes from a device already connected.
/// Returns true when connected.
Future<bool> connectGoogle(BuildContext context) async {
  final sync = context.read<SyncService>();
  var fromOther = runningOnTv;
  if (!fromOther) {
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
              leading: const Icon(Icons.devices),
              title: const Text('Desde otro dispositivo ya conectado'),
              subtitle: const Text('Muestra un código para escribirlo en el otro equipo, en la misma red.'),
              onTap: () => Navigator.pop(c, 'other'),
            ),
          ],
        ),
      ),
    );
    if (choice == null) return false;
    fromOther = choice == 'other';
  }
  if (!context.mounted) return false;
  if (fromOther) {
    final ok = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => const ReceiveSessionScreen()));
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

Future<List<String>> _ownAddresses() async {
  try {
    return [
      for (final i in await NetworkInterface.list(type: InternetAddressType.IPv4))
        for (final a in i.addresses) a.address,
    ];
  } catch (_) {
    return const [];
  }
}

/// TV: shows a code and waits for a connected phone or PC to send the session.
class ReceiveSessionScreen extends StatefulWidget {
  const ReceiveSessionScreen({super.key});

  @override
  State<ReceiveSessionScreen> createState() => _ReceiveSessionScreenState();
}

class _ReceiveSessionScreenState extends State<ReceiveSessionScreen> {
  TvLinkServer? _server;
  String _name = '';
  List<String> _ips = const [];
  String? _error;
  bool _receiving = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _server?.close();
    super.dispose();
  }

  Future<void> _start() async {
    final sync = context.read<SyncService>();
    await _server?.close();
    setState(() {
      _server = null;
      _error = null;
    });
    try {
      _name = await deviceName();
      _ips = await _ownAddresses();
      final server = TvLinkServer(
        name: _name,
        onSession: (s) async {
          if (mounted) setState(() => _receiving = true);
          try {
            await sync.adoptSession(s);
          } finally {
            if (mounted) setState(() => _receiving = false);
          }
        },
      );
      await server.start();
      if (!mounted) {
        await server.close();
        return;
      }
      setState(() => _server = server);
      await server.done;
      await server.close();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Google conectado.')));
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final server = _server;
    final big = Theme.of(context).textTheme.displayMedium
        ?.copyWith(color: accent, fontWeight: FontWeight.bold, letterSpacing: 8);
    return Scaffold(
      appBar: AppBar(title: const Text('Conectar con Google')),
      body: Center(
        child: SingleChildScrollView(
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
              : server == null || _receiving
              ? const CircularProgressIndicator()
              : ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'En el celular o el PC donde ya conectaste Google, abre EteroTV y ve a\n'
                        'Ajustes → Sincronización → Conectar una TV.',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      Text('Elige «$_name» y escribe este código:', textAlign: TextAlign.center),
                      const SizedBox(height: 8),
                      Text('${server.code.substring(0, 3)} ${server.code.substring(3)}', style: big),
                      const SizedBox(height: 16),
                      const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                          SizedBox(width: 12),
                          Text('Esperando…'),
                        ],
                      ),
                      if (_ips.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Text(
                          'Los dos tienen que estar en la misma red. Dirección de esta TV: ${_ips.join(', ')}',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
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
      ),
    );
  }
}

/// Phone / PC already connected: finds a TV that waits and sends it the session.
class SendSessionScreen extends StatefulWidget {
  const SendSessionScreen({super.key});

  @override
  State<SendSessionScreen> createState() => _SendSessionScreenState();
}

class _SendSessionScreenState extends State<SendSessionScreen> {
  List<TvFound>? _found;

  @override
  void initState() {
    super.initState();
    _search();
  }

  Future<void> _search() async {
    setState(() => _found = null);
    final f = await TvLinkClient.find();
    if (mounted) setState(() => _found = f);
  }

  Future<void> _byAddress() async {
    final c = TextEditingController();
    final ip = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Dirección de la TV'),
        content: RemoteTextField(
          controller: c,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(hintText: '192.168.1.50'),
          onSubmitted: (v) => Navigator.pop(d, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(d, c.text), child: const Text('Buscar')),
        ],
      ),
    );
    c.dispose();
    if (ip == null || ip.trim().isEmpty || !mounted) return;
    final tv = await TvLinkClient.probe(ip.trim(), timeout: const Duration(seconds: 3));
    if (!mounted) return;
    if (tv == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('En ${ip.trim()} no hay una TV esperando. Revisa que muestre el código.')));
      return;
    }
    await _send(tv);
  }

  Future<void> _send(TvFound tv) async {
    final sync = context.read<SyncService>();
    final messenger = ScaffoldMessenger.of(context);
    final session = sync.auth.exportSession();
    if (session == null) return;
    while (true) {
      if (!mounted) return;
      final c = TextEditingController();
      final code = await showDialog<String>(
        context: context,
        builder: (d) => AlertDialog(
          title: Text('Código de «${tv.name}»'),
          content: RemoteTextField(
            controller: c,
            autofocus: true,
            keyboardType: TextInputType.number,
            maxLength: 6,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 28, letterSpacing: 8),
            decoration: const InputDecoration(hintText: '000000', counterText: ''),
            onSubmitted: (v) => Navigator.pop(d, v),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancelar')),
            TextButton(onPressed: () => Navigator.pop(d, c.text), child: const Text('Conectar')),
          ],
        ),
      );
      c.dispose();
      if (code == null || !mounted) return;
      try {
        await TvLinkClient.send(tv, code.replaceAll(RegExp(r'\D'), ''), session);
        messenger.showSnackBar(SnackBar(content: Text('«${tv.name}» quedó conectada a Google.')));
        if (mounted) Navigator.pop(context);
        return;
      } on TvLinkException catch (e) {
        messenger.showSnackBar(SnackBar(content: Text(e.message)));
        if (e.message.startsWith('El código')) continue;
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final found = _found;
    return Scaffold(
      appBar: AppBar(title: const Text('Conectar una TV')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          const ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('En la TV: Ajustes → Conectar con Google. Va a mostrar un código de 6 números.'),
            subtitle: Text('La TV y este equipo tienen que estar en la misma red.'),
          ),
          if (found == null)
            const ListTile(
              leading: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
              title: Text('Buscando televisores en tu red…'),
            )
          else if (found.isEmpty)
            const ListTile(
              leading: Icon(Icons.tv_off),
              title: Text('No encontré ninguna TV esperando.'),
              subtitle: Text('Revisa que la TV muestre el código y vuelve a buscar.'),
            )
          else
            for (final (i, tv) in found.indexed)
              ListTile(
                autofocus: i == 0,
                leading: const Icon(Icons.tv),
                title: Text(tv.name),
                subtitle: Text(tv.host),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _send(tv),
              ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.refresh),
            title: const Text('Buscar de nuevo'),
            onTap: found == null ? null : _search,
          ),
          ListTile(
            leading: const Icon(Icons.edit),
            title: const Text('Escribir la dirección de la TV'),
            subtitle: const Text('Si no aparece en la lista: la TV la muestra debajo del código.'),
            onTap: _byAddress,
          ),
        ],
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
          leading: const Icon(Icons.connected_tv),
          title: const Text('Conectar una TV'),
          subtitle: const Text('Le pasa esta conexión con Google a un televisor de tu red (una vez por TV).'),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SendSessionScreen())),
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
