import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/profiles.dart';
import '../state/app_state.dart';
import 'i18n.dart';
import 'remote.dart';
import 'theme.dart';

/// A profile's picture: its drawing on a coloured circle, with a white ring
/// when it has the focus.
class AvatarCircle extends StatelessWidget {
  const AvatarCircle({super.key, required this.avatar, this.size = 96, this.focused = false});
  final String avatar;
  final double size;
  final bool focused;

  @override
  Widget build(BuildContext context) {
    final a = avatarOf(avatar);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: a.color,
        shape: BoxShape.circle,
        border: Border.all(color: focused ? Colors.white : Colors.transparent, width: size > 60 ? 4 : 2),
      ),
      alignment: Alignment.center,
      child: Text(a.emoji, style: TextStyle(fontSize: size * 0.55, height: 1.1)),
    );
  }
}

/// Goes back to «¿Quién va a ver?» from anywhere in the app.
void switchProfile(BuildContext context) {
  Navigator.of(context).popUntil((r) => r.isFirst);
  context.read<AppState>().leaveProfile();
}

/// The small picture of the profile in use, to change profile.
class ProfileButton extends StatelessWidget {
  const ProfileButton({super.key, this.size = 40});
  final double size;

  @override
  Widget build(BuildContext context) {
    final p = context.select<AppState, String>((s) => s.profile.avatar);
    final name = context.select<AppState, String>((s) => AppState.profileName(s.profile));
    return Tooltip(
      message: tr('Cambiar de perfil ({0})', [name]),
      child: _Focusable(
        onTap: () => switchProfile(context),
        builder: (f) => AvatarCircle(avatar: p, size: size, focused: f),
      ),
    );
  }
}

class _Focusable extends StatefulWidget {
  const _Focusable({required this.onTap, required this.builder, this.autofocus = false});
  final VoidCallback onTap;
  final Widget Function(bool focused) builder;
  final bool autofocus;
  @override
  State<_Focusable> createState() => _FocusableState();
}

class _FocusableState extends State<_Focusable> {
  bool _focused = false;
  @override
  Widget build(BuildContext context) => InkWell(
    autofocus: widget.autofocus,
    customBorder: const CircleBorder(),
    onTap: widget.onTap,
    onFocusChange: (f) => setState(() => _focused = f),
    child: widget.builder(_focused),
  );
}

/// «¿Quién va a ver?»: shown each time the app opens (Jose, 2026-11-10).
class ProfilesScreen extends StatefulWidget {
  const ProfilesScreen({super.key});
  @override
  State<ProfilesScreen> createState() => _ProfilesScreenState();
}

class _ProfilesScreenState extends State<ProfilesScreen> {
  bool _manage = false;

