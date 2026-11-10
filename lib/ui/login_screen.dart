import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../iptv/xtream.dart';
import '../state/app_state.dart';
import '../sync/google_auth.dart';
import '../sync/sync_service.dart';
import 'google_sync.dart';
import 'remote.dart';
import 'i18n.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _server = TextEditingController();
  final _user = TextEditingController();
  final _pass = TextEditingController();
  bool _busy = false;
  bool _show = false;
  String? _error;

  Future<void> _connect() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<AppState>().signIn(
        Credentials(server: _server.text, username: _user.text.trim(), password: _pass.text),
      );
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// A device already set up shares the IPTV account through Drive.
  Future<void> _fromGoogle() async {
    final sync = context.read<SyncService>();
    final state = context.read<AppState>();
    if (!sync.signedIn && !await connectGoogle(context)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    await sync.syncNow();
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (state.creds == null) {
        _error =
            sync.error ??
            tr(
              'Tu Drive todavía no tiene la cuenta IPTV. Conecta Google en Ajustes del dispositivo donde ya la escribiste, o escríbela aquí.',
            );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: AutofillGroup(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('EteroTV', style: Theme.of(context).textTheme.displaySmall, textAlign: TextAlign.center),
                  const SizedBox(height: 8),
                  Text(tr('Escribe los datos que te dio tu proveedor de IPTV.'), textAlign: TextAlign.center),
                  const SizedBox(height: 24),
                  RemoteTextField(
                    controller: _server,
                    autofocus: true,
                    keyboardType: TextInputType.url,
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      labelText: tr('URL del servidor'),
                      hintText: tr('http://servidor.com:8080'),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  RemoteTextField(
                    controller: _user,
                    autofillHints: const [AutofillHints.username],
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(labelText: tr('Usuario'), border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  RemoteTextField(
                    controller: _pass,
                    obscureText: !_show,
                    autofillHints: const [AutofillHints.password],
                    onSubmitted: (_) => _connect(),
                    decoration: InputDecoration(
                      labelText: tr('Contraseña'),
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(_show ? Icons.visibility_off : Icons.visibility),
                        onPressed: () => setState(() => _show = !_show),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                    ),
                  FilledButton(
                    onPressed: _busy ? null : _connect,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: _busy
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                          : Text(tr('Conectar')),
                    ),
                  ),
                  if (GoogleAuth.configured) ...[
                    const SizedBox(height: 24),
                    const Row(
                      children: [
                        Expanded(child: Divider()),
                        Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text('o')),
                        Expanded(child: Divider()),
                      ],
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.cloud_download_outlined),
                      label: Padding(
                        padding: EdgeInsets.all(12),
                        child: Text(tr('Traer mi cuenta desde Google Drive')),
                      ),
                      onPressed: _busy ? null : _fromGoogle,
                    ),
                  ],
                  const SizedBox(height: 16),
                  Text(
                    tr(
                      'Los datos se guardan cifrados en este dispositivo y, si conectas Google, en una carpeta oculta de tu Drive para tus otros dispositivos.',
                    ),
                    style: Theme.of(context).textTheme.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
