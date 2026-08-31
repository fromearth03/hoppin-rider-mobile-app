import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/error_codes.dart';
import '../../../core/result.dart';
import '../../../core/theme/colors.dart';
import '../data/payment_methods_repository.dart';
import 'widgets/payment_card_tile.dart';

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

  /// Starting a card add needs the Stripe SDK to collect the PAN against a
  /// setup intent — there is no Stripe key in this environment to wire it
  /// up. Building a raw TextField for the card number instead would put the
  /// app in PCI SAQ A-EP, which the design decisions explicitly forbid.
  ///
  /// So this calls the real endpoint (proving the wiring up to the SDK
  /// handoff works) and then tells the rider honestly that card entry isn't
  /// available yet, rather than faking a form that goes nowhere.
  Future<void> _startAddCard() async {
    final repo = ref.read(paymentMethodsRepositoryProvider);
    await repo.startAddCard();
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add a card'),
        content: const Text(
            'Card entry is not yet available in this build — it requires the '
            'Stripe SDK, which is not configured in this environment. Nothing '
            'was charged or saved.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
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
        title: const Text('Payment cards'),
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
                label: const Text('Add card'),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(56),
                  backgroundColor: AppColors.primary,
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

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        itemCount: _cards.length,
        itemBuilder: (context, index) {
          final card = _cards[index];
          final busy = _busyCardId == card.paymentMethodId;
          return PaymentCardTile(
            card: card,
            onMakeDefault:
                (card.isDefault || busy) ? null : () => _makeDefault(card),
            onRemove: busy ? () {} : () => _confirmRemove(card),
          );
        },
      ),
    );
  }
}