  void _edit(Profile? p) => Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileEditor(profile: p)));

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final list = s.profiles;
    Widget tile(Widget picture, String name, VoidCallback onTap, {bool autofocus = false, bool editing = false}) =>
        SizedBox(
          width: 130,
          child: _Focusable(
            autofocus: autofocus,
            onTap: onTap,
            builder: (f) => Column(
              children: [
                Stack(
                  alignment: Alignment.center,
                  children: [
                    picture is AvatarCircle ? AvatarCircle(avatar: picture.avatar, focused: f) : _AddCircle(focused: f),
                    if (editing)
                      Container(
                        width: 96,
                        height: 96,
                        decoration: const BoxDecoration(color: Colors.black45, shape: BoxShape.circle),
                        child: const Icon(Icons.edit, size: 36),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 16,
                    color: f ? Colors.white : Colors.white70,
                    fontWeight: f ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
        );
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Image.asset('assets/icon.png', width: 56, height: 56),
              const SizedBox(height: 16),
              Text(
                _manage ? tr('Administrar perfiles') : tr('¿Quién va a ver?'),
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 32),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 16,
                runSpacing: 24,
                children: [
                  for (final p in list)
                    tile(
                      AvatarCircle(avatar: p.avatar),
                      AppState.profileName(p),
                      () => _manage ? _edit(p) : s.selectProfile(p.id),
                      autofocus: p.id == s.profileId,
                      editing: _manage,
                    ),
                  if (list.length < AppState.maxProfiles)
                    tile(const SizedBox(), tr('Agregar perfil'), () => _edit(null)),
                ],
              ),
              const SizedBox(height: 32),
              OutlinedButton.icon(
                onPressed: () => setState(() => _manage = !_manage),
                icon: Icon(_manage ? Icons.check : Icons.edit_outlined),
                label: Text(_manage ? tr('Listo') : tr('Administrar perfiles')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AddCircle extends StatelessWidget {
  const _AddCircle({required this.focused});
  final bool focused;
  @override
  Widget build(BuildContext context) => Container(
    width: 96,
    height: 96,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: const Color(0xFF262626),
      border: Border.all(color: focused ? Colors.white : Colors.white24, width: focused ? 4 : 2),
    ),
    child: const Icon(Icons.add, size: 44, color: Colors.white70),
  );
}

/// Creating ([profile] null) or changing a profile: name and drawing.
class ProfileEditor extends StatefulWidget {
  const ProfileEditor({super.key, this.profile});
  final Profile? profile;
  @override
  State<ProfileEditor> createState() => _ProfileEditorState();
}

class _ProfileEditorState extends State<ProfileEditor> {
  late final _name = TextEditingController(text: widget.profile?.name ?? '');
  late String _avatar = widget.profile?.avatar ?? _freeAvatar();

  /// A new profile starts with a drawing nobody uses yet.
  String _freeAvatar() {
    final used = {for (final p in context.read<AppState>().profiles) p.avatar};
    return avatars.firstWhere((a) => !used.contains(a.id), orElse: () => avatars.first).id;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final s = context.read<AppState>();
    final name = _name.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('Escribe un nombre.'))));
      return;
    }
    final p = widget.profile;
    if (p == null) {
      await s.addProfile(name, _avatar);
    } else {
      await s.editProfile(p.id, name: name, avatar: _avatar);
    }
    if (mounted) Navigator.pop(context);
  }

  Future<void> _delete() async {
    final p = widget.profile!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(tr('¿Eliminar «{0}»?', [AppState.profileName(p)])),
        content: Text(tr('Se borran sus favoritos, lo que estaba viendo y lo visto, en todos tus dispositivos.')),
        actions: [
          TextButton(autofocus: true, onPressed: () => Navigator.pop(c, false), child: Text(tr('Cancelar'))),
          TextButton(onPressed: () => Navigator.pop(c, true), child: Text(tr('Eliminar'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await context.read<AppState>().deleteProfile(p.id);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final p = widget.profile;
    return Scaffold(
      appBar: AppBar(title: Text(p == null ? tr('Agregar perfil') : tr('Editar perfil'))),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Row(
            children: [
              AvatarCircle(avatar: _avatar, size: 80),
              const SizedBox(width: 24),
              Expanded(
                child: RemoteTextField(
                  controller: _name,
                  autofocus: p == null,
                  maxLength: 20,
                  textInputAction: TextInputAction.done,
                  decoration: InputDecoration(labelText: tr('Nombre')),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              FilledButton.icon(
                autofocus: p != null,
                onPressed: _save,
                icon: const Icon(Icons.check),
                label: Text(tr('Guardar')),
              ),
              const SizedBox(width: 12),
              if (p != null && s.profiles.length > 1)
                TextButton.icon(
                  onPressed: _delete,
                  icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                  label: Text(tr('Eliminar perfil'), style: const TextStyle(color: Colors.redAccent)),
                ),
            ],
          ),
          const SizedBox(height: 24),
          Text(tr('Elige un dibujo'), style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final a in avatars)
                _Focusable(
                  onTap: () => setState(() => _avatar = a.id),
                  builder: (f) => Stack(
                    children: [
                      AvatarCircle(avatar: a.id, size: 72, focused: f),
                      if (a.id == _avatar)
                        const Positioned(right: 0, bottom: 0, child: Icon(Icons.check_circle, color: accent)),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
