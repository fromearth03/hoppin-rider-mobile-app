import 'package:flutter/material.dart';
import 'package:hoppin_ui/hoppin_ui.dart';

import 'location_service.dart';

/// The just-in-time location permission prompt (COMPLY-02).
///
/// Purpose-first: plain-English rationale renders BEFORE any OS request, and
/// the request fires only on an explicit allow tap. It NEVER prompts over an
/// active ride — [canPrompt] is false while a trip is live, which disables the
/// allow action (there is no consent wall mid-trip).
///
/// Presentation + a thin call into the injected [LocationService]: state in,
/// result out via [onResult].
class JitLocationPrompt extends StatelessWidget {
  const JitLocationPrompt({
    required this.service,
    required this.onResult,
    this.canPrompt = true,
    super.key,
  });

  /// The OS-permission seam (a fake in tests).
  final LocationService service;

  /// Reports the permission outcome to the caller (which then continues or
  /// shows the OS-settings path).
  final ValueChanged<LocationPermissionResult> onResult;

  /// False while a ride is active — the allow action is disabled so the prompt
  /// can never interrupt a trip.
  final bool canPrompt;

  Future<void> _requestPermission() async {
    final result = await service.requestPermission();
    onResult(result);
  }

  @override
  Widget build(BuildContext context) {
    final hoppin = context.hoppin;
    final colors = hoppin.colors;
    final type = hoppin.type;

    return Padding(
      padding: EdgeInsets.all(hoppin.spacing.gutter),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(Icons.my_location, color: colors.accent, size: 40),
          SizedBox(height: hoppin.spacing.md),
          Text(
            'Turn on location',
            textAlign: TextAlign.center,
            style: type.title.copyWith(color: colors.textHi),
          ),
          SizedBox(height: hoppin.spacing.sm),
          // The plain-English purpose text — shown BEFORE any OS request.
          Text(
            'We use your location to find nearby drivers and set your pickup. '
            "You're always in control — you can turn this off any time in "
            'Settings.',
            textAlign: TextAlign.center,
            style: type.body.copyWith(color: colors.textMid),
          ),
          SizedBox(height: hoppin.spacing.gutter),
          HopButton.primary(
            key: const Key('jit_allow_button'),
            label: 'Allow location',
            onPressed: canPrompt ? _requestPermission : null,
          ),
          SizedBox(height: hoppin.spacing.sm),
          TextButton(
            onPressed: () => onResult(LocationPermissionResult.denied),
            style: TextButton.styleFrom(
              minimumSize: const Size.fromHeight(44),
            ),
            child: const Text('Not now'),
          ),
        ],
      ),
    );
  }
}
