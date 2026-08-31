import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/promotions_source.dart';
import '../domain/promotion_item.dart';

class PromotionalSnapshot {
  final List<PromotionItem> items;
  final bool isLoading;

  const PromotionalSnapshot({this.items = const [], this.isLoading = false});

  PromotionalSnapshot copyWith({
    List<PromotionItem>? items,
    bool? isLoading,
  }) =>
      PromotionalSnapshot(
        items: items ?? this.items,
        isLoading: isLoading ?? this.isLoading,
      );
}

class PromotionalController extends StateNotifier<PromotionalSnapshot> {
  final PromotionsSource _source;

  PromotionalController(this._source) : super(const PromotionalSnapshot());

  Future<void> load() async {
    state = state.copyWith(isLoading: true);
    final items = await _source.list();
    state = state.copyWith(items: items, isLoading: false);
  }
}

final promotionalControllerProvider =
    StateNotifierProvider<PromotionalController, PromotionalSnapshot>(
  (ref) => PromotionalController(ref.watch(promotionsSourceProvider)),
);
