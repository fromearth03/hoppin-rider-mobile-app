import 'package:hoppin_rider/core/localization/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'device_settings.dart';

final screenAwakeDriverProvider = Provider<Future<void> Function(bool)>(
  (ref) =>
      (enabled) => WakelockPlus.toggle(enable: enabled),
);

/// One owner for the device lock. Backgrounding or unmounting releases it.
class ScreenAwake extends ConsumerStatefulWidget {
  final Widget child;
  const ScreenAwake({super.key, required this.child});
  @override
  ConsumerState<ScreenAwake> createState() => _ScreenAwakeState();
}

class _ScreenAwakeState extends ConsumerState<ScreenAwake>
    with WidgetsBindingObserver {
  Future<void> _pending = Future.value();
  bool _foreground = true;
  late Future<void> Function(bool) _driver;
  @override
  void initState() {
    super.initState();
    _foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    _driver = ref.read(screenAwakeDriverProvider);
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _apply();
    });
  }

  void _apply() =>
      _set(_foreground && ref.read(deviceSettingsProvider).keepAwake);
  void _set(bool enabled) {
    _pending = _pending.then((_) async {
      try {
        await _driver(enabled);
      } catch (_) {
        if (enabled && mounted) {
          await ref
              .read(deviceSettingsProvider.notifier)
              .update((s) => s.copyWith(keepAwake: false));
          if (mounted) {
            ScaffoldMessenger.maybeOf(context)?.showSnackBar(
              const SnackBar(
                content: AppText(
                  'Could not keep the screen awake on this device.',
                ),
              ),
            );
          }
        }
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _apply();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _set(false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(
      deviceSettingsProvider.select((s) => s.keepAwake),
      (_, __) => _apply(),
    );
    return widget.child;
  }
}
