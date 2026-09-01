import 'package:flutter/material.dart';

/// The soft fade the frames draw at the bottom of a scrollable page: content
/// dissolves into the background, hinting there is more below — and once the
/// rider actually reaches the end, the fade dissolves too, so the last rows
/// are seen in full rather than forever half-veiled.
///
/// Wrap the SCROLLABLE (ListView etc.) — the fade paints over its bottom
/// edge and never intercepts touches. If the content fits with no scrolling,
/// no fade renders at all.
class BottomScrollFade extends StatefulWidget {
  final Widget child;
  final double height;

  const BottomScrollFade({super.key, required this.child, this.height = 96});

  @override
  State<BottomScrollFade> createState() => _BottomScrollFadeState();
}

class _BottomScrollFadeState extends State<BottomScrollFade> {
  bool _showFade = false;

  void _update(ScrollMetrics metrics) {
    // Within a few pixels of the end counts as the end — bounce physics
    // never rests exactly on maxScrollExtent.
    final atEnd = metrics.pixels >= metrics.maxScrollExtent - 4;
    final show = metrics.maxScrollExtent > 0 && !atEnd;
    if (show != _showFade) setState(() => _showFade = show);
  }

  bool _onScroll(ScrollNotification notification) {
    _update(notification.metrics);
    return false;
  }

  /// Fires on layout, before any touch — without this the fade would only
  /// appear after the first scroll rather than the moment content overflows.
  bool _onMetrics(ScrollMetricsNotification notification) {
    _update(notification.metrics);
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final background = Theme.of(context).scaffoldBackgroundColor;

    return NotificationListener<ScrollMetricsNotification>(
      onNotification: _onMetrics,
      child: NotificationListener<ScrollNotification>(
        onNotification: _onScroll,
        child: _body(background),
      ),
    );
  }

  Widget _body(Color background) {
    return Stack(
        children: [
          widget.child,
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: widget.height,
            child: IgnorePointer(
              child: AnimatedOpacity(
                opacity: _showFade ? 1 : 0,
                duration: const Duration(milliseconds: 200),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        background.withValues(alpha: 0),
                        background.withValues(alpha: 0.85),
                        background,
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
    );
  }
}
