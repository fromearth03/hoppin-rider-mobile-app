import 'package:flutter/material.dart';
import 'package:hoppin_ui/hoppin_ui.dart';

/// The designed unavailable-state for settings PREFERENCES (gap 71).
///
/// There is no preferences endpoint. Nothing a rider flips on this screen can
/// be saved anywhere — and the repo carries **zero persistence packages**, by
/// deliberate ruling, so there is nowhere on the device to quietly cache a
/// choice and pretend it was stored either. A device-local "save" is invisible
/// to support, dies on a cache-clear, and never follows the rider to a new
/// phone. It would be a false persistence signal, which is the exact failure
/// this project exists to not ship.
///
/// So the switches ship VISIBLE and INERT (`onChanged: null`), and this rung
/// says why.
///
/// **ONE rung for the WHOLE screen**, pinned above the toggle groups — not one
/// per switch. Eight identical rungs is noise, and noise is how a disclosure
/// gets ignored.
///
/// 🔴 The second line is not decoration. Without it the rung reads as *"nothing
/// on this screen works"* — which would be its own small lie, because the theme
/// toggle genuinely does. A disclosure that overstates the damage is still a
/// disclosure that is wrong.
///
/// It is CONSTRUCTED by `settings_screen.dart`. That mount site is what the
/// Group C reachability check looks for — a declared-but-never-constructed
/// disclosure is dead code wearing a compliance badge.
///
/// Body-swaps to the live read with zero view changes when prefs ship.
class SettingsPrefsUnavailable extends StatelessWidget {
  /// Creates the gap-71 preferences disclosure.
  const SettingsPrefsUnavailable({super.key});

  @override
  Widget build(BuildContext context) {
    return const HopCard(
      child: HopEmptyState(
        compact: true,
        headline: "Your preferences aren't saved yet",
        supporting:
            'These switches reset when you reopen the app — we can\'t store '
            'them for you until preferences are switched on. Theme is the '
            'exception: change it and it applies right away.',
      ),
    );
  }
}
