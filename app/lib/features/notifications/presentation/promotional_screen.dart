import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/promotional_controller.dart';
import 'widgets/promotion_card.dart';

/// Promotional offers list, backed by `GET /promotions` (rider-facing).
///
/// Every card comes from the server, including its Active / Availed / Expire
/// pill, which the server owns as `state`. With no offers the honest empty
/// state renders rather than invented cards.
class PromotionalScreen extends ConsumerStatefulWidget {
  const PromotionalScreen({super.key});

  @override
  ConsumerState<PromotionalScreen> createState() => _PromotionalScreenState();
}

class _PromotionalScreenState extends ConsumerState<PromotionalScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(
        () => ref.read(promotionalControllerProvider.notifier).load());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = ref.watch(promotionalControllerProvider);

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: const Text('Promotional'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: state.isLoading
          ? const Center(child: CircularProgressIndicator())
          : state.items.isEmpty
              ? _EmptyState(theme: theme, error: state.error)
              : RefreshIndicator(
                  onRefresh:
                      ref.read(promotionalControllerProvider.notifier).load,
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                    itemCount: state.items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 16),
                    itemBuilder: (context, index) =>
                        PromotionCard(item: state.items[index]),
                  ),
                ),
    );
  }
}

/// No cards to show. Either there are genuinely no offers, or the load failed
/// - in which case the server's own sentence renders, rather than telling the
/// rider to "check back later" for offers that may well exist.
class _EmptyState extends StatelessWidget {
  final ThemeData theme;
  final String? error;

  const _EmptyState({required this.theme, this.error});

  @override
  Widget build(BuildContext context) {
    final failed = error != null;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(failed ? Icons.cloud_off : Icons.local_offer_outlined,
                size: 56,
                color: Theme.of(context).textTheme.bodyMedium?.color),
            const SizedBox(height: 16),
            Text(
              failed
                  ? 'Promotions could not be loaded'
                  : 'No promotions right now',
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              failed
                  ? error!
                  : "Check back later for offers and discounts on your rides.",
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
