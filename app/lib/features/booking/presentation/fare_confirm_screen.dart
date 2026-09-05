import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MaxLengthEnforcement;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmaps;
import 'package:pointer_interceptor/pointer_interceptor.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/api/error_codes.dart';
import '../../../core/result.dart';
import '../../../core/theme/colors.dart';
import '../../payments/data/payment_methods_repository.dart';
import '../../payments/presentation/widgets/payment_method_sheet.dart';
import '../../trip/data/live_trip_source.dart' show TripWaypoint;
import '../../trip/presentation/widgets/trip_route_header.dart';
import '../application/booking_draft.dart';
import '../data/fare_repository.dart';
import '../data/vehicle_repository.dart';
import 'widgets/fare_legs_breakdown.dart';
import 'widgets/map_markers.dart';
import 'widgets/rider_map.dart';
import 'widgets/vehicle_card.dart';

/// The default card the booking will charge — the frame's payment row.
final _defaultCardProvider = FutureProvider.autoDispose<SavedCard?>((
  ref,
) async {
  final result = await ref.watch(paymentMethodsRepositoryProvider).list();
  return switch (result) {
    Ok(:final value) =>
      value.where((c) => c.isDefault).firstOrNull ?? value.firstOrNull,
    // No card is a state the screen renders ("Add a payment card"), never an
    // error that blocks seeing the fare.
    Err() => null,
  };
});

/// Fare / confirm-booking — the frames' `Ride Details.png` sheet over the
/// live map, with the dark route panel on top.
///
/// **The picker rows are vehicle categories, not drivers.** Dispatch solves a
/// Hungarian assignment and publishes exactly one match; there is no
/// endpoint returning candidate drivers, so this screen must never render a
/// list of named drivers to pick from (the frame's George card belongs to
/// the live-trip screen, once a driver actually exists). One
/// `POST /rides/estimate` is quoted per category and the primary button
/// CONFIRMS THE BOOKING. See `docs/SCREEN-DECISIONS.md`.
///
/// The frame draws Base + Surge fare rows; the estimate endpoint returns a
/// total (with per-leg splits on multi-stop) and no base/surge split, so the
/// card shows the real numbers honestly rather than inventing a split.
///
/// All constructor parameters are optional so the router can construct this
/// with no arguments; with no [categories] supplied there is simply nothing
/// to quote and the screen renders its empty state.
class FareConfirmScreen extends ConsumerStatefulWidget {
  final LatLng pickup;
  final LatLng dropoff;
  final List<LatLng> waypoints;
  final List<VehicleCategory> categories;

  /// Pickup → stops → dropoff display labels for the route panel, in order.
  final List<String> routeLabels;

  /// Called with the chosen category and its resolved quote once the rider
  /// taps Confirm. The caller (booking flow) owns what happens next — this
  /// screen only owns picking a category and fare, then confirming.
  /// [note] is the rider's free-text instruction for the driver — empty when
  /// they left it blank, which is most trips.
  final void Function(
    VehicleCategory category,
    FareEstimate? estimate,
    String note,
  )?
  onConfirm;

  const FareConfirmScreen({
    super.key,
    this.pickup = const LatLng(0, 0),
    this.dropoff = const LatLng(0, 0),
    this.waypoints = const [],
    this.categories = const [],
    this.routeLabels = const [],
    this.onConfirm,
  });

  @override
  ConsumerState<FareConfirmScreen> createState() => _FareConfirmScreenState();
}

class _FareConfirmScreenState extends ConsumerState<FareConfirmScreen> {
  /// One quote per category, filled in as each `POST /rides/estimate` lands;
  /// the sheet re-renders reactively off this map.
  final Map<String, Result<FareEstimate>> _resolved = {};

  /// Owned by the screen, not the sheet: the sheet is rebuilt on every drag
  /// and every fare that resolves, and a controller created down there would
  /// wipe a half-typed note each time.
  final _note = TextEditingController();
  String? _selectedId;

  /// A pin, every stop numbered, dropoff B — built async (canvas bitmaps).
  Set<gmaps.Marker> _markers = const {};

  @override
  void initState() {
    super.initState();
    // The vehicle picked on Home rides through: arrive preselected with its
    // quote loading rather than asking the rider to choose again. Nothing
    // picked → the grid works exactly as before.
    final draft = ref.read(draftVehicleCategoryProvider);
    if (draft != null && widget.categories.any((c) => c.id == draft)) {
      _selectedId = draft;
    }
    _fetchAll();
    _buildMarkers();
  }

