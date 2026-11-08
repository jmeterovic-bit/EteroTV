// Rules for "watched" and where to resume. Kept apart from the UI so they
// can be tested.

/// Past 90 % (or with less than 3 minutes left) counts as watched.
bool isWatched(int positionSecs, int durationSecs) {
  if (durationSecs <= 0) return false;
  return positionSecs >= durationSecs * 0.9 || durationSecs - positionSecs <= 180;
}

/// Where VLC should start. The first 30 s are not worth resuming, and going
/// back 5 s helps to pick up the thread.
int resumeFrom(int positionSecs, int durationSecs, {required bool watched}) {
  if (watched) return 0;
  if (positionSecs < 30) return 0;
  if (durationSecs > 0 && isWatched(positionSecs, durationSecs)) return 0;
  return positionSecs - 5;
}

/// 0..1 for the progress bar.
double fraction(int positionSecs, int durationSecs) {
  if (durationSecs <= 0) return 0;
  return (positionSecs / durationSecs).clamp(0, 1).toDouble();
}

String formatTime(int secs) {
  final h = secs ~/ 3600, m = (secs % 3600) ~/ 60, s = secs % 60;
  String two(int v) => v.toString().padLeft(2, '0');
  return h > 0 ? '$h:${two(m)}:${two(s)}' : '$m:${two(s)}';
}
