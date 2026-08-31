import 'package:flutter/material.dart';

/// Recent Payments — `GET /api/v1/me/transactions`.
///
/// That endpoint is documented in `docs/PAYMENTS-STRIPE.md` and
/// `docs/SCREEN-DECISIONS.md` ("Recent Payments list"), but no repository
/// method anywhere in this app calls it — verified by searching
/// `app/lib/features/payments/data` and the rest of `app/lib` for
/// `transactions`: nothing exists. Building a client against an endpoint
/// nobody has verified end to end, or filling this screen with sample rows
/// to match the Figma frame, would both tell the rider something false.
///
/// So this screen renders the real chrome and an honest, clearly-labelled
/// empty state instead — the same choice already made for
/// `RideHistoryScreen`. [_placeholderTransactions] is the seam: swap it for
/// a real `TransactionsRepository.list()` call once the client exists, and
/// nothing else on this screen needs to change.
class TransactionsScreen extends StatelessWidget {
  const TransactionsScreen({super.key});

  /// Explicit, honestly-named placeholder for `GET /me/transactions`. Always
  /// empty — there is no client wired to the endpoint yet, so there is
  /// nothing real to show. Never fabricate rows here.
  static List<Never> _placeholderTransactions() => const [];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final transactions = _placeholderTransactions();

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: const Text('Recent Payments'),
        // AppBar's automatic back button needs a route to pop to, which is
        // absent in isolation (e.g. under test). Wired explicitly instead,
        // matching the rest of this app's screens.
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: SafeArea(
        child: transactions.isEmpty
            ? _EmptyState(theme: theme)
            : const SizedBox.shrink(),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final ThemeData theme;
  const _EmptyState({required this.theme});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.receipt_long_outlined,
              size: 56,
              color: theme.textTheme.bodyMedium?.color,
            ),
            const SizedBox(height: 16),
            Text(
              'No recent payments',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Your charged rides will appear here in a future update.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}
