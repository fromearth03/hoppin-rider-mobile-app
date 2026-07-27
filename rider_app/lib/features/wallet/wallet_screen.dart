import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hoppin_shared/hoppin_shared.dart';
import 'package:hoppin_ui/hoppin_ui.dart';

import '../payments/stripe_sdk_gateway.dart';
import 'coming_soon_sheet.dart';

final paymentMethodsProvider = FutureProvider.autoDispose<List<PaymentMethod>>((
  ref,
) {
  return ref.watch(paymentsRepositoryProvider).paymentMethods();
});

final transactionsProvider = FutureProvider.autoDispose<List<Transaction>>((
  ref,
) {
  return ref.watch(paymentsRepositoryProvider).transactions();
});

/// Wallet: saved cards (list / set default / remove) + payment history.
///
/// Card management runs fully through `:8080` (proxying the Java payment
/// service). The one gated piece — entering NEW card details to confirm a
/// SetupIntent — needs the Stripe SDK behind [StripeSdkGateway]; while the
/// service is off, `createSetupIntent` returns `503 PAYMENTS_DISABLED` and
/// the Add-card tap shows the honest [ComingSoonSheet] (never a fake success,
/// never a crash — the add-card button stays visible per the no-holes DoD).
class WalletScreen extends ConsumerWidget {
  const WalletScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hoppin = context.hoppin;
    final colors = hoppin.colors;
    final spacing = hoppin.spacing;
    final cards = ref.watch(paymentMethodsProvider);
    final txns = ref.watch(transactionsProvider);

    return Scaffold(
      // NO AppBar. The shell renders a HopTopBar titled "Payments" over every
      // tab; this screen was drawing a SECOND header ("Wallet") beneath it. Two
      // stacked headers with two different names for the same tab.
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(paymentMethodsProvider);
          ref.invalidate(transactionsProvider);
        },
        child: ListView(
          // Inset by the chrome this list now scrolls beneath.
          padding: context.chromeScrollPadding(
            horizontal: spacing.gutter,
            top: spacing.gutter,
            bottom: spacing.gutter,
          ),
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    'Payment methods',
                    style: hoppin.type.section.copyWith(color: colors.textHi),
                  ),
                ),
                // Honest gated state: the button stays VISIBLE.
                TextButton.icon(
                  onPressed: () => _addCard(context, ref),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add card'),
                  style: TextButton.styleFrom(foregroundColor: colors.accent),
                ),
              ],
            ),
            SizedBox(height: spacing.sm),
            cards.when(
              loading: () => Padding(
                padding: EdgeInsets.all(spacing.lg),
                child: const Center(child: CircularProgressIndicator()),
              ),
              // PAYMENTS_DISABLED (503) lands here with a readable message.
              error: (e, _) =>
                  StatusBanner.error(message: friendlyErrorMessage(e)),
              data: (list) => list.isEmpty
                  ? const HopEmptyState(
                      compact: true,
                      headline: 'No saved cards yet',
                      supporting: 'Add a card to pay for your trips in a tap.',
                    )
                  : Column(
                      children: [for (final c in list) _CardTile(card: c)],
                    ),
            ),
            SizedBox(height: spacing.xl),
            Text(
              'Payment history',
              style: hoppin.type.section.copyWith(color: colors.textHi),
            ),
            SizedBox(height: spacing.xs),
            txns.when(
              loading: () => Padding(
                padding: EdgeInsets.all(spacing.lg),
                child: const Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) =>
                  StatusBanner.error(message: friendlyErrorMessage(e)),
              data: (list) => list.isEmpty
                  ? const HopEmptyState(
                      compact: true,
                      headline: 'No payments yet',
                      supporting: 'Payments for your trips will show up here.',
                    )
                  : Column(
                      children: [for (final t in list) _TransactionRow(txn: t)],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  /// Add card → real `createSetupIntent`. While the payment service is off it
  /// returns `503 PAYMENTS_DISABLED` → the designed [ComingSoonSheet] (the
  /// GATED rung). If it ever returns a `clientSecret`, hand it to the
  /// [StripeSdkGateway]; other failures surface [friendlyErrorMessage].
  Future<void> _addCard(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final intent = await ref
          .read(paymentsRepositoryProvider)
          .createSetupIntent();
      // Service is LIVE → confirm the clientSecret through the gateway seam.
      final result = await ref
          .read(stripeGatewayProvider)
          .confirmSetupIntent(intent.clientSecret);
      if (!context.mounted) return;
      switch (result.status) {
        case GatewayStatus.succeeded:
          ref.invalidate(paymentMethodsProvider);
        case GatewayStatus.unavailable:
          // The concrete confirm widget isn't wired yet → honest gated state.
          await showComingSoonSheet(context);
        case GatewayStatus.cancelled:
          break;
        case GatewayStatus.failed:
          messenger.showSnackBar(
            SnackBar(
              content: Text(result.message ?? 'Could not add the card.'),
            ),
          );
      }
    } on ApiException catch (e) {
      if (!context.mounted) return;
      if (e.code == 'PAYMENTS_DISABLED') {
        // The GATED rung — honest "coming soon", never a fake success/crash.
        await showComingSoonSheet(context);
      } else {
        messenger.showSnackBar(
          SnackBar(content: Text(friendlyErrorMessage(e))),
        );
      }
    } on Exception catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(friendlyErrorMessage(e))));
    }
  }
}

