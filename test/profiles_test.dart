import 'dart:convert';
import 'dart:typed_data';

import 'package:eterotv/data/profiles.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  test('a picture of your own becomes a small square that travels with the profile', () async {
    final photo = img.Image(width: 800, height: 600);
    img.fill(photo, color: img.ColorRgb8(200, 30, 30));
    final avatar = await photoAvatar(Uint8List.fromList(img.encodePng(photo)));
    expect(avatar, isNotNull);
    expect(isPhoto(avatar!), isTrue);
    final back = img.decodeJpg(base64Decode(avatar.substring(photoPrefix.length)))!;
    expect([back.width, back.height], [photoSize, photoSize]);
    expect(avatar.length, lessThan(30000), reason: 'small enough for the sync file');
    expect(avatarPhoto(avatar), isNotNull);

    final p = Profile.fromJson(Profile(id: 'p1', name: 'Jose', avatar: avatar).toJson());
    expect(p.avatar, avatar);
  });

  test('a file that is not a picture is refused, and drawings have no photo', () async {
    expect(await photoAvatar(Uint8List.fromList([1, 2, 3])), isNull);
    expect(avatarPhoto('fox'), isNull);
    expect(avatarPhoto('${photoPrefix}no-es-base64!'), isNull);
  });
}
