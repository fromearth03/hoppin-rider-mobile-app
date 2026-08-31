import 'package:flutter/material.dart';
import 'package:flutter_stripe/flutter_stripe.dart';

import '../../../../core/theme/colors.dart';

/// The Stripe-owned card form: number, expiry and CVC in one row, plus
/// "Set as default" and Save/Cancel.
///
/// This is the ONLY place a card is collected. It never builds its own
/// Card Number / CVV / Expiry field — [CardField] is Stripe's SDK widget, so
/// the PAN is read by Stripe's own platform view and never enters this
/// app's process memory or widget tree. That is what keeps the PCI audit at
/// SAQ A instead of SAQ A-EP; see docs/PAYMENTS-STRIPE.md.
///
/// Returns `true` via [Navigator.pop] once the card has been saved
/// successfully so the caller knows to refresh the list. Returns `false`/null
/// on cancel.
class AddCardSheet extends StatefulWidget {
  final String clientSecret;

  /// Called after the SDK confirms the setup intent, with whether the rider
  /// asked to make this their default card. Returns an error message on
  /// failure, or null on success.
  final Future<String?> Function({required bool makeDefault}) onConfirm;

  const AddCardSheet({
    super.key,
    required this.clientSecret,
    required this.onConfirm,
  });

  @override
  State<AddCardSheet> createState() => _AddCardSheetState();

  /// Shows the sheet and returns whether a card was saved.
  static Future<bool> show(
    BuildContext context, {
    required String clientSecret,
    required Future<String?> Function({required bool makeDefault}) onConfirm,
  }) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => AddCardSheet(
        clientSecret: clientSecret,
        onConfirm: onConfirm,
      ),
    );
    return saved ?? false;
  }
}

class _AddCardSheetState extends State<AddCardSheet> {
  CardFieldInputDetails? _cardDetails;
  bool _makeDefault = false;
  bool _submitting = false;
  String? _errorMessage;

  bool get _canSubmit =>
      !_submitting && (_cardDetails?.complete ?? false);

  Future<void> _submit() async {
    setState(() {
      _submitting = true;
      _errorMessage = null;
    });

    String? error;
    try {
      error = await widget.onConfirm(makeDefault: _makeDefault);
    } on StripeException catch (e) {
      // A declined or failed card is a real, expected outcome - shown
      // honestly with Stripe's own message, never swallowed into a fake
      // success.
      error = e.error.localizedMessage ?? e.error.message ?? 'That card was declined.';
    } catch (_) {
      error = 'Something went wrong saving that card. Try again.';
    }

    if (!mounted) return;

    if (error != null) {
      setState(() {
        _submitting = false;
        _errorMessage = error;
      });
      return;
    }

    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final border = isDark ? AppColors.darkBorder : AppColors.lightBorder;

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Add a card', style: theme.textTheme.headlineLarge?.copyWith(fontSize: 22)),
          const SizedBox(height: 4),
          Text(
            'Card details are sent directly to Stripe and never pass through Hoppin.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 20),
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: border),
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: CardField(
              enablePostalCode: false,
              style: theme.textTheme.bodyLarge,
              decoration: const InputDecoration(border: InputBorder.none),
              onCardChanged: (details) {
                setState(() => _cardDetails = details);
              },
            ),
          ),
          const SizedBox(height: 12),
          CheckboxListTile(
            value: _makeDefault,
            onChanged: _submitting
                ? null
                : (value) => setState(() => _makeDefault = value ?? false),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
            title: const Text('Set as default'),
          ),
          Text(
            'By adding a card you agree to be charged for rides booked with it, '
            'per our Terms of Service.',
            style: theme.textTheme.bodyMedium,
          ),
          if (_errorMessage != null) ...[
            const SizedBox(height: 12),
            Text(
              _errorMessage!,
              style: const TextStyle(color: AppColors.negative),
            ),
          ],
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _submitting
                      ? null
                      : () => Navigator.of(context).pop(false),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: _canSubmit ? _submit : null,
                  child: _submitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Save'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
