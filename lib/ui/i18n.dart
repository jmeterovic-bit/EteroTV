/// The app's text in Spanish, English or French (Ajustes → Idioma).
///
/// The code keeps writing the Spanish text; [tr] looks it up in the
/// language chosen. Values like a name or a number go in as {0}, {1}…
library;

import 'i18n_en.dart';
import 'i18n_fr.dart';

enum UiLang {
  es('Español'),
  en('English'),
  fr('Français');

  const UiLang(this.label);
  final String label;

  static UiLang fromName(String? n) => values.firstWhere((l) => l.name == n, orElse: () => es);
}

/// The language in use. Changed only through AppState, which rebuilds the app.
UiLang uiLang = UiLang.es;

String tr(String es, [List<Object?> args = const []]) {
  var s = switch (uiLang) {
    UiLang.es => es,
    UiLang.en => en[es] ?? es,
    UiLang.fr => fr[es] ?? es,
  };
  for (var i = 0; i < args.length; i++) {
    s = s.replaceAll('{$i}', '${args[i]}');
  }
  return s;
}