  /// Pickup A (blue), every stop its own numbered orange pin, dropoff B
  /// (green) — the rider must see exactly where Stop 1 and Stop 2 sit.
  Future<void> _buildMarkers() async {
    // No engine, no bitmaps: tests and desktop render the placeholder, and
    // the canvas futures would outlive a test's teardown.
    if (!RiderMap.mapSupported) return;
    String labelAt(int i) =>
        i < widget.routeLabels.length ? widget.routeLabels[i] : '';

    final markers = <gmaps.Marker>{
      gmaps.Marker(
        markerId: const gmaps.MarkerId('pickup'),
        position: gmaps.LatLng(widget.pickup.lat, widget.pickup.lng),
        icon: await circleLabelMarker('A', AppColors.info),
        infoWindow: gmaps.InfoWindow(
          title: labelAt(0).isEmpty ? 'Pickup' : labelAt(0),
        ),
      ),
      for (var i = 0; i < widget.waypoints.length; i++)
        gmaps.Marker(
          markerId: gmaps.MarkerId('stop${i + 1}'),
          position: gmaps.LatLng(
            widget.waypoints[i].lat,
            widget.waypoints[i].lng,
          ),
          icon: await circleLabelMarker('${i + 1}', AppColors.accent),
          infoWindow: gmaps.InfoWindow(
            title: labelAt(i + 1).isEmpty
                ? 'Stop ${i + 1}'
                : 'Stop ${i + 1} — ${labelAt(i + 1)}',
          ),
        ),
      gmaps.Marker(
        markerId: const gmaps.MarkerId('dropoff'),
        position: gmaps.LatLng(widget.dropoff.lat, widget.dropoff.lng),
        icon: await circleLabelMarker('B', AppColors.positive),
        infoWindow: gmaps.InfoWindow(
          title: labelAt(widget.routeLabels.length - 1).isEmpty
              ? 'Dropoff'
              : labelAt(widget.routeLabels.length - 1),
        ),
      ),
    };
    if (mounted) setState(() => _markers = markers);
  }

  void _fetchAll() {
    _resolved.clear();
    if (widget.categories.isEmpty) {
      // Nothing to quote -- skip resolving the repository entirely so
      // constructing this screen with no arguments (as the router does)
      // never needs a working ApiClient.
      return;
    }
    final repo = ref.read(fareRepositoryProvider);
    for (final category in widget.categories) {
      _fetchOne(repo, category);
    }
  }

  Future<Result<FareEstimate>> _fetchOne(
    FareRepository repo,
    VehicleCategory category,
  ) async {
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

  bool get _selectedHasFare => _resolved[_selectedId] is Ok<FareEstimate>;

  FareEstimate? get _selectedEstimate => _resolved[_selectedId]?.valueOrNull;

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.of(context).padding.top;

    final allFailed =
        widget.categories.isNotEmpty &&
        _resolved.length == widget.categories.length &&
        _resolved.values.every((r) => r is Err<FareEstimate>);

    // The chosen estimate's real geometry, drawn on the map behind the sheet.
    final est = _selectedEstimate;
    final polylines = <gmaps.Polyline>{
      if (est?.route case final route? when route.length >= 2)
        gmaps.Polyline(
          polylineId: const gmaps.PolylineId('estimate'),
          points: [for (final p in route) gmaps.LatLng(p.lat, p.lng)],
          color: AppColors.navy,
          width: 5,
        ),
    };

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: RiderMap(
              camera: gmaps.CameraPosition(
                target: gmaps.LatLng(widget.pickup.lat, widget.pickup.lng),
                zoom: 13,
              ),
              markers: _markers,
              polylines: polylines,
              padding: const EdgeInsets.only(bottom: 320),
            ),
          ),
          // The frame's dark route panel, top of the map.
          if (widget.routeLabels.length >= 2)
            Positioned(
              top: topInset + 12,
              left: 16,
              right: 16,
              child: TripRouteHeader(
                waypoints: [
                  for (final label in widget.routeLabels)
                    TripWaypoint(
                      label: label,
                      distanceLabel: null,
                      position: null,
                    ),
                ],
              ),
            ),
          // Collapsible: drag down to a peek to see the whole route on the
          // map, back up to book. Snaps between peek and open.
          DraggableScrollableSheet(
            initialChildSize: 0.62,
            minChildSize: 0.14,
            maxChildSize: 0.92,
            snap: true,
            snapSizes: const [0.14, 0.62],
            // PointerInterceptor: on web the map is a DOM platform view and
            // touches over the sheet can fall through and pan it underneath.
            builder: (context, scrollController) =>
                PointerInterceptor(child: _Sheet(
              scrollController: scrollController,
              categories: widget.categories,
              resolved: _resolved,
              selectedId: _selectedId,
              onSelect: (id) => setState(() => _selectedId = id),
              allFailed: allFailed,
              onRetry: _retry,
              firstError: allFailed
                  ? _resolved.values.whereType<Err<FareEstimate>>().first.error
                  : null,
              waypoints: widget.waypoints,
              confirmEnabled: _selectedId != null && _selectedHasFare,
              noteController: _note,
              onConfirm: () {
                final category = widget.categories.firstWhere(
                  (c) => c.id == _selectedId,
                );
                widget.onConfirm
                    ?.call(category, _selectedEstimate, _note.text.trim());
              },
            )),
          ),
        ],
      ),
    );
  }
}

