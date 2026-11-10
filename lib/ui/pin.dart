import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../iptv/xtream.dart';
import '../state/app_state.dart';
import 'remote.dart';

/// Asks for a 4-digit PIN. Returns null when cancelled.
Future<String?> askPin(BuildContext context, {required String title, String? message, bool forgot = false}) =>
    showDialog<String>(
      context: context,
      builder: (_) => _PinDialog(title: title, message: message, forgot: forgot),
    );

class _PinDialog extends StatefulWidget {
  const _PinDialog({required this.title, this.message, this.forgot = false});
  final String title;
  final String? message;
  final bool forgot;

  @override
  State<_PinDialog> createState() => _PinDialogState();
}

class _PinDialogState extends State<_PinDialog> {
  final _c = TextEditingController();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _done() {
    if (AppState.validPin(_c.text)) Navigator.pop(context, _c.text);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.message != null) ...[Text(widget.message!), const SizedBox(height: 12)],
        RemoteTextField(
          controller: _c,
          autofocus: true,
          obscureText: true,
          keyboardType: TextInputType.number,
          maxLength: 4,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 28, letterSpacing: 16),
          decoration: const InputDecoration(hintText: '••••', counterText: ''),
          onChanged: (v) {
            setState(() {});
            if (v.length == 4) _done();
          },
          onSubmitted: (_) => _done(),
        ),
      ],
    ),
    actions: [
      if (widget.forgot)
        TextButton(onPressed: () => Navigator.pop(context, 'forgot'), child: const Text('Olvidé el PIN')),
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
      TextButton(onPressed: AppState.validPin(_c.text) ? _done : null, child: const Text('Aceptar')),
    ],
  );
}

/// Creates the PIN (typed twice). Returns true when a PIN is set.
Future<bool> createPin(BuildContext context, {String title = 'Crear PIN de carpetas'}) async {
  final s = context.read<AppState>();
  final messenger = ScaffoldMessenger.of(context);
  final a = await askPin(context, title: title, message: 'Elige 4 números. Sirve para todas las carpetas protegidas.');
  if (a == null || !context.mounted) return false;
  final b = await askPin(context, title: 'Repite el PIN');
  if (b == null) return false;
  if (a != b) {
    messenger.showSnackBar(const SnackBar(content: Text('Los PIN no coinciden. No se cambió nada.')));
    return false;
  }
  await s.setPin(a);
  messenger.showSnackBar(const SnackBar(content: Text('PIN guardado.')));
  return true;
}

/// "Olvidé el PIN": the IPTV account password allows choosing a new one.
Future<bool> resetPin(BuildContext context) async {
  final s = context.read<AppState>();
  final c = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (d) => AlertDialog(
      title: const Text('Olvidé el PIN'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Escribe la contraseña de tu cuenta IPTV para elegir un PIN nuevo.'),
          RemoteTextField(controller: c, obscureText: true, autofocus: true),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancelar')),
        TextButton(onPressed: () => Navigator.pop(d, s.checkAccountPassword(c.text)), child: const Text('Seguir')),
      ],
    ),
  );
  c.dispose();
  if (!context.mounted) return false;
  if (ok != true) {
    if (ok == false) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Contraseña incorrecta.')));
    }
    return false;
  }
  return createPin(context, title: 'PIN nuevo');
}

/// Asks the PIN and opens [c] until the app closes.
Future<bool> unlockFolder(BuildContext context, Category c, String name) async {
  final s = context.read<AppState>();
  while (true) {
    if (!context.mounted) return false;
    final pin = await askPin(context, title: 'Carpeta protegida', message: name, forgot: true);
    if (pin == null || !context.mounted) return false;
    if (pin == 'forgot') {
      if (!await resetPin(context)) return false;
      continue;
    }
    if (await s.unlock(c, pin)) return true;
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('PIN incorrecto.')));
    }
  }
}

/// Protects [c] with the PIN (creating it first if needed), or removes the
/// protection after asking the PIN.
Future<void> toggleProtection(BuildContext context, Category c, String name) async {
  final s = context.read<AppState>();
  if (s.isProtected(c)) {
    if (s.isLocked(c) && !await unlockFolder(context, c, name)) return;
    await s.setProtected(c, false);
    return;
  }
  if (!s.hasPin && !await createPin(context)) return;
  await s.setProtected(c, true);
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('«$name» queda protegida. Se vuelve a bloquear al cerrar la app o tras una hora fuera de ella.'),
      ),
    );
  }
}

/// What a locked folder shows instead of its content.
class LockedFolder extends StatelessWidget {
  const LockedFolder({super.key, required this.category, required this.name});
  final Category category;
  final String name;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.lock, size: 56, color: Colors.white54),
        const SizedBox(height: 12),
        const Text('Carpeta protegida con PIN'),
        const SizedBox(height: 16),
        FilledButton.icon(
          autofocus: true,
          icon: const Icon(Icons.lock_open),
          label: const Text('Ingresar PIN'),
          onPressed: () => unlockFolder(context, category, name),
        ),
      ],
    ),
  );
}
