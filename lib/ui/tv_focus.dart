import 'dart:math';

import 'package:flutter/material.dart';

/// Moving the focus with the arrows of a TV remote.
///
/// Flutter's own directional traversal picks the geometrically closest
/// widget, even one scrolled out of sight in a row (so the focus "got lost"
/// going up), and at the top it wraps around to the bottom of the screen.
/// This one:
/// - up and down go to the row above or below, to an item that shows on
///   screen, and stay in the same column (content or side menu);
/// - left and right go along the row (scrolling it) and, at the start of a
///   row, to the side menu;
/// - at an edge the focus stays where it is;
/// - entering a tab again goes back to the item it had.
///
/// It is installed for the whole app in [tvActions].

/// A tab's focus scope: it remembers the last item, and the arrows can leave it.
class TvRegionScope extends FocusScopeNode {
  TvRegionScope({super.debugLabel});
}

/// Marks a secondary button (like «Ver todo») that up and down only reach
/// when it is right above or below.
const tvAsideLabel = 'tv-aside';

final tvActions = <Type, Action<Intent>>{
  ...WidgetsApp.defaultActions,
  DirectionalFocusIntent: _TvDirectionalFocusAction(),
};

class _TvDirectionalFocusAction extends Action<DirectionalFocusIntent> {
  @override
  void invoke(DirectionalFocusIntent intent) {
    final f = primaryFocus;
    if (f != null) tvFocusInDirection(f, intent.direction);
  }
}

Iterable<ScrollableState> _scrollables(BuildContext ctx) sync* {
  var s = Scrollable.maybeOf(ctx);
  while (s != null) {
    yield s;
    s = Scrollable.maybeOf(s.context);
  }
}

Rect? _boxRect(BuildContext ctx) {
  final box = ctx.findRenderObject();
  if (box is! RenderBox || !box.hasSize || !box.attached) return null;
  return box.localToGlobal(Offset.zero) & box.size;
}

ScrollableState? _scrollableOn(BuildContext ctx, Axis axis) {
  for (final s in _scrollables(ctx)) {
    if (s.position.axis == axis) return s;
  }
  return null;
}

/// Whether at least half of [n] shows in each of its scroll views, not
/// counting [except] (the row or list being moved along).
bool _shows(FocusNode n, ScrollableState? except) {
  final r = n.rect;
  for (final s in _scrollables(n.context!)) {
    if (s == except) continue;
    final v = _boxRect(s.context);
    if (v == null) continue;
    final h = s.position.axis == Axis.horizontal;
    final (a0, a1, b0, b1) = h ? (r.left, r.right, v.left, v.right) : (r.top, r.bottom, v.top, v.bottom);
    if (min(a1, b1) - max(a0, b0) < (a1 - a0) * 0.5) return false;
  }
  return true;
}

/// The column a widget belongs to: the vertical list around it, or itself.
Rect _column(FocusNode n) {
  final s = _scrollableOn(n.context!, Axis.vertical);
  return (s == null ? null : _boxRect(s.context)) ?? n.rect;
}

bool _overlapX(Rect a, Rect b) => a.right > b.left + 1 && a.left < b.right - 1;
bool _overlapY(Rect a, Rect b) => a.bottom > b.top + 1 && a.top < b.bottom - 1;
double _gapX(Rect a, Rect b) => max(0, max(a.left - b.right, b.left - a.right));
double _gapY(Rect a, Rect b) => max(0, max(a.top - b.bottom, b.top - a.bottom));

/// Moves the focus from [current] one step in [direction]. Returns false
/// (and keeps the focus) when there is nothing that way.
bool tvFocusInDirection(FocusNode current, TraversalDirection direction) {
  final ctx = current.context;
  var scope = current.nearestScope;
  if (ctx == null || scope == null) return false;
  if (scope is TvRegionScope) scope = scope.enclosingScope ?? scope;
  final cur = current.rect;
  final vertical = direction == TraversalDirection.up || direction == TraversalDirection.down;
  final along = _scrollableOn(ctx, vertical ? Axis.vertical : Axis.horizontal);

  final all = scope.traversalDescendants.where(
    (n) => n != current && n is! FocusScopeNode && n.context != null && n.context!.mounted && !n.rect.isEmpty,
  );
  bool ahead(Rect r) => switch (direction) {
    TraversalDirection.up => r.center.dy < cur.top,
    TraversalDirection.down => r.center.dy > cur.bottom,
    TraversalDirection.left => r.center.dx < cur.left,
    TraversalDirection.right => r.center.dx > cur.right,
  };
  bool shows(FocusNode n) {
    final same = along != null && _scrollableOn(n.context!, vertical ? Axis.vertical : Axis.horizontal) == along;
    return _shows(n, same ? along : null);
  }

  FocusNode? found;
  if (vertical) {
    final col = _column(current);
    final cands = [
      for (final n in all)
        if (ahead(n.rect) &&
            _overlapX(_column(n), col) &&
            (n.debugLabel != tvAsideLabel || _overlapX(n.rect, cur)) &&
            shows(n))
          n,
    ];
    if (cands.isNotEmpty) {
      double dy(FocusNode n) => (n.rect.center.dy - cur.center.dy).abs();
      final nearest = cands.reduce((a, b) => dy(a) <= dy(b) ? a : b);
      final row = cands.where((n) => (n.rect.center.dy - nearest.rect.center.dy).abs() < 24);
      double score(FocusNode n) => _gapX(n.rect, cur) * 1000 + (n.rect.center.dx - cur.center.dx).abs();
      found = row.reduce((a, b) => score(a) <= score(b) ? a : b);
    }
  } else {
    final cands = [
      for (final n in all)
        if (ahead(n.rect) && shows(n)) n,
    ];
    final band = cands.where((n) => _overlapY(n.rect, cur)).toList();
    final pool = band.isNotEmpty ? band : cands;
    if (pool.isNotEmpty) {
      double score(FocusNode n) =>
          _gapX(n.rect, cur) + _gapY(n.rect, cur) * 4 + (n.rect.center.dy - cur.center.dy).abs() * 0.01;
      found = pool.reduce((a, b) => score(a) <= score(b) ? a : b);
    }
  }
  if (found == null) return false;

  // Entering a tab from outside: back to the item it had, if it shows.
  final region = found.ancestors.whereType<TvRegionScope>().firstOrNull;
  if (region != null && !current.ancestors.contains(region)) {
    final last = region.focusedChild;
    if (last != null && last is! FocusScopeNode && last.context != null && _shows(last, null)) found = last;
  }

  found.requestFocus();
  _reveal(found, direction);
  return true;
}

/// Scrolls [n] into view: rows keep it at their edge, lists center it.
void _reveal(FocusNode n, TraversalDirection direction) {
  // Each list shows what holds the item: the row shows the card, and the
  // page shows the whole row.
  var ctx = n.context!;
  for (final s in _scrollables(n.context!)) {
    final obj = ctx.findRenderObject();
    if (obj == null) return;
    final h = s.position.axis == Axis.horizontal;
    s.position.ensureVisible(
      obj,
      alignment: 0.5,
      alignmentPolicy: !h
          ? ScrollPositionAlignmentPolicy.explicit
          : direction == TraversalDirection.left
          ? ScrollPositionAlignmentPolicy.keepVisibleAtStart
          : ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
    );
    ctx = s.context;
  }
}
