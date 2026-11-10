import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

/// The profile everything belonged to before there were profiles (1.0.0).
const defaultProfile = 'p0';

/// A picture for a profile: a drawing (emoji) on a coloured circle.
class Avatar {
  const Avatar(this.id, this.emoji, this.color);
  final String id;
  final String emoji;
  final Color color;
}

/// The drawings to choose from. Only the system's emoji, and only ones that
/// Android 9 (older Fire TV) already draws: no characters from films or
/// series (their owners' art cannot go in the app).
const avatars = <Avatar>[
  Avatar('fox', '🦊', Color(0xFFE67E22)),
  Avatar('panda', '🐼', Color(0xFF7F8C8D)),
  Avatar('lion', '🦁', Color(0xFFF1C40F)),
  Avatar('tiger', '🐯', Color(0xFFD35400)),
  Avatar('frog', '🐸', Color(0xFF27AE60)),
  Avatar('monkey', '🐵', Color(0xFF8E5A2B)),
  Avatar('penguin', '🐧', Color(0xFF34495E)),
  Avatar('owl', '🦉', Color(0xFF6D4C41)),
  Avatar('unicorn', '🦄', Color(0xFFE91E63)),
  Avatar('dragon', '🐲', Color(0xFF16A085)),
  Avatar('trex', '🦖', Color(0xFF2E7D32)),
  Avatar('octopus', '🐙', Color(0xFF8E24AA)),
  Avatar('wizard', '🧙', Color(0xFF3949AB)),
  Avatar('fairy', '🧚', Color(0xFFAB47BC)),
  Avatar('mermaid', '🧜', Color(0xFF00897B)),
  Avatar('hero', '🦸', Color(0xFFC62828)),
  Avatar('villain', '🦹', Color(0xFF4A148C)),
  Avatar('koala', '🐨', Color(0xFF607D8B)),
  Avatar('princess', '👸', Color(0xFFF06292)),
  Avatar('prince', '🤴', Color(0xFF1565C0)),
  Avatar('vampire', '🧛', Color(0xFF880E4F)),
  Avatar('elf', '🧝', Color(0xFF558B2F)),
  Avatar('rocket', '🚀', Color(0xFF0D47A1)),
  Avatar('robot', '🤖', Color(0xFF546E7A)),
  Avatar('alien', '👽', Color(0xFF43A047)),
  Avatar('ghost', '👻', Color(0xFF5C6BC0)),
  Avatar('pumpkin', '🎃', Color(0xFFEF6C00)),
  Avatar('clown', '🤡', Color(0xFFD81B60)),
  Avatar('parrot', '🦜', Color(0xFF00838F)),
  Avatar('dragon2', '🐉', Color(0xFF00695C)),
  Avatar('cat', '😺', Color(0xFFFF8F00)),
  Avatar('dog', '🐶', Color(0xFF795548)),
];

/// A profile can also use a picture of the user's own (1.1.0: Jose, for
/// personal use). It is kept in [Profile.avatar] as `img:` + a small JPEG in
/// base64, so it reaches the other devices with the profile.
const photoPrefix = 'img:';

bool isPhoto(String avatar) => avatar.startsWith(photoPrefix);

final _photoCache = <String, MemoryImage?>{};

/// The picture of a photo avatar, or null for a drawing (or a broken one).
MemoryImage? avatarPhoto(String avatar) {
  if (!isPhoto(avatar)) return null;
  return _photoCache.putIfAbsent(avatar, () {
    try {
      return MemoryImage(base64Decode(avatar.substring(photoPrefix.length)));
    } catch (_) {
      return null;
    }
  });
}

/// Side, in pixels, of the stored picture: enough for the largest circle.
const photoSize = 192;

/// Turns a picture file into a photo avatar: cut to a square in the middle,
/// [photoSize] pixels, JPEG (about 10 KB). Null when it is not a picture.
Future<String?> photoAvatar(Uint8List bytes) => Isolate.run(() {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;
  final square = img.copyResizeCropSquare(img.bakeOrientation(decoded), size: photoSize);
  return photoPrefix + base64Encode(img.encodeJpg(square, quality: 80));
});

Avatar avatarOf(String id) => avatars.firstWhere((a) => a.id == id, orElse: () => avatars.first);

/// Someone who watches: their own favourites, progress and languages. The
/// IPTV account, the PIN and the protected folders are shared by all.
class Profile {
  Profile({
    required this.id,
    this.name = '',
    this.avatar = 'fox',
    this.lang = 'es',
    this.audio = 'original',
    this.subs = 'none',
    this.updatedAt = 0,
    this.deleted = false,
  });

  final String id;
  String name;
  String avatar;

  /// The app's language ([UiLang] name) and the audio and subtitle
  /// languages ([TrackLang] names).
  String lang;
  String audio;
  String subs;

  /// ms since epoch of the last change; the newest wins when syncing.
  int updatedAt;

  /// Removed: kept so other devices remove it too.
  bool deleted;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'avatar': avatar,
    'lang': lang,
    'audio': audio,
    'subs': subs,
    'at': updatedAt,
    if (deleted) 'deleted': true,
  };

  static Profile fromJson(Map<String, dynamic> j) => Profile(
    id: j['id'] as String,
    name: (j['name'] ?? '') as String,
    avatar: (j['avatar'] ?? 'fox') as String,
    lang: (j['lang'] ?? 'es') as String,
    audio: (j['audio'] ?? 'original') as String,
    subs: (j['subs'] ?? 'none') as String,
    updatedAt: ((j['at'] ?? 0) as num).toInt(),
    deleted: j['deleted'] == true,
  );
}
