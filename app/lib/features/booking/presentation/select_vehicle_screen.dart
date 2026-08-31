import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/result.dart';
import '../../../core/theme/colors.dart';
import '../data/vehicle_repository.dart';
import 'widgets/vehicle_card.dart';

/// Loads the live vehicle catalogue. A plain [FutureProvider.autoDispose] —
/// no caching layer needed, since this screen's own retry button is the only
/// thing that ever re-triggers it.
final _vehicleCatalogueProvider =
    FutureProvider.autoDispose<List<VehicleCategory>>((ref) async {
  final result = await ref.watch(vehicleRepositoryProvider).list();
  return switch (result) {
    Ok(:final value) => value,
    Err(:final error) => throw error,
  };
});

/// Full-screen vehicle picker — "Select Vehicle" in the design pack.
///
/// Renders every category `GET /vehicle-types` returns, with live seats/bags,
/// never the four hardcoded in the design (three of those four are wrong,
/// and MiniCar + MiniTruck are bookable but undrawn). Artwork is keyed by
/// category name with a generic fallback in [VehicleCard] — required because
/// the API has no image field and categories are admin-editable.
class SelectVehicleScreen extends ConsumerStatefulWidget {
  /// Called when the rider taps a category. The caller (booking flow) owns
  /// what happens next — this screen only owns picking.
  final ValueChanged<VehicleCategory>? onSelected;

  const SelectVehicleScreen({super.key, this.onSelected});

  @override
  ConsumerState<SelectVehicleScreen> createState() =>
      _SelectVehicleScreenState();
}

class _SelectVehicleScreenState extends ConsumerState<SelectVehicleScreen> {
  String? _selectedId;

  @override
  Widget build(BuildContext context) {
    final catalogue = ref.watch(_vehicleCatalogueProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Select Vehicle')),
      body: SafeArea(
        child: catalogue.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => _ErrorState(
            message: _messageFor(error),
            onRetry: () => ref.invalidate(_vehicleCatalogueProvider),
          ),
          data: (categories) {
            // hasCapacity filters rows the API COALESCEd to 0/0 - rendering
            // "0 Seats 0 Bags" would state something false.
            final bookable =
                categories.where((c) => c.hasCapacity).toList(growable: false);

            if (bookable.isEmpty) {
              return const _EmptyState();
            }

            return GridView.builder(
              padding: const EdgeInsets.all(20),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 16,
                crossAxisSpacing: 16,
                childAspectRatio: 0.95,
              ),
              itemCount: bookable.length,
              itemBuilder: (context, index) {
                final category = bookable[index];
                return VehicleCard(
                  category: category,
                  selected: category.id == _selectedId,
                  onTap: () {
                    setState(() => _selectedId = category.id);
                    widget.onSelected?.call(category);
                  },
                );
              },
            );
          },
        ),
      ),
    );
  }

  // ApiException carries server-owned copy in `.message`; anything else (a
  // network failure, say) falls back to generic text rather than surfacing
  // a raw exception string to the rider.
  String _messageFor(Object error) =>
      error is ApiException ? error.message : 'Something went wrong';
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
            Icon(Icons.directions_car_outlined,
                size: 40,
                color: Theme.of(context).textTheme.bodyMedium?.color),
            const SizedBox(height: 16),
            Text('No vehicles available right now',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge),
          ],
        ),
      ),
    );
  }
}
