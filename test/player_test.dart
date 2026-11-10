import 'package:eterotv/player/vlc.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the player saved on a device is read back, and anything else is VLC', () {
    for (final p in AndroidPlayer.values) {
      expect(AndroidPlayer.fromName(p.name), p);
    }
    expect(AndroidPlayer.fromName(null), AndroidPlayer.vlc);
    expect(AndroidPlayer.fromName('otro'), AndroidPlayer.vlc);
  });

  test('messages name the chosen player', () {
    final a = AndroidVlc();
    expect(a.name, 'VLC');
    a.player = AndroidPlayer.just;
    expect(a.name, 'Just Player');
    expect(VlcMissing(a.name).toString(), 'Just Player no está instalado');
  });
}
