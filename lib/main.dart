import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';

import 'data/database.dart';
import 'player/own_player.dart';
import 'platform/device.dart';
import 'state/app_state.dart';
import 'sync/sync_service.dart';
import 'ui/home_screen.dart';
import 'ui/i18n.dart';
import 'ui/login_screen.dart';
import 'ui/profiles_screen.dart';
import 'ui/remote.dart';
import 'ui/theme.dart';
import 'ui/tv_focus.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  if (Platform.isWindows || Platform.isLinux) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  } else {
    databaseFactory = sqflite.databaseFactorySqflitePlugin;
  }
  runningOnTv = await isTv();
  final dir = await getApplicationSupportDirectory();
  final db = await AppDatabase.open(p.join(dir.path, 'eterotv.db'));
  final prefs = await SharedPreferences.getInstance();
  var deviceId = prefs.getString('deviceId');
  if (deviceId == null) {
    deviceId = const Uuid().v4();
    await prefs.setString('deviceId', deviceId);
  }
  final state = AppState(db: db, prefs: prefs, deviceId: deviceId);
  await state.init();
  final sync = SyncService(state);
  await sync.start();
  HardwareKeyboard.instance.addHandler(tvKeyHandler);
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: state),
        ChangeNotifierProvider.value(value: sync),
      ],
      child: const EteroApp(),
    ),
  );
}

class EteroApp extends StatelessWidget {
  const EteroApp({super.key});

  @override
  Widget build(BuildContext context) {
    final signedIn = context.select<AppState, bool>((s) => s.creds != null);
    final chosen = context.select<AppState, bool>((s) => s.profileChosen);
    final lang = context.select<AppState, UiLang>((s) => s.uiLanguage);
    return MaterialApp(
      // A new language builds every screen again (the texts are read when
      // they are built).
      key: ValueKey(lang),
      navigatorKey: navigatorKeyFor(lang),
      locale: Locale(lang.name),
      supportedLocales: [for (final l in UiLang.values) Locale(l.name)],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      title: 'EteroTV',
      debugShowCheckedModeBanner: false,
      theme: eteroTheme(),
      actions: tvActions,
      builder: (context, child) => runningOnTv ? TvSafeArea(child: child!) : child!,
      home: !signedIn
          ? const LoginScreen()
          : chosen
          ? const HomeScreen()
          : const ProfilesScreen(),
    );
  }
}
