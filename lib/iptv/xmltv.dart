import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import 'package:http/http.dart' as http;

import 'xtream.dart';

/// One programme of the provider's full guide (XMLTV, `xmltv.php`).
class GuideRow {
  GuideRow(this.channel, this.start, this.stop, this.title);

  /// The guide's channel id: a channel's `epg_channel_id` in the catalog.
  final String channel;

  /// ms since epoch.
  final int start;
  final int stop;
  final String title;
}

/// Reads an XMLTV file as it arrives, piece by piece, so a guide of
/// hundreds of MB never sits whole in memory (Fire TV). Only the
/// programmes that touch [from, to) and whose channel is in [channels]
/// (when given) are kept.
class XmltvScanner {
  XmltvScanner({required this.from, required this.to, this.channels});

  final int from;
  final int to;
  final Set<String>? channels;
  final List<GuideRow> rows = [];
  final StringBuffer _buf = StringBuffer();

  static final _attr = RegExp(r'''(\w+)\s*=\s*("([^"]*)"|'([^']*)')''');
  static final _title = RegExp(r'<title\b[^>]*>([\s\S]*?)</title>');

  void add(String chunk) {
    _buf.write(chunk);
    var s = _buf.toString();
    var at = 0;
    while (true) {
      final open = s.indexOf('<programme', at);
      if (open < 0) {
        // Keep a tail in case "<programme" is split between two pieces.
        at = s.length > 16 ? s.length - 16 : 0;
        break;
      }
      final close = s.indexOf('</programme>', open);
      if (close < 0) {
        at = open;
        break;
      }
      _programme(s.substring(open, close));
      at = close + 12;
    }
    _buf.clear();
    if (at < s.length) _buf.write(s.substring(at));
    s = '';
  }

  void _programme(String p) {
    final gt = p.indexOf('>');
    final head = gt < 0 ? p : p.substring(0, gt);
    String? start, stop, channel;
    for (final m in _attr.allMatches(head)) {
      final v = m[3] ?? m[4] ?? '';
      switch (m[1]) {
        case 'start':
          start = v;
        case 'stop':
          stop = v;
        case 'channel':
          channel = unescapeXml(v).trim();
      }
    }
    if (channel == null || channel.isEmpty) return;
    if (channels != null && !channels!.contains(channel)) return;
    final a = parseXmltvTime(start), b = parseXmltvTime(stop);
    if (a == null || b == null || b <= from || a >= to) return;
    final t = _title.firstMatch(p);
    if (t == null) return;
    final title = unescapeXml(t[1]!.replaceAll(RegExp(r'<!\[CDATA\[|\]\]>'), '')).trim();
    if (title.isEmpty) return;
    rows.add(GuideRow(channel, a, b, title));
  }
}

/// "20261115160000 +0100" → ms since epoch (UTC when no offset is given).
int? parseXmltvTime(String? s) {
  if (s == null) return null;
  final m = RegExp(r'^\s*(\d{4})(\d\d)(\d\d)(\d\d)(\d\d)(\d\d)?\s*([+-]\d\d:?\d\d)?').firstMatch(s);
  if (m == null) return null;
  int n(int i) => int.parse(m[i] ?? '0');
  var t = DateTime.utc(n(1), n(2), n(3), n(4), n(5), n(6)).millisecondsSinceEpoch;
  final z = m[7]?.replaceAll(':', '');
  if (z != null) {
    final mins = int.parse(z.substring(1, 3)) * 60 + int.parse(z.substring(3, 5));
    t -= (z.startsWith('-') ? -mins : mins) * 60000;
  }
  return t;
}

String unescapeXml(String s) {
  if (!s.contains('&')) return s;
  return s.replaceAllMapped(RegExp(r'&(#x[0-9a-fA-F]+|#\d+|amp|lt|gt|quot|apos);'), (m) {
    final e = m[1]!;
    if (e.startsWith('#x')) return String.fromCharCode(int.parse(e.substring(2), radix: 16));
    if (e.startsWith('#')) return String.fromCharCode(int.parse(e.substring(1)));
    return const {'amp': '&', 'lt': '<', 'gt': '>', 'quot': '"', 'apos': "'"}[e]!;
  });
}

/// Downloads the provider's full guide in another isolate and keeps only
/// the programmes of [channels] that touch [from, to).
Future<List<GuideRow>> downloadGuide(Credentials c, {required int from, required int to, Set<String>? channels}) =>
    Isolate.run(() async {
      final client = http.Client();
      try {
        final uri = Uri.parse('${c.server}/xmltv.php')
            .replace(queryParameters: {'username': c.username, 'password': c.password});
        final res = await client.send(http.Request('GET', uri)).timeout(const Duration(seconds: 60));
        if (res.statusCode != 200) throw XtreamException('xmltv ${res.statusCode}');
        final scan = XmltvScanner(from: from, to: to, channels: channels);
        await res.stream
            .transform(const Utf8Decoder(allowMalformed: true))
            .timeout(const Duration(seconds: 60))
            .forEach(scan.add);
        return scan.rows;
      } finally {
        client.close();
      }
    });
