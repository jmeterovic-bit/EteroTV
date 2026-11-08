import '../iptv/xtream.dart';

/// After a list refresh the provider may give a channel, movie or series a
/// new id. These helpers find the closest items by name (and duration) so
/// the user can confirm a replacement. Nothing is replaced automatically.

final _noise = RegExp(
  r'\b(4k|uhd|fhd|hd|sd|hevc|h265|x265|1080p|720p|multi|vose|vo|sub|dual|latino|lat|cast|esp)\b',
  caseSensitive: false,
);

/// "ES | Mi Película (2019) [4K]" -> "mi pelicula"
String normalizeName(String raw) {
  var s = raw.toLowerCase();
  // Country / group prefix: "ES |", "ES -", "[LAT]", "|ES|".
  s = s.replaceAll(RegExp(r'^\s*\|?\s*[a-z]{2,4}\s*[|:\-]\s*'), '');
  s = s.replaceAll(RegExp(r'[\[\(][^\]\)]*[\]\)]'), ' ');
  s = _stripAccents(s);
  s = s.replaceAll(_noise, ' ');
  s = s.replaceAll(RegExp(r'[^a-z0-9ñ ]'), ' ');
  return s.replaceAll(RegExp(r'\s+'), ' ').trim();
}

String _stripAccents(String s) {
  const from = 'áàäâãéèëêíìïîóòöôõúùüû';
  const to = 'aaaaaeeeeiiiiooooouuuu';
  final b = StringBuffer();
  for (final ch in s.split('')) {
    final i = from.indexOf(ch);
    b.write(i >= 0 ? to[i] : ch);
  }
  return b.toString();
}

/// 0..1, token overlap blended with a character-bigram similarity so that
/// small spelling changes still score well.
double nameSimilarity(String a, String b) {
  final na = normalizeName(a), nb = normalizeName(b);
  if (na.isEmpty || nb.isEmpty) return 0;
  if (na == nb) return 1;
  final ta = na.split(' ').toSet(), tb = nb.split(' ').toSet();
  final tokens = ta.intersection(tb).length / ta.union(tb).length;
  return 0.5 * tokens + 0.5 * _dice(na, nb);
}

double _dice(String a, String b) {
  Set<String> grams(String s) => {for (var i = 0; i < s.length - 1; i++) s.substring(i, i + 2)};
  final ga = grams(a), gb = grams(b);
  if (ga.isEmpty || gb.isEmpty) return 0;
  return 2 * ga.intersection(gb).length / (ga.length + gb.length);
}

/// What we remember about a lost favourite.
class LostItem {
  LostItem({
    required this.kind,
    required this.name,
    this.durationSecs = 0,
    this.tmdbId = '',
    this.year = '',
    this.epgId = '',
  });
  final Kind kind;
  final String name;
  final int durationSecs;
  final String tmdbId;
  final String year;
  final String epgId;
}

class Candidate {
  Candidate(this.item, this.score, this.reasons, {this.durationSecs = 0});
  final CatalogItem item;
  final double score;
  final List<String> reasons;
  final int durationSecs;

  /// Strong enough to offer "accept all safe suggestions".
  bool get safe => score >= 0.9;
}

/// Score one candidate. [candidateDuration] is optional: the movie
/// duration comes from a separate call, so it is only asked for the best few.
Candidate scoreCandidate(LostItem lost, CatalogItem c, {int candidateDuration = 0}) {
  final reasons = <String>[];
  if (lost.tmdbId.isNotEmpty && lost.tmdbId == c.tmdbId) {
    return Candidate(c, 1, ['mismo ID de TMDB'], durationSecs: candidateDuration);
  }
  if (lost.kind == Kind.live && lost.epgId.isNotEmpty && lost.epgId == c.epgId) {
    return Candidate(c, 0.95, ['mismo canal de la guía'], durationSecs: candidateDuration);
  }
  var score = nameSimilarity(lost.name, c.name) * 0.8;
  if (score >= 0.75) reasons.add('nombre casi igual');
  if (lost.year.isNotEmpty && lost.year == c.year) {
    score += 0.05;
    reasons.add('mismo año');
  }
  if (lost.durationSecs > 0 && candidateDuration > 0) {
    final diff = (lost.durationSecs - candidateDuration).abs();
    if (diff <= 120) {
      score += 0.15;
      reasons.add('misma duración');
    } else if (diff > 600) {
      score -= 0.2;
      reasons.add('duración distinta');
    }
  }
  return Candidate(c, score.clamp(0, 1).toDouble(), reasons, durationSecs: candidateDuration);
}

/// Best name matches of the same kind, without durations (cheap pass).
List<Candidate> bestByName(LostItem lost, Iterable<CatalogItem> pool, {int limit = 5}) {
  final out = <Candidate>[
    for (final c in pool)
      if (c.kind == lost.kind) scoreCandidate(lost, c),
  ]..removeWhere((c) => c.score < 0.35);
  out.sort((a, b) => b.score.compareTo(a.score));
  return out.take(limit).toList();
}
