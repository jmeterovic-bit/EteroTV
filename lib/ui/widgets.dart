import 'package:flutter/material.dart';

import '../logic/progress.dart';
import 'remote.dart';
import 'theme.dart';
import 'tv_focus.dart';

/// A poster/card that grows and gets a coloured border when focused, so it
/// is easy to follow with the TV remote. Enter/OK activates it.
class FocusCard extends StatefulWidget {
  const FocusCard({
    super.key,
    required this.title,
    this.subtitle,
    this.image = '',
    this.icon = Icons.movie_outlined,
    this.progress,
    this.width = 150,
    this.aspect = 2 / 3,
    this.autofocus = false,
    this.badge,
    required this.onTap,
    this.onLongPress,
  });

  final String title;
  final String? subtitle;
  final String image;
  final IconData icon;
  final double? progress;
  final double width;
  final double aspect;
  final bool autofocus;
  final IconData? badge;
  final VoidCallback onTap;

  /// Long press (phone) or holding OK / the menu key (remote) opens the item's menu.
  final VoidCallback? onLongPress;

  @override
  State<FocusCard> createState() => _FocusCardState();
}

class _FocusCardState extends State<FocusCard> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.width,
      child: RemoteMenu(
        onSelect: widget.onTap,
        onMenu: widget.onLongPress,
        child: InkWell(
          autofocus: widget.autofocus,
          onTap: widget.onTap,
          onLongPress: widget.onLongPress,
          // The arrows scroll it into view (tv_focus.dart).
          onFocusChange: (f) => setState(() => _focused = f),
          borderRadius: BorderRadius.circular(8),
          child: AnimatedScale(
            scale: _focused ? 1.07 : 1,
            duration: const Duration(milliseconds: 120),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AspectRatio(
                  aspectRatio: widget.aspect,
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF262626),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: _focused ? accent : Colors.transparent, width: 3),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        NetImage(widget.image, icon: widget.icon),
                        if (widget.badge != null)
                          Positioned(top: 4, right: 4, child: Icon(widget.badge, color: accent, size: 20)),
                        if (widget.progress != null)
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            child: LinearProgressIndicator(value: widget.progress, minHeight: 4, color: accent),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontWeight: _focused ? FontWeight.bold : FontWeight.normal),
                ),
                if (widget.subtitle != null)
                  Text(
                    widget.subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class NetImage extends StatelessWidget {
  const NetImage(this.url, {super.key, this.icon = Icons.movie_outlined, this.fit = BoxFit.cover});
  final String url;
  final IconData icon;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final fallback = Center(child: Icon(icon, size: 40, color: Colors.white38));
    if (!url.startsWith('http')) return fallback;
    return Image.network(url, fit: fit, errorBuilder: (_, _, _) => fallback, cacheWidth: 300);
  }
}

/// A titled horizontal row, Netflix style.
class Shelf extends StatefulWidget {
  const Shelf({super.key, required this.title, required this.children, this.height = 290, this.onSeeAll});
  final String title;
  final List<Widget> children;
  final double height;
  final VoidCallback? onSeeAll;

  @override
  State<Shelf> createState() => _ShelfState();
}

class _ShelfState extends State<Shelf> {
  /// «Ver todo» is reached with up/down only from the items right below it.
  final _seeAll = FocusNode(debugLabel: tvAsideLabel);

  @override
  void dispose() {
    _seeAll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Shelf(:title, :children, :height, :onSeeAll) = widget;
    if (children.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(16, 16, onSeeAll == null ? 16 : 4, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
              if (onSeeAll != null)
                TextButton(
                  focusNode: _seeAll,
                  onPressed: onSeeAll,
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [Text('Ver todo'), Icon(Icons.chevron_right)],
                  ),
                ),
            ],
          ),
        ),
        SizedBox(
          height: height,
          child: FocusTraversalGroup(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              itemCount: children.length,
              separatorBuilder: (_, _) => const SizedBox(width: 14),
              itemBuilder: (_, i) => children[i],
            ),
          ),
        ),
      ],
    );
  }
}

String progressLabel(int pos, int dur) => dur > 0 ? '${formatTime(pos)} de ${formatTime(dur)}' : formatTime(pos);

void showError(BuildContext context, Object e) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
}
