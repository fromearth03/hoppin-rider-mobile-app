import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/colors.dart';
import '../application/call_controller.dart';

/// "Call Hoppin Support": an in-app voice call to the Hoppin team, answered by
/// whoever is on duty in the admin panel. No phone number, no phone credit —
/// it runs through Hoppin's own call server like a call with the driver.
///
/// [sosId] and [rideId] travel with the call so the person answering sees
/// which alert or trip it is about. The call screen itself is shown by the
/// app-wide CallOverlay as soon as the call starts.
class CallSupportButton extends ConsumerWidget {
  final String? sosId;
  final String? rideId;

  /// Filled and red when it sits next to an emergency (the Safety screen);
  /// outlined elsewhere.
  final bool urgent;

  const CallSupportButton({
    super.key,
    this.sosId,
    this.rideId,
    this.urgent = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final onCall = ref.watch(callControllerProvider).isActive;
    void call() => ref
        .read(callControllerProvider.notifier)
        .placeSupportCall(sosId: sosId, rideId: rideId);
    final label = Text(onCall ? 'You are on a call' : 'Call Hoppin Support');
    const icon = Icon(Icons.support_agent);
    final shape =
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(12));
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: urgent
          ? FilledButton.icon(
              onPressed: onCall ? null : call,
              icon: icon,
              label: label,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.navy,
                shape: shape,
              ),
            )
          : OutlinedButton.icon(
              onPressed: onCall ? null : call,
              icon: icon,
              label: label,
              style: OutlinedButton.styleFrom(shape: shape),
            ),
    );
  }
}
