import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/api/error_codes.dart';
import '../../../core/result.dart';
import '../../../core/theme/colors.dart';
import '../data/fare_repository.dart';
import '../data/vehicle_repository.dart';
import 'widgets/fare_category_card.dart';
import 'widgets/fare_legs_breakdown.dart';

/// Fare / confirm-booking screen — "Pricing Details" / "Choose your driver"
/// in the design pack.
///
/// **The cards are vehicle categories, not drivers.** Dispatch solves a
/// Hungarian assignment and publishes exactly one match; there is no
/// endpoint returning candidate drivers, so this screen must never render a
/// list of named drivers to pick from. One `POST /rides/estimate` is quoted
/// per category, each card shows category + fare, and the primary button
/// CONFIRMS THE BOOKING rather than offering a driver choice that does not
/// exist. See `docs/SCREEN-DECISIONS.md` — "Fare / driver selection".
///
/// All constructor parameters are optional so the router can construct this
/// with no arguments; with no [categories] supplied there is simply nothing
/// to quote and the screen renders its empty state.
class FareConfirmScreen extends ConsumerStatefulWidget {
  final LatLng pickup;
  final LatLng dropoff;
  final List<LatLng> waypoints;
  final List<VehicleCategory> categories;

  /// Called with the chosen category once the rider taps Confirm. The
  /// caller (booking flow) owns what happens next — this screen only owns
  /// picking a category and fare, then confirming.
  final ValueChanged<VehicleCategory>? onConfirm;

  const FareConfirmScreen({
    super.key,
    this.pickup = const LatLng(0, 0),
    this.dropoff = const LatLng(0, 0),
    this.waypoints = const [],
    this.categories = const [],
    this.onConfirm,
  });

  @override
  ConsumerState<FareConfirmScreen> createState() => _FareConfirmScreenState();
}

class _FareConfirmScreenState extends ConsumerState<FareConfirmScreen> {
  late Map<String, Future<Result<FareEstimate>>> _quotes;
  final Map<String, Result<FareEstimate>> _resolved = {};
  String? _selectedId;

  @override
  void initState() {
    super.initState();
    _quotes = {};
    _fetchAll();
  }

  void _fetchAll() {
    _resolved.clear();
    if (widget.categories.isEmpty) {
      // Nothing to quote -- skip resolving the repository entirely so
      // constructing this screen with no arguments (as the router does)
      // never needs a working ApiClient.
      _quotes = {};
      return;
    }
    final repo = ref.read(fareRepositoryProvider);
    _quotes = {
      for (final category in widget.categories)
        category.id: _fetchOne(repo, category),
    };
  }

  Future<Result<FareEstimate>> _fetchOne(
      FareRepository repo, VehicleCategory category) async {
    final result = await repo.estimate(
      pickup: widget.pickup,
      dropoff: widget.dropoff,
      vehicleCategoryId: category.id,
      waypoints: widget.waypoints,
    );
    if (mounted) setState(() => _resolved[category.id] = result);
    return result;
  }

  void _retry() {
    setState(_fetchAll);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.maybePop(context),
        ),
        title: const Text('Pricing Details'),
      ),
      body: SafeArea(
        child: widget.categories.isEmpty
            ? const _EmptyState()
            : FutureBuilder<List<Result<FareEstimate>>>(
                future: Future.wait(_quotes.values),
                builder: (context, snapshot) {
                  final allFailed = _resolved.length == widget.categories.length &&
                      _resolved.values.every((r) => r is Err<FareEstimate>);

                  if (allFailed) {
                    final firstError = _resolved.values
                        .whereType<Err<FareEstimate>>()
                        .first
                        .error;
                    return _ErrorState(
                      message: _messageFor(firstError, widget.waypoints),
                      onRetry: _retry,
                    );
                  }

                  return _QuoteList(
                    categories: widget.categories,
                    resolved: _resolved,
                    waypoints: widget.waypoints,
                    selectedId: _selectedId,
                    onSelect: (id) => setState(() => _selectedId = id),
                  );
                },
              ),
      ),
      bottomNavigationBar: widget.categories.isEmpty
          ? null
          : SafeArea(
              minimum: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Row(
                children: [
                  _RoundIconButton(icon: Icons.credit_card_outlined, onTap: () {}),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      style: theme.filledButtonTheme.style,
                      onPressed: _selectedId == null || !_selectedHasFare()
                          ? null
                          : () {
                              final category = widget.categories
                                  .firstWhere((c) => c.id == _selectedId);
                              widget.onConfirm?.call(category);
                            },
                      child: const Text('Confirm'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  _RoundIconButton(icon: Icons.tune, onTap: () {}),
                ],
              ),
            ),
    );
  }

  bool _selectedHasFare() =>
      _resolved[_selectedId] is Ok<FareEstimate>;

  static String _messageFor(ApiException error, List<LatLng> waypoints) {
    if ((error.code == 'NO_ZONE' || error.code == 'NO_TARIFF') &&
        waypoints.isNotEmpty) {
      // The server does not report which stop failed, and with up to five
      // stops the rider cannot guess — so every stop is named rather than
      // pointing at "this" stop.
      final stops =
          List.generate(waypoints.length, (i) => 'Stop ${i + 1}').join(', ');
      return '${RiderErrorCopy.messageFor(error)} Check your stops: $stops.';
    }
    return RiderErrorCopy.messageFor(error);
  }
}

class _QuoteList extends StatelessWidget {
  final List<VehicleCategory> categories;
  final Map<String, Result<FareEstimate>> resolved;
  final List<LatLng> waypoints;
  final String? selectedId;
  final ValueChanged<String> onSelect;

  const _QuoteList({
    required this.categories,
    required this.resolved,
    required this.waypoints,
    required this.selectedId,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selected = selectedId == null
        ? null
        : resolved[selectedId!]?.valueOrNull;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      children: [
        for (final category in categories) ...[
          Builder(builder: (context) {
            final result = resolved[category.id];
            return FareCategoryCard(
              category: category,
              farePence: (result is Ok<FareEstimate>) ? result.value.totalPence : null,
              durationSeconds:
                  (result is Ok<FareEstimate>) ? result.value.durationSeconds : null,
              selected: category.id == selectedId,
              isLoading: result == null,
              errorMessage: (result is Err<FareEstimate>)
                  ? RiderErrorCopy.messageFor(result.error)
                  : null,
              onTap: () => onSelect(category.id),
            );
          }),
          const SizedBox(height: 14),
        ],
        if (selected != null && selected.isMultiStop && selected.legs.isNotEmpty) ...[
          const SizedBox(height: 6),
          FareLegsBreakdown(legs: selected.legs, totalPence: selected.totalPence),
          const SizedBox(height: 16),
        ],
        // Waiting is never in the estimate and accrues live -- state that it
        // may apply without ever attaching a number the app cannot know.
        Text(
          waypoints.isEmpty
              ? 'Waiting time may apply and is charged live during the trip.'
              : 'Waiting time may apply at each stop and is charged live '
                  'during the trip.',
          style: theme.textTheme.bodyMedium,
        ),
      ],
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _RoundIconButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Material(
      color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Icon(icon, color: theme.colorScheme.onSurface),
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 40, color: AppColors.negative),
            const SizedBox(height: 16),
            Text(message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge),
            const SizedBox(height: 16),
            TextButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.local_taxi_outlined,
                size: 40,
                color: Theme.of(context).textTheme.bodyMedium?.color),
            const SizedBox(height: 16),
            Text('No vehicle categories to price yet',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge),
          ],
        ),
      ),
    );
  }
}
