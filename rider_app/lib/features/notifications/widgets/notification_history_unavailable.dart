import 'package:flutter/material.dart';
import 'package:hoppin_ui/hoppin_ui.dart';

/// The designed unavailable-state for notification HISTORY (gap 68, SL-12).
///
/// There is no `GET /me/notifications` endpoint. The client therefore cannot
/// know what history exists — and the difference between that and "there is
/// none" is the whole point of this widget.
///
/// 🔴 It must NEVER read "you have no notifications". That asserts EMPTINESS.
/// The truth is IGNORANCE. An empty-state that claims the rider has nothing
/// waiting for them, when the client simply cannot read the record, is the same
/// species of lie as a fake unread badge — it is just a quieter one.
///
/// It is CONSTRUCTED by `notification_centre_screen.dart` on both branches: the
/// empty feed, and pinned beneath a populated list (live events do not make
/// OLDER history readable). That mount site is what the Group C reachability
/// check looks for — a declared-but-never-constructed disclosure is dead code
/// wearing a compliance badge.
///
/// Body-swaps to the live read with zero view changes when the endpoint ships.
class NotificationHistoryUnavailable extends StatelessWidget {
  /// Creates the gap-68 history disclosure.
  const NotificationHistoryUnavailable({super.key});

  @override
  Widget build(BuildContext context) {
    return const HopCard(
      child: HopEmptyState(
        compact: true,
        headline: "Notification history isn't available yet",
        supporting:
            'New alerts show here as they arrive during your trip. Your saved '
            'history will appear once we can load it.',
      ),
    );
  }
}
