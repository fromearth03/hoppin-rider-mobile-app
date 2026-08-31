import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/api/error_codes.dart';
import '../../../core/result.dart';
import '../../../core/theme/colors.dart';
import '../data/vehicle_repository.dart';
import 'widgets/map_placeholder.dart';
import 'widgets/vehicle_card.dart';

/// The categories the rider can book, cheapest first.
///
/// Order comes from the server and is preserved. Re-sorting client-side would
/// reorder the picker away from what the operator configured in the admin
/// panel.
final vehicleCategoriesProvider =
    FutureProvider.autoDispose<List<VehicleCategory>>((ref) async {
  final result = await ref.watch(vehicleRepositoryProvider).list();
  return switch (result) {
    Ok(:final value) => value,
    Err(:final error) => throw error,
  };
});

/// Home: a full-bleed map with a booking sheet over it.
///
/// The map is a placeholder until a Maps SDK key exists; everything else here
/// is live against the real backend.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  String? _selectedCategoryId;

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(vehicleCategoriesProvider);

    return Scaffold(
      body: Stack(
        children: [
          const Positioned.fill(child: MapPlaceholder()),
          Positioned(
            top: MediaQuery.of(context).padding.top + 12,
            left: 16,
            child: _CircleButton(
              icon: Icons.menu,
              onTap: () => Scaffold.of(context).openDrawer(),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: _BookingSheet(
              categories: categories,
              selectedId: _selectedCategoryId,
              onSelect: (id) => setState(() => _selectedCategoryId = id),
            ),
          ),
        ],
      ),
    );
  }
}

class _CircleButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _CircleButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      shape: const CircleBorder(),
      elevation: 2,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Icon(icon, size: 22),
        ),
      ),
    );
  }
}

class _BookingSheet extends StatelessWidget {
  final AsyncValue<List<VehicleCategory>> categories;
  final String? selectedId;
  final ValueChanged<String> onSelect;

  const _BookingSheet({
    required this.categories,
    required this.selectedId,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        MediaQuery.of(context).padding.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _ModeRow(),
          const SizedBox(height: 14),
          _Categories(
            categories: categories,
            selectedId: selectedId,
            onSelect: onSelect,
          ),
          const SizedBox(height: 14),
          const _SearchField(),
        ],
      ),
    );
  }
}

/// "Ride Type" and "Schedule Ride", as drawn.
class _ModeRow extends StatelessWidget {
  const _ModeRow();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.primary, width: 1.5),
            ),
            child: Row(
              children: [
                const Icon(Icons.directions_car,
                    color: AppColors.accent, size: 26),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Ride Type', style: theme.textTheme.titleMedium),
                      Text('Pick the vehicle that fits your trip',
                          style: theme.textTheme.bodyMedium,
                          overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 10),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Icon(Icons.event, color: AppColors.primary, size: 26),
        ),
      ],
    );
  }
}

class _Categories extends StatelessWidget {
  final AsyncValue<List<VehicleCategory>> categories;
  final String? selectedId;
  final ValueChanged<String> onSelect;

  const _Categories({
    required this.categories,
    required this.selectedId,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return categories.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: Center(child: CircularProgressIndicator()),
      ),
      // The server's own message, never invented copy: one backend code
      // carries two unrelated meanings distinguished only by its text.
      error: (e, _) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Text(
          e is ApiException
              ? RiderErrorCopy.messageFor(e)
              : 'Could not load vehicles.',
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.negative),
        ),
      ),
      data: (list) {
        if (list.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Text('No vehicles available right now.',
                textAlign: TextAlign.center),
          );
        }

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: list.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            mainAxisExtent: 74,
          ),
          itemBuilder: (_, i) {
            final c = list[i];
            return VehicleCard(
              category: c,
              selected: c.id == selectedId,
              onTap: () => onSelect(c.id),
            );
          },
        );
      },
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(Icons.search,
              color: theme.textTheme.bodyMedium?.color, size: 22),
          const SizedBox(width: 10),
          Text('Where to & for how much?', style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}
