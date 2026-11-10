import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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

/// A row's «Ver todo» button: up from the row reaches it (it is the row's
/// header), and right from the end of the row. (A node type and not a
/// debugLabel: labels are empty in release builds.)
class TvAsideNode extends FocusNode {}

class _TvRowNode extends FocusNode {
  _TvRowNode() : super(canRequestFocus: false, skipTraversal: true);
}

class _TvShelfNode extends FocusNode {
  _TvShelfNode() : super(canRequestFocus: false, skipTraversal: true);
}

/// A row of items (a shelf's cards, the banner's buttons): coming into it
/// from above or below lands on its first item.
class TvRow extends StatefulWidget {
  const TvRow({super.key, required this.child});
  final Widget child;
  @override
  State<TvRow> createState() => _TvRowState();
}

class _TvRowState extends State<TvRow> {
  final _node = _TvRowNode();
  @override
  void dispose() {
    _node.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Focus(focusNode: _node, child: widget.child);
}

/// A titled row: its «Ver todo» ([TvAsideNode]) and its [TvRow].
class TvShelf extends StatefulWidget {
  const TvShelf({super.key, required this.child});
  final Widget child;
  @override
  State<TvShelf> createState() => _TvShelfState();
}

class _TvShelfState extends State<TvShelf> {
  final _node = _TvShelfNode();
  @override
  void dispose() {
    _node.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Focus(focusNode: _node, child: widget.child);
}

T? _up<T extends FocusNode>(FocusNode n) => n.ancestors.whereType<T>().firstOrNull;

/// The first item of [row], scrolled back to the start.
bool _toRowStart(_TvRowNode row, TraversalDirection direction) {
  List<FocusNode> items() => [
    for (final n in row.traversalDescendants)
      if (n is! FocusScopeNode && n.context != null && n.context!.mounted) n,
  ]..sort((a, b) => a.rect.left.compareTo(b.rect.left));
  final first = items().firstOrNull;
  if (first == null) return false;
  final s = _scrollableOn(first.context!, Axis.horizontal);
  final inRow = s != null && _up<_TvRowNode>(first) == row && s.position.pixels > s.position.minScrollExtent;
  if (!inRow) {
    first.requestFocus();
    _reveal(first, direction);
    return true;
  }
  // Scrolled: go back to the start, then take the first card once built.
  s.position.jumpTo(s.position.minScrollExtent);
  first.requestFocus();
  WidgetsBinding.instance.addPostFrameCallback((_) {
    final f = items().firstOrNull;
    if (f != null) {
      f.requestFocus();
      _reveal(f, direction);
    }
  });
  WidgetsBinding.instance.scheduleFrame();
  return true;
}

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
bool tvFocusInDirection(FocusNode current, TraversalDirection direction, {bool retry = true}) {
  if (current is FocusScopeNode) return tvRecoverFocus(current);
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
  final myRow = _up<_TvRowNode>(current);
  // Up from a row goes to its «Ver todo», the row's header.
  if (direction == TraversalDirection.up && myRow != null) {
    final aside = _up<_TvShelfNode>(current)?.traversalDescendants.whereType<TvAsideNode>().firstOrNull;
    if (aside != null && aside.context != null) {
      aside.requestFocus();
      _reveal(aside, direction);
      return true;
    }
  }
  if (vertical) {
    final col = _column(current);
    var cands = [
      for (final n in all)
        if (ahead(n.rect) && _overlapX(_column(n), col) && n is! TvAsideNode && shows(n)) n,
    ];
    // Inside a list, the next row of that list first (even if it is just
    // off screen): a search bar or a button above the list comes after.
    if (along != null) {
      final inList = [
        for (final n in cands)
          if (_scrollableOn(n.context!, Axis.vertical) == along) n,
      ];
      if (inList.isNotEmpty) cands = inList;
    }
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
    // At the end of a row, right goes to its «Ver todo» (just above it).
    if (band.isEmpty && direction == TraversalDirection.right) {
      final aside = all.where((n) => n is TvAsideNode && n.rect.bottom <= cur.top + 8 && n.rect.bottom > cur.top - 80);
      if (aside.isNotEmpty) band.add(aside.first);
    }
    final pool = band.isNotEmpty ? band : cands;
    if (pool.isNotEmpty) {
      double score(FocusNode n) =>
          _gapX(n.rect, cur) + _gapY(n.rect, cur) * 4 + (n.rect.center.dy - cur.center.dy).abs() * 0.01;
      found = pool.reduce((a, b) => score(a) <= score(b) ? a : b);
    }
  }
  if (found == null) return _scrollOn(current, along, direction, retry);

  // Entering a tab from outside: back to the item it had, if it shows.
  final region = found.ancestors.whereType<TvRegionScope>().firstOrNull;
  if (region != null && !current.ancestors.contains(region)) {
    final last = region.focusedChild;
    if (last != null && last is! FocusScopeNode && last.context != null && _shows(last, null)) found = last;
  }

  // Into another row from above or below: its first item.
  final row = _up<_TvRowNode>(found);
  if (vertical && row != null && row != myRow) return _toRowStart(row, direction);

  found.requestFocus();
  _reveal(found, direction);
  return true;
}

/// Nothing more that way among what the list has built: lists only build
/// what is near the screen, so scroll it a bit and look again.
bool _scrollOn(FocusNode current, ScrollableState? along, TraversalDirection direction, bool retry) {
  if (along == null || !retry) return false;
  final p = along.position;
  final forward = direction == TraversalDirection.down || direction == TraversalDirection.right;
  final to = (p.pixels + (forward ? 1 : -1) * p.viewportDimension * 0.6).clamp(p.minScrollExtent, p.maxScrollExtent);
  if (to == p.pixels) return false;
  p.jumpTo(to);
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (current.hasPrimaryFocus && current.context != null) {
      tvFocusInDirection(current, direction, retry: false);
    }
  });
  WidgetsBinding.instance.scheduleFrame();
  return true;
}

/// When the focused item disappeared (a row reloaded under it), the focus
/// is left on the page itself and the arrows did nothing. This puts it back
/// on the item that shows nearest the top left.
bool tvRecoverFocus([FocusScopeNode? scope]) {
  var s = scope ?? FocusManager.instance.rootScope;
  // The innermost scope that has the focus (the open screen, the tab).
  while (s.focusedChild is FocusScopeNode) {
    s = s.focusedChild! as FocusScopeNode;
  }
  final shown = [
    for (final n in s.traversalDescendants)
      if (n is! FocusScopeNode && n.context != null && n.context!.mounted && !n.rect.isEmpty && _shows(n, null)) n,
  ];
  if (shown.isEmpty) return false;
  // Content first (to the right of the side menu), then top to bottom.
  double score(FocusNode n) => n.rect.top + n.rect.left * 0.5 - (_column(n).width > 300 ? 100000 : 0);
  final pick = shown.reduce((a, b) => score(a) <= score(b) ? a : b);
  pick.requestFocus();
  return true;
}

/// Arrow keys when nothing has the focus at all.
bool tvKeyHandler(KeyEvent e) {
  if (e is! KeyDownEvent) return false;
  final arrows = {
    LogicalKeyboardKey.arrowUp,
    LogicalKeyboardKey.arrowDown,
    LogicalKeyboardKey.arrowLeft,
    LogicalKeyboardKey.arrowRight,
  };
  if (!arrows.contains(e.logicalKey)) return false;
  final f = FocusManager.instance.primaryFocus;
  if (f != null && f is! FocusScopeNode) return false;
  return tvRecoverFocus(f as FocusScopeNode?);
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
