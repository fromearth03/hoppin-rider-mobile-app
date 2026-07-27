import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hoppin_shared/hoppin_shared.dart';
import 'package:hoppin_ui/hoppin_ui.dart';

/// The LIVE vehicle classes — `GET /vehicle-types`.
///
/// This is the read the static list below was written to be replaced by. It
/// returns real `vehicle_category_id`s from admin's `vehicle_categories` table,
/// which is what makes XL and Accessibility bookable rather than disclosed-as-
/// unavailable.
///
/// Returns an EMPTY list on failure (the repository swallows the error), and an
/// empty list is deliberately treated as "no live data" by the consumer, which
/// then keeps the static fallback. A rider must never see an empty ride-type
/// picker because a lookup call failed.
final vehicleTypesProvider =
    FutureProvider.autoDispose<List<VehicleType>>((ref) {
  return ref.watch(ridesRepositoryProvider).vehicleTypes();
});

/// Maps a live class onto the selector's view model.
///
/// Every live row is [RideTypeOption.bookable] — it carries a real id, so the
/// server can honour it. The glyph is matched on name because the API has no
/// icon field; an unrecognised class gets the generic car rather than being
/// dropped, since a class we cannot draw is still a class we can book.
RideTypeOption _optionFor(VehicleType v) {
  final n = v.name.toLowerCase();
  final icon = n.contains('access') || n.contains('wheelchair')
      ? Icons.accessible
      : (n.contains('xl') || n.contains('large') || n.contains('van')
          ? Icons.airport_shuttle
          : Icons.directions_car);

  // Only print a capacity line for figures the admin actually set — "0 seats"
  // reads as a broken product.
  final parts = <String>[
    if (v.seats > 0) '${v.seats} seats',
    if (v.bags > 0) 'Upto ${v.bags} bags',
  ];

  return RideTypeOption(
    id: v.id,
    label: v.name,
    capacity: parts.join(' • '),
    icon: icon,
  );
}

/// The live classes as selector options, or null when there are none to show.
///
/// Null (not an empty list) is what tells the selector to keep its disclosed
/// static fallback.
List<RideTypeOption>? rideTypeOptionsFrom(List<VehicleType> live) =>
    live.isEmpty ? null : live.map(_optionFor).toList();

/// One selectable ride-type / vehicle class.
///
/// [id] is the `vehicle_category_id` threaded into `POST /rides/estimate` and
/// `POST /rides/request`. A `null` id is a first-class value: the server
/// defaults to Standard when the field is absent, so Standard ships with a
/// `null` id until the real category uuids arrive — see the SL-1 disclosure
/// below. This keeps the seam honest (no invented uuid) while the app already
/// speaks the live contract.
@immutable
class RideTypeOption {
  const RideTypeOption({
    required this.id,
    required this.label,
    required this.capacity,
    required this.icon,
    this.bookable = true,
  });

  /// The `vehicle_category_id` (null → server-default Standard).
  final String? id;

  /// Rider-facing class name — "Standard" / "XL" / "Accessibility".
  final String label;

  /// Seats/bags supporting line.
  final String capacity;

  /// Class glyph.
  final IconData icon;

  /// Whether this class can actually be booked right now.
  ///
  /// False for any class we cannot name to the server. Until
  /// `GET /vehicle-categories` ships (gap #65) we do not know the real
  /// `vehicle_category_id` for XL or Accessibility — and a booking button that
  /// sends a category id the backend has never seen is a promise we cannot
  /// keep. Especially for Accessibility: a rider who needs a wheelchair-
  /// accessible vehicle must get one, or be told plainly that they cannot book
  /// it here yet. They must never be quietly handed whatever the server does
  /// with an unknown id.
  ///
  /// Unbookable classes still RENDER — they are real products and hiding them
  /// would misrepresent the service — but they are not selectable, and the
  /// selector says why.
  final bool bookable;
}

