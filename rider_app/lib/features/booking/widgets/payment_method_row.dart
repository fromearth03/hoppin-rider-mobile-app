import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hoppin_shared/hoppin_shared.dart';
import 'package:hoppin_ui/hoppin_ui.dart';

/// The rider's real saved cards, read on the confirm surface.
///
/// This is the SAME live read the Wallet performs — `GET /me/payment-methods`
/// through the shared [paymentsRepositoryProvider] — so Booking and Wallet can
/// never disagree about what is on file. Overriding [paymentsRepositoryProvider]
/// (as every test and the demo composition already do) steers both.
///
/// It deliberately does NOT re-use the Wallet screen's own
/// `paymentMethodsProvider`: that one resolves the repository chain
/// (`payments → api client → auth`) synchronously in its body, so mounting it
/// from inside a widget build — which is exactly what this row does, on a
/// screen the Wallet never hosts — makes Riverpod schedule a refresh mid-build
/// and the framework throws "setState() called during build". The zero-delay
/// hop below pushes the whole chain-mount off the build phase, so the read is
/// safe from ANY mount point. The endpoint, the repository and therefore the
/// answer are identical.
final confirmPaymentMethodsProvider =
    FutureProvider.autoDispose<List<PaymentMethod>>((ref) async {
  await Future<void>.delayed(Duration.zero);
  return ref.read(paymentsRepositoryProvider).paymentMethods();
});

/// The payment-method row on the confirm surface — the LAST thing a rider
/// reads before committing money.
///
/// It reads the REAL saved-card list ([confirmPaymentMethodsProvider], the same
/// `GET /me/payment-methods` the Wallet reads) and renders only what that answer
/// actually supports:
///
///   • a saved default card  → its real brand + last4 (never a made-up one);
///   • a saved card list with no default → the first card, plainly labelled as
///     the one that will be used, with no "Default" pill it has not earned;
///   • an empty list         → "No payment method saved" — the rider genuinely
///     has no card;
///   • `503 PAYMENTS_DISABLED` → "Card payments aren't switched on yet" — the
///     payment service is off, so no card CAN be on file;
///   • any other error       → "We can't check your payment method" — we do not
///     know, and saying "you have no cards" here would be asserting emptiness
///     out of ignorance, which is a lie;
///   • loading               → "Checking your payment method…" — asserts nothing.
///
/// This row previously rendered a hardcoded brand, a hardcoded masked number
/// and an unearned "Default" pill — a card no rider ever had. It read no
/// provider and took no argument: every rider on the money path was shown a
/// card that does not exist. The real data was one provider away.
class PaymentMethodRow extends ConsumerWidget {
  /// Creates the confirm-surface payment-method row.
  const PaymentMethodRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final methods = ref.watch(confirmPaymentMethodsProvider);

    // Branch on the FACTS the AsyncValue carries, not on its runtime type.
    // Riverpod 3 surfaces a failed read as an AsyncLoading that carries the
    // error (`hasError == true` while `isLoading == true`), so `.when()`
    // dispatches such a read into its `loading` arm and the error arm never
    // fires. On the money path that would leave the rider on a "checking…"
    // rung forever instead of being told we cannot read their card. Error is
    // therefore checked FIRST, before value, before loading.
    if (methods.hasError) return _errorRung(methods.error!);

    if (methods.hasValue) {
      final cards = methods.requireValue;
      if (cards.isEmpty) {
        return const _PaymentRung(
          headline: 'No payment method saved',
          supporting:
              "There's no card on your account, so we can't tell you what "
              'this ride will be charged to. Add a card in Wallet before '
              'you book.',
        );
      }
      // The card the server marks default is the one that gets charged. If
      // the server marks none, we show the card we have but do NOT pin a
      // "Default" pill on it — that pill is the server's claim, not ours.
      PaymentMethod? defaultCard;
      for (final c in cards) {
        if (c.isDefault) {
          defaultCard = c;
          break;
        }
      }
      return _SelectedCardRow(
        card: defaultCard ?? cards.first,
        isDefault: defaultCard != null,
      );
    }

    return const _PaymentRung(
      headline: 'Checking your payment method…',
      supporting:
          "We're reading the card on your account. The card that will be "
          'charged appears here in a moment.',
    );
  }

  /// Distinguishes "the payment service is OFF" (a known, nameable state) from
  /// "we could not read your cards" (ignorance). Neither claims the rider has
  /// no card, and neither invents one.
  Widget _errorRung(Object error) {
    if (error is ApiException && error.code == 'PAYMENTS_DISABLED') {
      return const _PaymentRung(
        headline: "Card payments aren't switched on yet",
        supporting:
            'Our secure payment service is still being switched on, so no card '
            'can be charged for this ride yet. Payment will be arranged '
            'directly for now.',
      );
    }
    return const _PaymentRung(
      headline: "We can't check your payment method",
      supporting:
          "We couldn't reach your saved cards just now, so we can't tell you "
          'which card this ride would be charged to. Open Wallet to check '
          'before you book.',
    );
  }
}

/// The honest degrade rung: a designed, visible [HopEmptyState] inside the row
/// slot. It never names a brand, never shows digits, and never wears a
/// "Default" pill. It only says what is actually known.
class _PaymentRung extends StatelessWidget {
  const _PaymentRung({required this.headline, required this.supporting});

  final String headline;
  final String supporting;

  @override
  Widget build(BuildContext context) {
    return HopCard(
      child: HopEmptyState(
        compact: true,
        headline: headline,
        supporting: supporting,
      ),
    );
  }
}

/// The real card row — brand and last4 come from the server's [PaymentMethod],
/// never from a literal. The "Default" pill renders only when the server itself
/// flagged the card as the default.
class _SelectedCardRow extends StatelessWidget {
  const _SelectedCardRow({required this.card, required this.isDefault});

  final PaymentMethod card;
  final bool isDefault;

  @override
  Widget build(BuildContext context) {
    final hoppin = context.hoppin;
    final colors = hoppin.colors;
    final radius = BorderRadius.circular(hoppin.radii.control);

    // A card with no brand/last4 on it is still a real card — we show what the
    // server gave us and stay silent about what it did not.
    final brand = card.brand?.toUpperCase();
    final last4 = card.last4;

    return Container(
      decoration: BoxDecoration(
        color: colors.selectedTint,
        borderRadius: radius,
        border: Border.all(color: colors.selectedBorder),
      ),
      padding: EdgeInsets.symmetric(
        horizontal: hoppin.spacing.lg,
        vertical: hoppin.spacing.md,
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: colors.accent,
              borderRadius: BorderRadius.circular(hoppin.radii.control),
            ),
            child: Icon(Icons.credit_card, color: colors.onAccent, size: 22),
          ),
          SizedBox(width: hoppin.spacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  brand ?? 'Saved card',
                  style: hoppin.type.bodyMedium.copyWith(color: colors.textHi),
                ),
                Text(
                  last4 != null
                      ? '•••• •••• •••• $last4'
                      : 'Card details not shared by your bank',
                  style: hoppin.type.metaSmall.copyWith(color: colors.textMid),
                ),
              ],
            ),
          ),
          if (isDefault)
            const StatusPill(label: 'Default', tone: PillTone.success),
        ],
      ),
    );
  }
}
