import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/result.dart';
import '../data/promotions_source.dart';
import '../domain/promotion_item.dart';

class PromotionalSnapshot {
  final List<PromotionItem> items;
  final bool isLoading;

  /// The server's own words when the load failed, null otherwise.
  final String? error;

  const PromotionalSnapshot({
    this.items = const [],
    this.isLoading = false,
    this.error,
  });

  PromotionalSnapshot copyWith({
    List<PromotionItem>? items,
    bool? isLoading,
    String? error,
    bool clearError = false,
  }) =>
      PromotionalSnapshot(
        items: items ?? this.items,
        isLoading: isLoading ?? this.isLoading,
        error: clearError ? null : (error ?? this.error),
      );
}

class PromotionalController extends StateNotifier<PromotionalSnapshot> {
  final PromotionsSource _source;

  PromotionalController(this._source) : super(const PromotionalSnapshot());

  Future<void> load() async {
    state = state.copyWith(isLoading: true, clearError: true);
    switch (await _source.list()) {
      case Ok(:final value):
        state = state.copyWith(items: value, isLoading: false);
      case Err(:final error):
        state = state.copyWith(
            items: const [], isLoading: false, error: error.message);
    }
  }
}

final promotionalControllerProvider =
    StateNotifierProvider<PromotionalController, PromotionalSnapshot>(
  (ref) => PromotionalController(ref.watch(promotionsSourceProvider)),
);