class _Sheet extends ConsumerWidget {
  final ScrollController scrollController;
  final List<VehicleCategory> categories;
  final Map<String, Result<FareEstimate>> resolved;
  final String? selectedId;
  final ValueChanged<String> onSelect;
  final bool allFailed;
  final ApiException? firstError;
  final VoidCallback onRetry;
  final List<LatLng> waypoints;
  final bool confirmEnabled;
  final TextEditingController noteController;
  final VoidCallback onConfirm;

  const _Sheet({
    required this.scrollController,
    required this.categories,
    required this.resolved,
    required this.selectedId,
    required this.onSelect,
    required this.allFailed,
    required this.firstError,
    required this.onRetry,
    required this.waypoints,
    required this.confirmEnabled,
    required this.noteController,
    required this.onConfirm,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return Material(
      color: const Color(0xFFF7F7FA),
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      clipBehavior: Clip.antiAlias,
      elevation: 12,
      // Everything, handle included, lives INSIDE the sheet's scrollable —
      // DraggableScrollableSheet only follows drags that flow through its
      // controller, so a handle outside the list could never collapse it.
      child: ListView(
        controller: scrollController,
        padding: EdgeInsets.fromLTRB(
          16,
          8,
          16,
          MediaQuery.of(context).padding.bottom + 12,
        ),
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFD5D5DC),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Text(
                  'Ride Details',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontSize: 16.5,
                    color: AppColors.navy,
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: Material(
                    color: const Color(0xFFE3E3E8),
                    shape: const CircleBorder(),
                    child: InkWell(
                      onTap: () => Navigator.of(context).maybePop(),
                      customBorder: const CircleBorder(),
                      child: const Padding(
                        padding: EdgeInsets.all(6),
                        child: Icon(
                          Icons.close,
                          size: 16,
                          color: AppColors.lightTextSecondary,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (categories.isEmpty)
                const _EmptyState()
              else if (allFailed)
                _ErrorState(
                  message: _messageFor(firstError!, waypoints),
                  onRetry: onRetry,
                )
              else ...[
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: categories.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    mainAxisExtent: 66,
                  ),
                  itemBuilder: (_, i) {
                    final c = categories[i];
                    return VehicleCard(
                      category: c,
                      selected: c.id == selectedId,
                      onTap: () => onSelect(c.id),
                    );
                  },
                ),
                const SizedBox(height: 14),
                Text(
                  'Fare Estimate',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontSize: 15,
                    color: AppColors.navy,
                  ),
                ),
                const SizedBox(height: 8),
                _FareCard(
                  selectedId: selectedId,
                  resolved: resolved,
                  waypoints: waypoints,
                ),
                const SizedBox(height: 14),
                _PaymentRow(
                  onChanged: () => ref.invalidate(_defaultCardProvider),
                ),
                const SizedBox(height: 14),
                _DriverNoteField(controller: noteController),
                const SizedBox(height: 14),
                // Waiting is never in the estimate and accrues live --
                // state that it may apply without attaching a number the
                // app cannot know.
                Text(
                  'Cancellation Policy',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontSize: 15,
                    color: AppColors.navy,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Cancelling after driver assignment may incur a fee. '
                  '${waypoints.isEmpty ? 'Waiting time may apply and is charged live during the trip.' : 'Waiting time may apply at each stop and is charged live during the trip.'}',
                  style: theme.textTheme.bodyMedium?.copyWith(fontSize: 12),
                ),
                const SizedBox(height: 14),
                FilledButton(
                  onPressed: confirmEnabled ? onConfirm : null,
                  child: const Text('Confirm Booking'),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  static String _messageFor(ApiException error, List<LatLng> waypoints) {
    if ((error.code == 'NO_ZONE' || error.code == 'NO_TARIFF') &&
        waypoints.isNotEmpty) {
      // The server does not report which stop failed, and with up to five
      // stops the rider cannot guess — so every stop is named rather than
      // pointing at "this" stop.
      final stops = List.generate(
        waypoints.length,
        (i) => 'Stop ${i + 1}',
      ).join(', ');
      return '${RiderErrorCopy.messageFor(error)} Check your stops: $stops.';
    }
    return RiderErrorCopy.messageFor(error);
  }
}

/// Anything the driver needs to know before they arrive.
///
/// Optional and unlabelled as required, because most trips need nothing said.
/// Capped at the column's 300 characters (mig 130) with the counter only
/// appearing near the limit — a live "0/300" under an empty optional box reads
/// as a form to fill in.
class _DriverNoteField extends StatelessWidget {
  final TextEditingController controller;

  const _DriverNoteField({required this.controller});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Note for your driver',
          style: theme.textTheme.titleMedium
              ?.copyWith(fontSize: 15, color: AppColors.navy),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          maxLines: 2,
          maxLength: 300,
          maxLengthEnforcement: MaxLengthEnforcement.enforced,
          textInputAction: TextInputAction.done,
          textCapitalization: TextCapitalization.sentences,
          style: const TextStyle(fontSize: 13),
          buildCounter: (context,
              {required currentLength, required isFocused, maxLength}) {
            if (currentLength < 240) return null;
            return Text('$currentLength/$maxLength',
                style: theme.textTheme.bodySmall);
          },
          decoration: InputDecoration(
            hintText: 'Optional — e.g. second gate past the barrier',
            hintStyle: const TextStyle(fontSize: 13),
            filled: true,
            fillColor: Colors.white,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFE3E3E8)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFE3E3E8)),
            ),
          ),
        ),
      ],
    );
  }
}

