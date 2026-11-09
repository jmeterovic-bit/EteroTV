import 'dart:convert';

import 'package:http/http.dart' as http;

import 'google_auth.dart';

class RemoteFile {
  const RemoteFile(this.id, this.name);
  final String id;
  final String name;
}

/// What the sync needs from storage. Drive implements it; tests use memory.
abstract class RemoteStore {
  Future<List<RemoteFile>> list();
  Future<String> read(RemoteFile f);
  Future<void> write(String name, String content, {RemoteFile? existing});
}

class DriveException implements Exception {
  DriveException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Files in the hidden app folder of the user's Drive (appDataFolder): the
/// user cannot see them and other apps cannot read them. Plain REST calls.
class DriveStore implements RemoteStore {
  DriveStore(this.auth, {http.Client? client}) : _http = client ?? http.Client();
  final GoogleAuth auth;
  final http.Client _http;

  static const prefix = 'eterotv-';

  Future<Map<String, String>> _headers() async => {'Authorization': 'Bearer ${await auth.accessToken()}'};

  void _check(http.Response r) {
    if (r.statusCode >= 200 && r.statusCode < 300) return;
    throw DriveException('Google Drive respondió ${r.statusCode}.');
  }

  @override
  Future<List<RemoteFile>> list() async {
    final out = <RemoteFile>[];
    String? page;
    do {
      final r = await _http.get(
        Uri.https('www.googleapis.com', '/drive/v3/files', {
          'spaces': 'appDataFolder',
          'q': "name contains '$prefix' and trashed = false",
          'fields': 'nextPageToken,files(id,name)',
          'pageSize': '100',
          'pageToken': ?page,
        }),
        headers: await _headers(),
      );
      _check(r);
      final m = jsonDecode(r.body) as Map<String, dynamic>;
      for (final f in (m['files'] as List? ?? const [])) {
        final name = f['name'] as String;
        if (name.startsWith(prefix)) out.add(RemoteFile(f['id'] as String, name));
      }
      page = m['nextPageToken'] as String?;
    } while (page != null);
    return out;
  }

  @override
  Future<String> read(RemoteFile f) async {
    final r = await _http.get(
      Uri.https('www.googleapis.com', '/drive/v3/files/${f.id}', {'alt': 'media'}),
      headers: await _headers(),
    );
    _check(r);
    return utf8.decode(r.bodyBytes);
  }

  @override
  Future<void> write(String name, String content, {RemoteFile? existing}) async {
    final h = await _headers();
    if (existing != null) {
      final r = await _http.patch(
        Uri.https('www.googleapis.com', '/upload/drive/v3/files/${existing.id}', {'uploadType': 'media'}),
        headers: {...h, 'Content-Type': 'application/json; charset=UTF-8'},
        body: utf8.encode(content),
      );
      _check(r);
      return;
    }
    const boundary = 'eterotv-boundary-7c1f';
    final meta = jsonEncode({
      'name': name,
      'parents': ['appDataFolder'],
    });
    final body =
        '--$boundary\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n$meta\r\n'
        '--$boundary\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n$content\r\n--$boundary--';
    final r = await _http.post(
      Uri.https('www.googleapis.com', '/upload/drive/v3/files', {'uploadType': 'multipart'}),
      headers: {...h, 'Content-Type': 'multipart/related; boundary=$boundary'},
      body: utf8.encode(body),
    );
    _check(r);
  }
}
