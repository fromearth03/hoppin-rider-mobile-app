import 'package:flutter/material.dart';

import '../../core/theme/colors.dart';

/// The one bottom sheet every map-backed screen uses.
///
/// Rules it enforces everywhere so no screen re-invents them wrong:
///  * ALWAYS collapsible — drag the (tall, easy-to-grab) handle down to a
///    peek so the map behind is fully usable, up for the content. Snaps.
///  * Everything, handle included, lives INSIDE the sheet's scrollable:
///    `DraggableScrollableSheet` only follows drags that flow through its
///    controller, so a handle outside the list could never move the sheet —
///    and a drag that starts on the sheet is consumed by the sheet, never
///    leaked to the map behind it.
class CollapsibleSheet extends StatelessWidget {
  final List<Widget> children;

  /// Optional centred title with a circled close on the right.
  final String? title;
  final VoidCallback? onClose;

  final double initialSize;
  final double minSize;
  final double maxSize;
  final Color color;

  const CollapsibleSheet({
    super.key,
    required this.children,
    this.title,
    this.onClose,
    this.initialSize = 0.62,
    this.minSize = 0.14,
    this.maxSize = 0.92,
    this.color = const Color(0xFFF7F7FA),
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DraggableScrollableSheet(
      initialChildSize: initialSize,
      minChildSize: minSize,
      maxChildSize: maxSize,
      snap: true,
      snapSizes: [minSize, initialSize],
      builder: (context, scrollController) => Material(
        color: color,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        clipBehavior: Clip.antiAlias,
        elevation: 12,
        child: ListView(
          controller: scrollController,
          padding: EdgeInsets.fromLTRB(
              16, 0, 16, MediaQuery.of(context).padding.bottom + 12),
          children: [
            // A generous grab zone, not a hairline: the whole strip drags.
            SizedBox(
              height: 26,
              child: Center(
                child: Container(
                  width: 44,
                  height: 4.5,
                  decoration: BoxDecoration(
                    color: const Color(0xFFC9C9D2),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            ),
            if (title != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Text(
                      title!,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontSize: 16.5, color: AppColors.navy),
                    ),
                    if (onClose != null)
                      Align(
                        alignment: Alignment.centerRight,
                        child: Material(
                          color: const Color(0xFFE3E3E8),
                          shape: const CircleBorder(),
                          child: InkWell(
                            onTap: onClose,
                            customBorder: const CircleBorder(),
                            child: const Padding(
                              padding: EdgeInsets.all(6),
                              child: Icon(Icons.close,
                                  size: 16,
                                  color: AppColors.lightTextSecondary),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ...children,
          ],
        ),
      ),
    );
  }
}
