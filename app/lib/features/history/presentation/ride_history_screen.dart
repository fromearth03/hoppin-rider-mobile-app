import 'package:flutter/material.dart';

/// Ride history, list view.
///
/// There is no live list-rides endpoint wired anywhere in the app yet.
/// `GET /api/v1/rides` is recorded in SCREEN-DECISIONS.md as a milestone 2
/// contract - verified against `rider_trips_read.go`, cursor-paged with
/// `status`/`from`/`to`/`limit`/`cursor` - but no repository method calls it
/// from this app. Filling this screen with the design's sample rows (or any
/// other fabricated data) would tell the rider a lie: that Hoppin has been
/// tracking trips it has not actually shown them. So this screen renders the
/// real chrome (title, back arrow) and an honest, clearly-labelled notice
/// instead of a fake list. It becomes a real list once the repository method
/// lands - nothing else on this screen should need to change.
class RideHistoryScreen extends StatelessWidget {
  const RideHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: const Text('Ride History'),
        // AppBar only draws a back button automatically when it can find a
        // route to pop to. In isolation (e.g. this screen pushed directly, or
        // under test with no navigation stack) that auto-detection finds
        // nothing, so the design's back arrow is wired explicitly instead.
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.history,
                size: 56,
                color: theme.textTheme.bodyMedium?.color,
              ),
              const SizedBox(height: 16),
              Text(
                'Ride history coming soon',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                'Your past trips will appear here in a future update.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
