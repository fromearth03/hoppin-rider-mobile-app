import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/money.dart';
import '../../../../core/result.dart';
import '../../../../core/theme/colors.dart';
import '../../../../shared/widgets/bottom_scroll_fade.dart';
import '../../../payments/data/payment_methods_repository.dart';
import '../../../payments/presentation/widgets/payment_method_sheet.dart';
import '../../data/live_trip_source.dart';

/// The rider's default card, for the chip the frame draws under the fare.
/// Null (chip hidden) on any failure — a payment chip must never guess.
final _defaultCardProvider =
    FutureProvider.autoDispose<SavedCard?>((ref) async {
  final result = await ref.watch(paymentMethodsRepositoryProvider).list();
  return switch (result) {
    Ok(:final value) => value.where((c) => c.isDefault).firstOrNull ??
        value.firstOrNull,
    Err() => null,
  };
});

/// The bottom card on `Driver Arrived.png` / `Start Ride.png`: driver photo,
/// name, rating with count, chat / safety shortcuts and Cancel Ride.
///
/// Renders the awaiting-match state -- [driver] null -- as a real designed
/// state rather than a blank card or a crash, per the decisions doc: `driver`
/// is null while matching, a normal state, not an error.
///
/// The call button drawn in the Figma is NOT built: `RideDriverInfoView`
/// exposes no phone number (`ride_context_repo.go:20-38`), so a button here
/// would do nothing -- worse than its absence, since a rider taps it when
/// they need the driver most. Deferred to phase 2 per SCREEN-DECISIONS.md.
class DriverInfoCard extends ConsumerStatefulWidget {
  final TripDriver? driver;
  final VoidCallback onChat;
  final VoidCallback onSafety;
  final VoidCallback onCancel;

  /// The fare block from `GET /rides/:id` — estimate/total only; this
  /// endpoint has no base/surge split, so the card shows the real number
  /// and invents nothing (frame deviation recorded in SCREEN-DECISIONS.md).
  final Pence? totalPence;
  final String currency;

  const DriverInfoCard({
    super.key,
    required this.driver,
    required this.onChat,
    required this.onSafety,
    required this.onCancel,
    this.totalPence,
    this.currency = 'GBP',
  });

  @override
  ConsumerState<DriverInfoCard> createState() => _DriverInfoCardState();
}

class _DriverInfoCardState extends ConsumerState<DriverInfoCard> {
  /// The frame's X collapses the details back to the compact driver row so
  /// the map breathes; tapping the collapsed header reopens it.
  bool _collapsed = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final d = widget.driver;
    // Bound the details so the map stays visible; inside the bound the
    // content scrolls under the frame's bottom fade, and Cancel Booking
    // stays pinned below it — veiled content behind, solid button in front,
    // exactly the frame's materialise-at-the-end behaviour.
    final maxDetailsHeight = MediaQuery.of(context).size.height * 0.42;

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
          if (d == null)
            _AwaitingDriverRow(theme: theme)
          else ...[
            // `Ride Details.png`: centred title, X top-right.
            Stack(
              alignment: Alignment.center,
              children: [
                Center(
                  child: Text('Ride Details',
                      style: theme.textTheme.titleMedium),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: Icon(
                        _collapsed
                            ? Icons.keyboard_arrow_up
                            : Icons.close,
                        size: 20),
                    tooltip: _collapsed ? 'Show details' : 'Hide details',
                    onPressed: () =>
                        setState(() => _collapsed = !_collapsed),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _AssignedDriverRow(
              driver: d,
              theme: theme,
              onChat: widget.onChat,
              onSafety: widget.onSafety,
            ),
            if (!_collapsed) ...[
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: maxDetailsHeight),
                child: BottomScrollFade(
                  height: 56,
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Divider(height: 1),
                        const SizedBox(height: 4),
                        _SpecRow(
                            label: 'Complete Rides',
                            value: '${d.tripsCompleted}'),
                        if (d.hasRating)
                          _SpecRow(
                              label: 'Driver Review',
                              value:
                                  '${d.rating!.toStringAsFixed(1)} Rating'),
                        if (d.plate != null)
                          _SpecRow(
                              label: 'Vehicle Number', value: d.plate!),
                        if (d.vehicleType != null)
                          _SpecRow(
                              label: 'Vehicle Type', value: d.vehicleType!),
                        if (d.hasCapacity)
                          _SpecRow(
                              label: 'Capacity',
                              value: '${d.seats} Seats ${d.bags} Bags'),
                        if (widget.totalPence != null) ...[
                          const SizedBox(height: 4),
                          const Divider(height: 1),
                          const SizedBox(height: 4),
                          _SpecRow(
                            label: 'Total',
                            value: widget.totalPence!
                                .format(currency: widget.currency),
                            emphasised: true,
                          ),
                        ],
                        _DefaultCardChip(theme: theme),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ],
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: widget.onCancel,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryDark,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            // The frame labels the pre-pickup action Cancel Booking.
            child: Text(d == null ? 'Cancel Ride' : 'Cancel Booking'),
          ),
        ],
      ),
    );
  }
}

