import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/promotion_item.dart';

/// Where the Promotional screen gets its rows.
///
/// There is no promotions endpoint in this API - searched `app/lib` and the
/// backend contracts recorded in `docs/SCREEN-DECISIONS.md`, neither has one.
/// [NoPromotionsSource] is the only implementation today and always returns
/// an empty list, so the screen renders its honest empty state rather than
/// inventing offers that look live.
///
/// When a real endpoint exists, add a `RemotePromotionsSource` here and swap
/// the provider override below - the screen and controller do not change.
abstract class PromotionsSource {
  Future<List<PromotionItem>> list();
}

/// The only implementation until a backend exists. Deliberately named so it
/// cannot be mistaken for a real data source.
class NoPromotionsSource implements PromotionsSource {
  const NoPromotionsSource();

  @override
  Future<List<PromotionItem>> list() async => const [];
}

final promotionsSourceProvider =
    Provider<PromotionsSource>((ref) => const NoPromotionsSource());
