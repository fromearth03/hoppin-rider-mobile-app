import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/promotional_controller.dart';
import 'widgets/promotion_card.dart';

/// Promotional offers list.
///
/// There is no promotions endpoint anywhere in this API - see
/// [PromotionsSource]. The list is driven entirely by whatever source is
/// wired to [promotionsSourceProvider], which defaults to
/// [NoPromotionsSource] and therefore renders empty until a real backend
/// exists. Nothing on this screen is invented.
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
              ? _EmptyState(theme: theme)
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                  itemCount: state.items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 16),
                  itemBuilder: (context, index) =>
                      PromotionCard(item: state.items[index]),
                ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final ThemeData theme;
  const _EmptyState({required this.theme});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.local_offer_outlined,
                size: 56,
                color: Theme.of(context).textTheme.bodyMedium?.color),
            const SizedBox(height: 16),
            Text(
              'No promotions right now',
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              "Check back later for offers and discounts on your rides.",
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
