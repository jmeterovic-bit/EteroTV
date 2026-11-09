import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';

import 'data/database.dart';
import 'state/app_state.dart';
import 'ui/home_screen.dart';
import 'ui/login_screen.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isWindows || Platform.isLinux) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  } else {
    databaseFactory = sqflite.databaseFactorySqflitePlugin;
  }
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
  runApp(ChangeNotifierProvider.value(value: state, child: const EteroApp()));
}

class EteroApp extends StatelessWidget {
  const EteroApp({super.key});

  @override
  Widget build(BuildContext context) {
    final signedIn = context.select<AppState, bool>((s) => s.creds != null);
    return MaterialApp(
      title: 'EteroTV',
      debugShowCheckedModeBanner: false,
      theme: eteroTheme(),
      home: signedIn ? const HomeScreen() : const LoginScreen(),
    );
  }
}