/// ⚠️ SL-1 DISCLOSED STATIC SEAM — `:8080` exposes NO `GET /vehicle-categories`
/// list endpoint (SCOPE-TRACE row 6, MISSING-BE). Ride categories are
/// admin-configured data, so this is deliberately a STATIC config list, NOT a
/// live-list fetch. `POST /rides/estimate` + `POST /rides/request` already
/// accept `vehicle_category_id`, so the moment the list endpoint lands this
/// const is swapped for the live read with ZERO change to the selector, the
/// interactor, or the threading — a pure body-swap.
///
/// ⚠️ **WAVE-0 (2026-07-12): XL and Accessibility CANNOT BE BOOKED.**
///
/// Standard is genuinely bookable — `id: null` means "server default", which
/// the backend resolves itself. It is real and it works.
///
/// XL and Accessibility carried **fabricated placeholder uuids** the database
/// has never seen, while rendering as confident, first-class, selectable cards
/// identical to Standard. A rider selecting one sent the server a category id
/// it does not recognise.
///
/// **This is safety-critical for Accessibility.** A wheelchair user selecting a
/// card that says "Wheelchair accessible" must get a wheelchair-accessible
/// vehicle — not a rejected id and a fallback to whatever the server does with
/// an unknown uuid. Booking an accessible vehicle is a promise you cannot
/// half-keep. We do not ship a button that makes that promise on a guess.
///
/// So the two unbookable classes are marked [bookable] `false`: they stay
/// VISIBLE (they are real products, and hiding them would misrepresent the
/// service) but are not selectable, and the selector discloses why. When
/// `GET /vehicle-categories` ships (gap #65 / SL-1), this const swaps for the
/// live read, every class becomes bookable with its real id, and the disclosure
/// disappears — a pure body-swap, no view change.
const List<RideTypeOption> kRideTypeOptions = [
  RideTypeOption(
    id: null,
    label: 'Standard',
    capacity: '4 seats • Upto 2 bags',
    icon: Icons.directions_car,
  ),
  RideTypeOption(
    id: null,
    label: 'XL',
    capacity: '6 seats • Upto 4 bags',
    icon: Icons.airport_shuttle,
    bookable: false,
  ),
  RideTypeOption(
    id: null,
    label: 'Accessibility',
    capacity: 'Wheelchair accessible',
    icon: Icons.accessible,
    bookable: false,
  ),
];

/// The ride-type selector (Figma "Book (Ride Now)" ride-type grid). A dumb
/// widget over [context.hoppin] tokens rendering the static [kRideTypeOptions]
/// as a row of [RideTypeCard]s. Single-selection: the parent owns the chosen
/// [selectedCategory] and receives the new id via [onSelect].
///
/// Presentation-only — it never fetches, never navigates, never touches the
/// data layer. The convergence lane (10-05) mounts it into `booking_view.dart`
/// and wires [onSelect] to `BookingInteractor.setCategory`.
class RideTypeSelector extends StatelessWidget {
  const RideTypeSelector({
    required this.selectedCategory,
    required this.onSelect,
    this.options,
    super.key,
  });

  /// The currently-chosen `vehicle_category_id` (null → Standard).
  final String? selectedCategory;

  /// Emits the chosen option's [RideTypeOption.id] on tap.
  final ValueChanged<String?> onSelect;

  /// The LIVE classes from `GET /vehicle-types`, when the read succeeded.
  ///
  /// This is the body-swap the static list below was always waiting for: every
  /// live row carries a real `vehicle_category_id`, so every class it contains
  /// is genuinely bookable — including Accessibility, which the static list has
  /// to mark unbookable because it cannot name the category to the server.
  ///
  /// Null (read failed / still loading) falls back to [kRideTypeOptions] with
  /// its disclosures intact. Never render a partial live list as if it were
  /// complete: a missing Accessibility row reads as "not offered", which is a
  /// different and worse lie than "cannot book it here yet".
  final List<RideTypeOption>? options;

