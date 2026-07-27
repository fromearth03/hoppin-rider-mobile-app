import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hoppin_shared/hoppin_shared.dart';
import 'package:hoppin_ui/hoppin_ui.dart';
import 'package:url_launcher/url_launcher.dart';

/// Wraps the whole app in the `MaterialApp.router` builder: reads the launch
/// gate and, when the operator has armed one, replaces EVERYTHING (including
/// login) with a non-dismissible block.
///
/// Precedence — maintenance, then force-update — is resolved in [AppStatus.gate];
/// this only paints the decision. The soft "update available" nudge is
/// deliberately NOT a block: it does not gate here, so a newer-build-available
/// user proceeds straight into [child] (the nudge is a lighter surface for a
/// later pass, not a launch wall).
///
/// 🔴 Fails OPEN. While the check is in flight the app renders normally rather
/// than a spinner: the gate is a rare operator action, and a launch that stalls
/// behind a status call is worse for every normal user than the tiny window in
/// which a just-armed maintenance block appears a beat late. On error/timeout
/// `appStatusProvider` yields `ok` anyway.
class LaunchGate extends ConsumerWidget {
  const LaunchGate({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(appStatusProvider);
    final gate = status.hasValue ? status.requireValue.gate : AppGate.ok;

    return switch (gate) {
      AppGate.maintenance => const HopLaunchBlock(
          icon: Icons.build_outlined,
          headline: "We're down for maintenance",
          body: "Hoppin is briefly offline while we make things better. "
              "Please check back shortly — you don't need to do anything.",
        ),
      AppGate.forceUpdate => HopLaunchBlock(
          icon: Icons.system_update_outlined,
          headline: 'Update required',
          body: 'This version of Hoppin is no longer supported. Update to the '
              'latest version to keep riding.',
          actionLabel: 'Update now',
          onAction: _openStore,
        ),
      // Soft nudge and ok both proceed — the app is fully usable.
      AppGate.updateAvailable || AppGate.ok => child,
    };
  }

  Future<void> _openStore() async {
    // The store listing. A wrong-but-harmless fallback (the web app) if the
    // native store URI cannot be resolved, so the button is never a dead end.
    final uri = Uri.parse('https://hoppin.tech/download');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}
