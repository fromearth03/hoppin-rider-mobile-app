import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/api/error_codes.dart';
import '../../../../core/result.dart';
import '../../../../core/theme/colors.dart';
import '../../data/payment_methods_repository.dart';

/// The rider's saved cards, for the sheet. Autodispose so a card added or
/// re-defaulted elsewhere is re-fetched on next open.
final _sheetCardsProvider =
    FutureProvider.autoDispose<List<SavedCard>>((ref) async {
  final result = await ref.watch(paymentMethodsRepositoryProvider).list();
  return switch (result) {
    Ok(:final value) => value,
    Err(:final error) => throw error,
  };
});

/// `Select Payment Method.png`: bottom sheet listing the rider's real saved
/// cards with a tick on the default. Tapping another card makes it the
/// default — the API charges the default card, there is no per-ride
/// selection, so "selecting" and "making default" are honestly the same
/// action (`POST /me/payment-methods/:pmId/default`).
///
/// PayPal and Wallet are drawn on the frame; neither exists behind this app
/// (cards only — rider-app-backend-truths), so both rows render visibly
/// "Soon"-disabled rather than being hidden or faked.
Future<void> showPaymentMethodSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _PaymentMethodSheet(),
  );
}

class _PaymentMethodSheet extends ConsumerStatefulWidget {
  const _PaymentMethodSheet();

  @override
  ConsumerState<_PaymentMethodSheet> createState() =>
      _PaymentMethodSheetState();
}

class _PaymentMethodSheetState extends ConsumerState<_PaymentMethodSheet> {
  bool _busy = false;

  Future<void> _choose(SavedCard card) async {
    if (card.isDefault || _busy) return;
    setState(() => _busy = true);

    final result =
        await ref.read(paymentMethodsRepositoryProvider).setDefault(
              card.paymentMethodId,
            );
    if (!mounted) return;
    setState(() => _busy = false);

    switch (result) {
      case Ok():
        ref.invalidate(_sheetCardsProvider);
        Navigator.of(context).pop();
      case Err(:final error):
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(RiderErrorCopy.messageFor(error))),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final cards = ref.watch(_sheetCardsProvider);

    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkBackground : AppColors.lightBackground,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: MediaQuery.of(context).padding.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Text('Select Payment Method',
                style: theme.textTheme.titleMedium),
          ),
          const SizedBox(height: 16),
          cards.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (error, _) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(
                'Could not load your cards.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
            ),
            data: (list) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (list.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      'No saved cards yet. Add one under Payments.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                for (final card in list)
                  _MethodRow(
                    icon: Icons.credit_card,
                    title: card.displayLabel,
                    subtitle: '···· ···· ···· ${card.last4}',
                    selected: card.isDefault,
                    enabled: !_busy,
                    onTap: () => _choose(card),
                  ),
              ],
            ),
          ),
          // Drawn on the frame; no backend behind either — cards only.
          const _MethodRow(
            icon: Icons.paypal,
            title: 'PayPal',
            subtitle: null,
            selected: false,
            enabled: false,
            comingSoon: true,
          ),
          const _MethodRow(
            icon: Icons.account_balance_wallet_outlined,
            title: 'Wallet',
            subtitle: null,
            selected: false,
            enabled: false,
            comingSoon: true,
          ),
        ],
      ),
    );
  }
}

class _MethodRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final bool selected;
  final bool enabled;
  final bool comingSoon;
  final VoidCallback? onTap;

  const _MethodRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.enabled,
    this.comingSoon = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final muted = theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.5);
    final live = enabled && !comingSoon;
    final titleColor =
        live ? theme.textTheme.bodyLarge?.color : muted;

    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color:
                      isDark ? AppColors.darkBorder : AppColors.lightBorder),
            ),
            child: Icon(icon, size: 20, color: titleColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: theme.textTheme.bodyLarge
                        ?.copyWith(color: titleColor)),
                if (subtitle != null)
                  Text(subtitle!,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(fontSize: 12, color: muted)),
              ],
            ),
          ),
          if (comingSoon)
            Text('Soon',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(fontSize: 11, color: muted))
          else if (selected)
            const Icon(Icons.check_circle,
                color: AppColors.positive, size: 20),
        ],
      ),
    );

    if (!live || onTap == null) return row;
    return InkWell(onTap: onTap, child: row);
  }
}