  @override
  Widget build(BuildContext context) {
    final hoppin = context.hoppin;
    final gap = hoppin.spacing.md;

    // IntrinsicHeight equalises the three cards' heights (the "Wheelchair
    // accessible" line wraps differently) without forcing an infinite height
    // when hosted in a vertically-unbounded scroll view.
    // Live rows when we have them, the disclosed static list otherwise. Live
    // rows are all bookable (they carry real ids), so the SL-1 banner below
    // disappears on its own the moment the read succeeds — no separate flag.
    final effective = options ?? kRideTypeOptions;
    final unbookable =
        effective.where((o) => !o.bookable).map((o) => o.label).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // 🔴 THREE-ACROSS DOES NOT FIT ON A PHONE.
        //
        // A fixed 3-column Row gave each card ~72pt of text width at 360pt and
        // ~82pt at 390pt. RideTypeCard caps its name to one line and ellipsises
        // it (deliberately — the alternative it documents is a word fractured
        // mid-letter), so on EVERY phone width the widest real class name
        // rendered as "Accessibilit…" and its capacity line as "Wheelchair
        // access…". The class a wheelchair user is looking for was the one
        // name the layout could not print.
        //
        // So the column count is measured rather than assumed: three across
        // only where a card can actually hold the longest label, otherwise two,
        // which buys ~50% more width per card and lets the names render in
        // full. The cards are unchanged — this is purely how many share a row.
        LayoutBuilder(
          builder: (context, constraints) {
            final columns =
                constraints.maxWidth >= _threeUpMinWidth ? 3 : 2;
            return _grid(columns: columns, gap: gap, items: effective);
          },
        ),
        // The SL-1 disclosure (#65). The unbookable classes are visible above
        // but not selectable; this says why, in the rider's terms, instead of
        // letting them tap a card that would send the server a category id it
        // has never seen. Disappears the moment GET /vehicle-categories ships.
        if (unbookable.isNotEmpty) ...[
          SizedBox(height: hoppin.spacing.sm),
          HopBanner.notice(
            message: '${_readableList(unbookable)} '
                '${unbookable.length == 1 ? 'is' : 'are'} coming soon — '
                'you can book Standard today.',
          ),
        ],
      ],
    );
  }

  /// The width at which three cards can each still print the longest class
  /// name in full. Below it the selector drops to two columns.
  ///
  /// Derived, not eyeballed: the widest name ("Accessibility") needs ~100pt at
  /// `bodyMedium`, each card spends `spacing.md` on both inner edges, and two
  /// `spacing.md` gaps sit between three cards —
  /// `3 * (100 + 12 * 2) + 2 * 12 = 396`. A 390pt phone therefore falls to two
  /// columns, which is the correct answer: at three across it was clipping.
  static const double _threeUpMinWidth = 396;

  /// Lays the options out [columns]-across, wrapping into as many rows as it
  /// takes. Rows are [IntrinsicHeight] so cards in the same row match height
  /// (the capacity lines wrap differently) without demanding an infinite
  /// height from the scroll view hosting this.
  Widget _grid({
    required int columns,
    required double gap,
    required List<RideTypeOption> items,
  }) {
    final rows = <Widget>[];
    for (var start = 0; start < items.length; start += columns) {
      final slice = items.skip(start).take(columns).toList();
      rows.add(
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < columns; i++) ...[
                if (i > 0) SizedBox(width: gap),
                // A short final row keeps the cards at the SAME width as the
                // rows above rather than stretching the leftovers across the
                // full span — a 2-up grid whose last card is double-width
                // reads as a different, more important option.
                Expanded(
                  child: i < slice.length
                      ? _card(slice[i])
                      : const SizedBox.shrink(),
                ),
              ],
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) SizedBox(height: gap),
          rows[i],
        ],
      ],
    );
  }

  /// "XL and Accessibility" / "XL, Accessibility and Estate".
  static String _readableList(List<String> items) {
    if (items.length == 1) return items.first;
    return '${items.sublist(0, items.length - 1).join(', ')} '
        'and ${items.last}';
  }

  Widget _card(RideTypeOption option) {
    // Selection keys on the LABEL, not the id: every class carries a null id
    // today (we refuse to invent uuids), so `option.id == selectedCategory`
    // would mark all three cards selected at once.
    final isSelected = option.bookable &&
        (selectedCategory == null
            ? option.label == 'Standard'
            : option.id == selectedCategory);

    return Opacity(
      // Unbookable classes read as present-but-not-yet, never as equal peers.
      opacity: option.bookable ? 1 : 0.45,
      child: RideTypeCard(
        name: option.label,
        capacity: option.capacity,
        icon: option.icon,
        selected: isSelected,
        // Not bookable → not tappable. We will not accept a selection we
        // cannot honour (see [RideTypeOption.bookable]).
        onTap: option.bookable ? () => onSelect(option.id) : null,
      ),
    );
  }
}
