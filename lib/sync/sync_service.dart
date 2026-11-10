import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';

import '../state/app_state.dart';
import 'drive_store.dart';
import 'google_auth.dart';

/// Keeps "my library" the same on every device through Google Drive.
///
/// Each device keeps one file `eterotv-device-<id>.json` with everything it
/// shares (see [AppState.exportSnapshot]). Syncing = read the other devices'
/// files, keep the newest of each thing, then upload our merged file. Runs
/// at start, when the app comes back to the front, a few seconds after each
/// change, and every 10 minutes.
class SyncService extends ChangeNotifier {
  SyncService(this.state, {GoogleAuth? auth, RemoteStore? remote}) : auth = auth ?? GoogleAuth() {
    _remote = remote;
  }

  final AppState state;
  final GoogleAuth auth;
  RemoteStore? _remote;
  RemoteStore get remote => _remote ??= DriveStore(auth);

  static const debounce = Duration(seconds: 4);
  static const every = Duration(minutes: 10);

  bool syncing = false;
  String? error;
  DateTime? lastSync;
  int lastDevices = 0;

  Timer? _soon;
  Timer? _periodic;
  bool _again = false;
  AppLifecycleListener? _life;

  bool get signedIn => auth.signedIn;
  String get _ownName => '${DriveStore.prefix}device-${state.deviceId}.json';

  Future<void> start() async {
    await auth.load();
    state.onLocalChange = schedule;
    _periodic = Timer.periodic(every, (_) => syncNow());
    _life = AppLifecycleListener(onResume: syncNow);
    if (auth.signedIn) unawaited(syncNow());
  }

  @override
  void dispose() {
    _soon?.cancel();
    _periodic?.cancel();
    _life?.dispose();
    super.dispose();
  }

  void schedule() {
    if (!auth.signedIn) return;
    _soon?.cancel();
    _soon = Timer(debounce, syncNow);
  }

  Future<void> syncNow() async {
    if (!auth.signedIn) return;
    if (syncing) {
      _again = true;
      return;
    }
    syncing = true;
    error = null;
    notifyListeners();
    try {
      do {
        _again = false;
        await _round();
      } while (_again);
      lastSync = DateTime.now();
    } catch (e) {
      error = e.toString();
    } finally {
      syncing = false;
      notifyListeners();
    }
  }

  Future<void> _round() async {
    final files = await remote.list();
    RemoteFile? own;
    var devices = 0;
    for (final f in files) {
      if (f.name == _ownName) {
        own = f;
        continue;
      }
      if (!f.name.startsWith('${DriveStore.prefix}device-')) continue;
      try {
        final data = jsonDecode(await remote.read(f)) as Map<String, dynamic>;
        devices++;
        await state.mergeSnapshot(data);
      } on FormatException {
        // A half-written file: the next round reads it again.
      }
    }
    lastDevices = devices;
    await remote.write(_ownName, jsonEncode(state.exportSnapshot()), existing: own);
  }

  Future<void> signInWithBrowser() async {
    await auth.signInWithBrowser();
    notifyListeners();
    await syncNow();
  }

  /// TV: keeps the session sent by a connected phone or PC, then syncs.
  Future<void> adoptSession(Map<String, dynamic> session) async {
    await auth.adoptSession(session);
    notifyListeners();
    await syncNow();
  }

  /// Stops syncing on this device. Drive keeps the other devices' data.
  Future<void> signOut() async {
    await auth.signOut();
    lastSync = null;
    error = null;
    notifyListeners();
  }

  @visibleForTesting
  String get ownFileName => _ownName;
}
