import 'package:flutter/material.dart';
import 'package:hoppin_ui/hoppin_ui.dart';

/// The designed disclosure state for the multi-stop seam (SL-11, #7).
///
/// The Scope Lock Document (§4.1) lists multi-stop trips as in-scope, but the
/// estimate/request/route contract carries NO waypoint fields (SCOPE-TRACE
/// row 7, MISSING-BE) and there is no Figma frame for it — so the multi-stop
/// UI is DEFERRED (locked decision 2). Rather than fake a waypoint entry that
/// the backend cannot honour, this designed state honestly discloses that
/// multi-stop arrives once the waypoint contract lands.
///
/// This is the registered unavailable-state widget for the SL-11 seam
/// (`kSeamRegistry`); the seam_registry_test group-C check pumps it and
/// asserts a designed, non-blank surface. Token-driven throughout — it is a
/// disclosure marker, never a live waypoint editor.
class MultiStopUnavailableNotice extends StatelessWidget {
  /// Creates the multi-stop deferred disclosure state.
  const MultiStopUnavailableNotice({super.key});

  @override
  Widget build(BuildContext context) {
    return const HopEmptyState(
      compact: true,
      headline: 'Multi-stop trips coming soon',
      supporting:
          'Adding stops along the way is on the way — it arrives once the '
          'waypoint routing is confirmed. For now, book a single pickup and '
          'destination.',
    );
  }
}
