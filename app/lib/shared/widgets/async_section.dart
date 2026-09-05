import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/api/error_codes.dart';
import '../../core/theme/colors.dart';

/// Renders one of three genuinely distinct states for an async section.
///
/// This exists because the alternative keeps going wrong: a screen that falls
/// back to its empty state on failure tells the rider "no rides" when the truth
/// is "we could not ask". A skeleton that never resolves says the same thing
/// more slowly. Making the three states a single decision, in one place, is the
/// only way they stay honest across dozens of screens.
///
///  * loading → [skeleton]
///  * failed  → a message and a Retry, never an empty state
///  * data    → [empty] when [isEmpty] says so, otherwise [data]
class AsyncSection<T> extends StatelessWidget {
  final AsyncValue<T> value;

  /// Shown while loading. Should mirror the shape of the real content.
  final Widget skeleton;

  /// Builds the real content.
  final Widget Function(T value) data;

  /// True when the loaded value has nothing to show.
  final bool Function(T value)? isEmpty;

  /// Shown when [isEmpty] returns true. Falls back to a plain line.
  final Widget? empty;

  /// Re-runs the request. Without it the error state is a dead end.
  final VoidCallback? onRetry;

  const AsyncSection({
    super.key,
    required this.value,
    required this.skeleton,
    required this.data,
    this.isEmpty,
    this.empty,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return value.when(
      // `skipLoadingOnRefresh` is deliberately NOT used: a background refresh
      // keeps the old content on screen rather than flashing a skeleton over
      // data the rider is already reading.
      loading: () => skeleton,
      error: (err, _) => _Failed(error: err, onRetry: onRetry),
      data: (v) {
        if (isEmpty?.call(v) ?? false) {
          return empty ?? const _Empty();
        }
        return data(v);
      },
    );
  }
}

class _Failed extends StatelessWidget {
  final Object error;
  final VoidCallback? onRetry;

  const _Failed({required this.error, this.onRetry});

  @override
  Widget build(BuildContext context) {
    final message = error is ApiException
        ? RiderErrorCopy.messageFor(error as ApiException)
        : 'Something went wrong.';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off_rounded,
              size: 34, color: AppColors.lightTextDisabled),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          if (onRetry != null) ...[
            const SizedBox(height: 14),
            OutlinedButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Center(
          child: Text('Nothing here yet',
              style: Theme.of(context).textTheme.bodyMedium),
        ),
      );
}
