import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_stripe/flutter_stripe.dart' as stripe_sdk;

import 'package:intl/intl.dart';

import '../../../core/api/error_codes.dart';
import '../../../core/config.dart';
import '../../../core/result.dart';
import '../../../core/theme/colors.dart';
import '../../history/data/trip_history_repository.dart';
import '../data/payment_methods_repository.dart';
import 'widgets/add_card_sheet.dart';
import 'widgets/payment_card_tile.dart';

/// The frame's "Recent Payments" list — real charged rides off `GET /rides`,
/// newest first. There is no dedicated transactions endpoint; a completed
/// ride with a total IS the payment record.
final _recentPaymentsProvider =
    FutureProvider.autoDispose<List<TripHistoryItem>>((ref) async {
  final result = await ref
      .watch(tripHistoryRepositoryProvider)
      .myTrips(status: 'completed', limit: 10);
  return switch (result) {
    Ok(:final value) => [
        for (final t in value.trips)
          if (t.totalPence != null) t,
      ],
    // Decoration on this screen; an error renders as an empty section, never
    // as a failure that hides the rider's cards.
    Err() => const <TripHistoryItem>[],
  };
});

/// Card management, not a per-ride payment picker.
///
/// The design pack calls this "Select Payment Method" and draws it as a
/// booking step with PayPal and Cash alongside a Visa card. None of that is
/// real: the ride service has no per-ride payment selection — booking always
/// charges the rider's default card — and neither PayPal nor cash exists
/// anywhere in the payment service. This screen is titled and built as what
/// it actually is: where a rider adds, removes and re-defaults their saved
/// Stripe cards.
class PaymentMethodsScreen extends ConsumerStatefulWidget {
  const PaymentMethodsScreen({super.key});

  @override
  ConsumerState<PaymentMethodsScreen> createState() =>
      _PaymentMethodsScreenState();
}

class _PaymentMethodsScreenState extends ConsumerState<PaymentMethodsScreen> {
  bool _loading = true;
  List<SavedCard> _cards = const [];
  String? _errorMessage;

  // Per-row busy state so one row's action can't be double-tapped while its
  // request is in flight, without freezing the rest of the list.
  String? _busyCardId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    final repo = ref.read(paymentMethodsRepositoryProvider);
    final result = await repo.list();
    if (!mounted) return;

