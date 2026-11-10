import 'dart:io';

import 'package:eterotv/ui/i18n.dart';
import 'package:eterotv/ui/i18n_en.dart';
import 'package:eterotv/ui/i18n_fr.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() => uiLang = UiLang.es);

  test('tr: Spanish as written, English and French from the tables, with values', () {
    expect(tr('Buscar en {0}', ['Series']), 'Buscar en Series');
    uiLang = UiLang.en;
    expect(tr('Buscar en {0}', ['Series']), 'Search in Series');
    uiLang = UiLang.fr;
    expect(tr('Ajustes'), 'Réglages');
    expect(tr('un texto sin traducir'), 'un texto sin traducir');
  });

  test('every text the app shows has its English and French', () {
    // The texts passed to tr('…') in the code (one literal or several in a row).
    final keys = <String>{};
    final lit = RegExp(r"'((?:[^'\\]|\\.)*)'");
    final call = RegExp(r"(?<![A-Za-z_])tr\(\s*((?:'(?:[^'\\]|\\.)*'\s*)+)");
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart') || f.path.contains('i18n')) continue;
      for (final m in call.allMatches(f.readAsStringSync())) {
        final text = lit.allMatches(m.group(1)!).map((l) => l.group(1)!).join();
        keys.add(text.replaceAll(r"\'", "'").replaceAll(r'\n', '\n').replaceAll(r'\$', r'$'));
      }
    }
    expect(keys.length, greaterThan(200));
    for (final (name, table) in [('en', en), ('fr', fr)]) {
      final missing = keys.where((k) => !table.containsKey(k)).toList();
      expect(missing, isEmpty, reason: '$name sin traducir');
      for (final MapEntry(:key, :value) in table.entries) {
        final holes = RegExp(r'\{\d\}');
        expect(
          holes.allMatches(value).map((m) => m[0]).toSet(),
          holes.allMatches(key).map((m) => m[0]).toSet(),
          reason: '$name: «$key»',
        );
      }
    }
  });

  test('the TV code message keeps the prefix the app looks for', () {
    for (final l in UiLang.values) {
      uiLang = l;
      expect(tr('El código no coincide con el de la TV.'), startsWith(tr('El código')));
    }
  });
}