class _CardTile extends ConsumerWidget {
  const _CardTile({required this.card});

  final PaymentMethod card;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hoppin = context.hoppin;
    final colors = hoppin.colors;
    final label =
        '${(card.brand ?? 'Card').toUpperCase()} •••• ${card.last4 ?? '????'}';
    final expiry = (card.expMonth != null && card.expYear != null)
        ? '${card.expMonth.toString().padLeft(2, '0')}/${card.expYear! % 100}'
        : null;

    return Padding(
      padding: EdgeInsets.symmetric(vertical: hoppin.spacing.xs),
      child: HopCard(
        child: ListTile(
          contentPadding: EdgeInsets.symmetric(horizontal: hoppin.spacing.md),
          leading: Icon(Icons.credit_card, color: colors.accent),
          title: Text(
            label,
            style: hoppin.type.bodyMedium.copyWith(color: colors.textHi),
          ),
          subtitle: Text(
            [
              if (expiry != null) 'Expires $expiry',
              if (card.isDefault) 'Default',
            ].join(' · '),
            style: hoppin.type.metaSmall.copyWith(color: colors.textMid),
          ),
          trailing: PopupMenuButton<String>(
            onSelected: (action) => _onAction(context, ref, action),
            itemBuilder: (_) => [
              if (!card.isDefault)
                const PopupMenuItem(
                  value: 'default',
                  child: Text('Make default'),
                ),
              const PopupMenuItem(value: 'remove', child: Text('Remove')),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _onAction(
    BuildContext context,
    WidgetRef ref,
    String action,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final repo = ref.read(paymentsRepositoryProvider);
    try {
      switch (action) {
        case 'default':
          await repo.setDefault(card.paymentMethodId);
        case 'remove':
          await repo.removeCard(card.paymentMethodId);
      }
      ref.invalidate(paymentMethodsProvider);
    } on Exception catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(friendlyErrorMessage(e))));
    }
  }
}

/// One payment-history row — pence-accurate GBP via [formatPence].
class _TransactionRow extends StatelessWidget {
  const _TransactionRow({required this.txn});

  final Transaction txn;

  @override
  Widget build(BuildContext context) {
    final hoppin = context.hoppin;
    final colors = hoppin.colors;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(Icons.receipt_long_outlined, color: colors.textMid),
      title: Text(
        formatPence(txn.amountPence),
        style: hoppin.type.bodyMedium.copyWith(color: colors.textHi),
      ),
      subtitle: Text(
        [
          if (txn.status != null) txn.status!,
          if (txn.createdAt != null) formatShortDateTime(txn.createdAt!),
        ].join(' · '),
        style: hoppin.type.metaSmall.copyWith(color: colors.textMid),
      ),
    );
  }
}
