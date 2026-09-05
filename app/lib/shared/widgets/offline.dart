import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/net/network_status.dart';
import '../../core/theme/colors.dart';

/// Full-screen "you're offline" state.
///
/// Used everywhere EXCEPT a live trip. Blanking the screen on someone sitting
/// in a moving car would take away their map, their driver's details and the
/// SOS button at the moment they most need them — see [OfflineBanner].
class OfflineScreen extends ConsumerStatefulWidget {
  /// Shown after a successful recheck, so the caller can refetch.
  final VoidCallback? onRestored;

  const OfflineScreen({super.key, this.onRestored});

  @override
  ConsumerState<OfflineScreen> createState() => _OfflineScreenState();
}

class _OfflineScreenState extends ConsumerState<OfflineScreen> {
  bool _checking = false;

  Future<void> _retry() async {
    if (_checking) return;
    setState(() => _checking = true);
    final ok = await ref.read(networkStatusProvider).recheck();
    if (!mounted) return;
    setState(() => _checking = false);
    if (ok) widget.onRestored?.call();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  height: 96,
                  width: 96,
                  decoration: const BoxDecoration(
                    color: Color(0xFFF1F1F5),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.wifi_off_rounded,
                      size: 42, color: AppColors.lightTextSecondary),
                ),
                const SizedBox(height: 24),
                Text("You're offline",
                    style: theme.textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 10),
                Text(
                  'We can’t reach Hoppin right now. Check your connection — '
                  'we’ll reconnect on our own as soon as it’s back.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 26),
                SizedBox(
                  width: 180,
                  child: FilledButton(
                    onPressed: _checking ? null : _retry,
                    child: _checking
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2.4, color: Colors.white),
                          )
                        : const Text('Try again'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The non-destructive variant: a slim bar that says we are reconnecting while
/// leaving the screen behind it fully usable. This is what a live trip gets.
class OfflineBanner extends ConsumerWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final offline = ref.watch(networkStatusProvider).isOffline;
    if (!offline) return const SizedBox.shrink();

    return Material(
      color: AppColors.negative,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(
                height: 13,
                width: 13,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white),
              ),
              const SizedBox(width: 10),
              Text(
                'Reconnecting — showing your last update',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Colors.white, fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Wraps a screen so it is replaced by [OfflineScreen] while unreachable.
///
/// Screens that must survive a dropout — anything a rider depends on mid-journey
/// — should use [OfflineBanner] instead of this.
class OfflineGate extends ConsumerWidget {
  final Widget child;
  final VoidCallback? onRestored;

  const OfflineGate({super.key, required this.child, this.onRestored});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(networkStatusProvider).isOffline) {
      return OfflineScreen(onRestored: onRestored);
    }
    return child;
  }
}