/// The white fare card: legs for a multi-stop trip, then the total — the
/// real quote for the selected category.
class _FareCard extends StatelessWidget {
  final String? selectedId;
  final Map<String, Result<FareEstimate>> resolved;
  final List<LatLng> waypoints;

  const _FareCard({
    required this.selectedId,
    required this.resolved,
    required this.waypoints,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Widget inner;
    final result = selectedId == null ? null : resolved[selectedId];
    if (selectedId == null) {
      inner = Text(
        'Select a vehicle to see your fare.',
        style: theme.textTheme.bodyMedium,
      );
    } else if (result == null) {
      inner = const Center(
        child: Padding(
          padding: EdgeInsets.all(6),
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    } else if (result is Err<FareEstimate>) {
      inner = Text(
        RiderErrorCopy.messageFor(result.error),
        style: const TextStyle(color: AppColors.negative, fontSize: 13),
      );
    } else {
      final est = (result as Ok<FareEstimate>).value;
      final km = (est.distanceMeters / 1000).toStringAsFixed(1);
      final mins = (est.durationSeconds / 60).round();
      inner = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (est.isMultiStop && est.legs.isNotEmpty) ...[
            FareLegsBreakdown(legs: est.legs, totalPence: est.totalPence),
            const Divider(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Total',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontSize: 15,
                    color: AppColors.navy,
                  ),
                ),
                // The API's grand total, never a client-side re-sum.
                Text(
                  est.totalPence.format(currency: est.currency),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontSize: 15,
                    color: AppColors.navy,
                  ),
                ),
              ],
            ),
          ] else ...[
            _row(theme, 'Distance', '$km km'),
            const SizedBox(height: 6),
            _row(theme, 'Time', '$mins min'),
            const Divider(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Total',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontSize: 15,
                    color: AppColors.navy,
                  ),
                ),
                Text(
                  est.totalPence.format(currency: est.currency),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontSize: 15,
                    color: AppColors.navy,
                  ),
                ),
              ],
            ),
          ],
        ],
      );
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: inner,
    );
  }

  Widget _row(ThemeData theme, String label, String value) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text(label, style: theme.textTheme.bodyMedium),
      Text(value, style: theme.textTheme.bodyLarge?.copyWith(fontSize: 14)),
    ],
  );
}

/// The frame's payment row: brand + masked digits with the green check;
/// tapping opens the existing payment-method sheet.
class _PaymentRow extends ConsumerWidget {
  final VoidCallback onChanged;
  const _PaymentRow({required this.onChanged});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final card = ref.watch(_defaultCardProvider).valueOrNull;

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      elevation: 1,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () async {
          await showPaymentMethodSheet(context);
          onChanged();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          child: Row(
            children: [
              const Icon(Icons.credit_card, size: 22, color: AppColors.navy),
              const SizedBox(width: 12),
              Expanded(
                child: card == null
                    ? Text(
                        'Add a payment card',
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontSize: 14,
                        ),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _brandName(card.brand),
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontSize: 14,
                              color: AppColors.navy,
                            ),
                          ),
                          Text(
                            '**** **** **** ${card.last4}',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
              ),
              if (card != null)
                const Icon(Icons.verified, size: 20, color: AppColors.positive),
            ],
          ),
        ),
      ),
    );
  }

  static String _brandName(String brand) =>
      brand.isEmpty ? 'Card' : brand[0].toUpperCase() + brand.substring(1);
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
            const Icon(
              Icons.error_outline,
              size: 40,
              color: AppColors.negative,
            ),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
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
            Icon(
              Icons.local_taxi_outlined,
              size: 40,
              color: Theme.of(context).textTheme.bodyMedium?.color,
            ),
            const SizedBox(height: 16),
            Text(
              'No vehicle categories to price yet',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ],
        ),
      ),
    );
  }
}
