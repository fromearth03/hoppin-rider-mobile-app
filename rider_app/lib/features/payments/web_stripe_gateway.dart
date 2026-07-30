import 'package:flutter/material.dart';
import 'package:flutter_stripe/flutter_stripe.dart';

import 'stripe_sdk_gateway.dart';

/// The REAL card-entry gateway (replaces [NoopStripeGateway] when a Stripe
/// publishable key is configured). Presents a Stripe [CardField], collects a
/// card, and confirms the SetupIntent — on web this runs js.confirmCardSetup
/// under the hood — so the card is attached to the rider's Stripe customer for
/// reuse. Context-free by design: it shows its own sheet via the root navigator
/// key, matching the [StripeSdkGateway.confirmSetupIntent] seam.
class WebStripeGateway implements StripeSdkGateway {
  const WebStripeGateway(this.navigatorKey);

  final GlobalKey<NavigatorState> navigatorKey;

  @override
  Future<GatewayResult> confirmSetupIntent(String clientSecret) async {
    final context = navigatorKey.currentContext;
    if (context == null) {
      return const GatewayResult.failed('Could not open the card form.');
    }
    final result = await showModalBottomSheet<GatewayResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (_) => _CardEntrySheet(clientSecret: clientSecret),
    );
    // A null result means the rider dismissed the sheet.
    return result ?? const GatewayResult.cancelled();
  }
}

class _CardEntrySheet extends StatefulWidget {
  const _CardEntrySheet({required this.clientSecret});

  final String clientSecret;

  @override
  State<_CardEntrySheet> createState() => _CardEntrySheetState();
}

class _CardEntrySheetState extends State<_CardEntrySheet> {
  bool _complete = false;
  bool _busy = false;
  String? _error;

  Future<void> _save() async {
    if (_busy || !_complete) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // confirmCardSetup (web) rejects on a card error, surfacing as a
      // StripeException here — so a non-throwing return means the card attached.
      final si = await Stripe.instance.confirmSetupIntent(
        paymentIntentClientSecret: widget.clientSecret,
        params: const PaymentMethodParams.card(
          paymentMethodData: PaymentMethodData(),
        ),
      );
      if (!mounted) return;
      Navigator.of(context).pop(GatewayResult.succeeded(si.id));
    } on StripeException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.error.localizedMessage ??
            e.error.message ??
            'Your card could not be saved.';
      });
    } catch (e) {
      // On web a decline is thrown as a stripe_js error, not a StripeException —
      // pull its message ('Your card was declined.', etc.) instead of a generic
      // line so testers see the real reason.
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _stripeMessage(e) ??
            'Your card could not be saved. Check the details or try another card.';
      });
    }
  }

  /// Best-effort message from any Stripe error object (StripeError / stripe_js)
  /// that exposes a `message` field, without importing the web-only package.
  String? _stripeMessage(Object e) {
    try {
      final m = (e as dynamic).message;
      if (m is String && m.trim().isNotEmpty) return m;
    } catch (_) {}
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Add a card', style: theme.textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            'Your card is stored securely by Stripe — we never see the number.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 20),
          CardField(
            enablePostalCode: false,
            onCardChanged: (card) =>
                setState(() => _complete = card?.complete ?? false),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
          ],
          const SizedBox(height: 20),
          FilledButton(
            onPressed: (_busy || !_complete) ? null : _save,
            child: _busy
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Save card'),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