/// One "label ......... value" line of the frame's spec block.
class _SpecRow extends StatelessWidget {
  final String label;
  final String value;
  final bool emphasised;

  const _SpecRow({
    required this.label,
    required this.value,
    this.emphasised = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style =
        emphasised ? theme.textTheme.titleMedium : theme.textTheme.bodyMedium;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
          const SizedBox(width: 12),
          Text(value,
              style: style?.copyWith(
                  color: theme.textTheme.bodyLarge?.color)),
        ],
      ),
    );
  }
}

/// The default card chip under the fare, per the frame ("Visa Classic ····
/// ✓"). Tapping opens the payment sheet; hidden entirely when no card
/// could be read — a payment chip must never guess.
class _DefaultCardChip extends ConsumerWidget {
  final ThemeData theme;
  const _DefaultCardChip({required this.theme});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final card = ref.watch(_defaultCardProvider).valueOrNull;
    if (card == null) return const SizedBox.shrink();

    final isDark = theme.brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => showPaymentMethodSheet(context),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
          ),
          child: Row(
            children: [
              Icon(Icons.credit_card,
                  size: 20, color: theme.textTheme.bodyLarge?.color),
              const SizedBox(width: 10),
              Expanded(
                child: Text(card.displayLabel,
                    style: theme.textTheme.bodyLarge),
              ),
              const Icon(Icons.check_circle,
                  color: AppColors.positive, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

class _AwaitingDriverRow extends StatelessWidget {
  final ThemeData theme;
  const _AwaitingDriverRow({required this.theme});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2.5),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Finding your driver', style: theme.textTheme.titleMedium),
              Text(
                'This usually takes a moment',
                style: theme.textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AssignedDriverRow extends StatelessWidget {
  final TripDriver driver;
  final ThemeData theme;
  final VoidCallback onChat;
  final VoidCallback onSafety;

  const _AssignedDriverRow({
    required this.driver,
    required this.theme,
    required this.onChat,
    required this.onSafety,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        CircleAvatar(
          radius: 22,
          backgroundColor: AppColors.buttonPrimary.withValues(alpha: 0.25),
          child: Text(
            driver.name.isNotEmpty ? driver.name[0].toUpperCase() : '?',
            style: theme.textTheme.titleMedium,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(driver.name, style: theme.textTheme.titleMedium),
              // Rating is nullable and never defaulted: a new driver with no
              // rating yet must not be shown a fabricated score.
              if (driver.hasRating)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.star, size: 16, color: AppColors.warning),
                    const SizedBox(width: 4),
                    Text(
                      '${driver.rating!.toStringAsFixed(1)} (${driver.ratingCount})',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                ),
            ],
          ),
        ),
        // Call is deferred to phase 2 -- no phone number exists on any
        // endpoint. Chat and SOS are the two real controls.
        IconButton(
          onPressed: onChat,
          icon: const Icon(Icons.chat_bubble, color: AppColors.primary),
        ),
        IconButton(
          onPressed: onSafety,
          icon: const Icon(Icons.warning_rounded, color: AppColors.negative),
        ),
      ],
    );
  }
}