    setState(() {
      _loading = false;
      switch (result) {
        case Ok(:final value):
          _cards = value;
        case Err(:final error):
          _errorMessage = RiderErrorCopy.messageFor(error);
      }
    });
  }

  Future<void> _makeDefault(SavedCard card) async {
    setState(() => _busyCardId = card.paymentMethodId);

    final repo = ref.read(paymentMethodsRepositoryProvider);
    final result = await repo.setDefault(card.paymentMethodId);
    if (!mounted) return;

    if (result case Err(:final error)) {
      setState(() {
        _busyCardId = null;
        _errorMessage = RiderErrorCopy.messageFor(error);
      });
      return;
    }

    setState(() => _busyCardId = null);
    await _load();
  }

  Future<void> _confirmRemove(SavedCard card) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove this card?'),
        content: Text(
            '${card.displayLabel} will be removed from your account. This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.negative),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    await _removeCard(card);
  }

  Future<void> _removeCard(SavedCard card) async {
    setState(() => _busyCardId = card.paymentMethodId);

    final repo = ref.read(paymentMethodsRepositoryProvider);
    final result = await repo.remove(card.paymentMethodId);
    if (!mounted) return;

    if (result case Err(:final error)) {
      setState(() {
        _busyCardId = null;
        _errorMessage = RiderErrorCopy.messageFor(error);
      });
      return;
    }

    setState(() => _busyCardId = null);
    await _load();
  }

  /// Whether the Stripe SDK can actually collect a card here.
  ///
  /// `CardField` has no web platform implementation in the version this app
  /// depends on, so on web the raw PAN has nowhere PCI-safe to go — showing
  /// it would either crash or, worse, fall back to a field this app
  /// controls. Mobile still needs a real key: without one, `confirmSetupIntent`
  /// would fail opaquely deep inside the SDK instead of with a clear reason
  /// shown up front.
  bool get _canAddCard => !kIsWeb && AppConfig.stripePublishableKey.isNotEmpty;

  /// `POST /me/payment-methods/setup-intent` → the Stripe `CardField` sheet
  /// collects the card directly against the returned `clientSecret` → the
  /// SDK confirms the setup intent → the list is refreshed. The PAN is
  /// never read, logged or held by this app at any point — see
  /// docs/PAYMENTS-STRIPE.md.
  Future<void> _startAddCard() async {
    if (!_canAddCard) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Add a card'),
          content: const Text(kIsWeb
              ? 'Card entry needs the mobile app — the Stripe card field is '
                  'not available in this web build. Nothing was charged or saved.'
              : 'Card entry is unavailable in this build — the Stripe key is '
                  'not configured. Nothing was charged or saved.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    final repo = ref.read(paymentMethodsRepositoryProvider);
    final result = await repo.startAddCard();
    if (!mounted) return;

    final SetupIntent setupIntent;
    switch (result) {
      case Ok(:final value):
        setupIntent = value;
      case Err(:final error):
        setState(() => _errorMessage = RiderErrorCopy.messageFor(error));
        return;
    }

    final saved = await AddCardSheet.show(
      context,
      clientSecret: setupIntent.clientSecret,
      onConfirm: ({required makeDefault}) =>
          _confirmSetupIntent(setupIntent.clientSecret, makeDefault: makeDefault),
    );

    if (!saved || !mounted) return;
    await _load();
  }

  /// Hands the card off to Stripe and confirms the setup intent. Returns an
  /// error message on failure (a decline, a network error, a provider
  /// failure) or null on success — never a fake success for a card that was
  /// not actually saved.
  Future<String?> _confirmSetupIntent(
    String clientSecret, {
    required bool makeDefault,
  }) async {
    final confirmed = await stripe_sdk.Stripe.instance.confirmSetupIntent(
      paymentIntentClientSecret: clientSecret,
      params: const stripe_sdk.PaymentMethodParams.card(
        paymentMethodData: stripe_sdk.PaymentMethodData(),
      ),
    );

    // Stripe's status is a plain string ("Succeeded", "RequiresAction", …)
    // rather than a typed enum in this SDK version - "Succeeded" is the only
    // outcome that actually saved a usable card.
    if (confirmed.status != 'Succeeded') {
      return 'That card could not be saved. Try again.';
    }

    if (makeDefault && confirmed.paymentMethodId.isNotEmpty) {
      final repo = ref.read(paymentMethodsRepositoryProvider);
      final defaultResult = await repo.setDefault(confirmed.paymentMethodId);
      if (defaultResult case Err(:final error)) {
        // The card itself saved fine; only the "set as default" step
        // failed. Say so rather than implying the whole add failed.
        return 'Card saved, but could not be set as default: '
            '${RiderErrorCopy.messageFor(error)}';
      }
    }

    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back),
        ),
        title: const Text('Payment Methods'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _buildBody(theme)),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: _startAddCard,
                icon: const Icon(Icons.add),
                label: const Text('Add Payment Methods'),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(56),
                  backgroundColor: AppColors.navy,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(28)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline,
                size: 40, color: AppColors.negative),
            const SizedBox(height: 12),
            Text(_errorMessage!,
                textAlign: TextAlign.center, style: theme.textTheme.bodyLarge),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );
    }

    if (_cards.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.credit_card_off,
                size: 40, color: theme.textTheme.bodyMedium?.color),
            const SizedBox(height: 12),
            Text('No payment cards saved yet',
                style: theme.textTheme.bodyLarge, textAlign: TextAlign.center),
            const SizedBox(height: 4),
            Text('Add a card to book a ride.',
                style: theme.textTheme.bodyMedium, textAlign: TextAlign.center),
          ],
        ),
      );
    }

    final recent = ref.watch(_recentPaymentsProvider).valueOrNull ??
        const <TripHistoryItem>[];

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(_recentPaymentsProvider);
        await _load();
      },
      child: ListView(
        children: [
          for (final card in _cards)
            Builder(builder: (context) {
              final busy = _busyCardId == card.paymentMethodId;
              return PaymentCardTile(
                card: card,
                onMakeDefault: (card.isDefault || busy)
                    ? null
                    : () => _makeDefault(card),
                onRemove: busy ? () {} : () => _confirmRemove(card),
              );
            }),
          // `Payment Methods.png`'s Recent Payments block, from real charged
          // rides.
          if (recent.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text('Recent Payments',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontSize: 15, color: AppColors.navy)),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                children: [
                  for (var i = 0; i < recent.length; i++) ...[
                    if (i > 0)
                      Divider(
                          height: 1,
                          color: theme.dividerColor.withValues(alpha: 0.5)),
                    _RecentPaymentRow(trip: recent[i]),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _RecentPaymentRow extends StatelessWidget {
  final TripHistoryItem trip;
  const _RecentPaymentRow({required this.trip});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final when = (trip.dropoffTime ?? trip.pickupTime ?? trip.requestedAt)
        .toLocal();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  trip.dropoffLabel ?? trip.pickupLabel ?? 'Ride',
                  style: theme.textTheme.bodyLarge
                      ?.copyWith(fontSize: 14, color: AppColors.navy),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(DateFormat('d MMM, yyyy').format(when),
                    style:
                        theme.textTheme.bodyMedium?.copyWith(fontSize: 11.5)),
              ],
            ),
          ),
          Text(
            // A charge leaving the rider's card, as the frame signs it.
            '-${trip.totalPence!.format(currency: trip.currency)}',
            style: theme.textTheme.titleMedium
                ?.copyWith(fontSize: 13.5, color: AppColors.negative),
          ),
        ],
      ),
    );
  }
}
