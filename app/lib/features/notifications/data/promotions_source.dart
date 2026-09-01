import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/result.dart';
import '../domain/promotion_item.dart';
import 'promotions_repository.dart';

/// What the Promotional screen loads.
///
/// A thin seam over [PromotionsRepository] so the screen and its goldens can
/// be driven from a fake without a network.
abstract class PromotionsSource {
  Future<Result<List<PromotionItem>>> list();
}

/// The live implementation: `GET /promotions` (rider-facing offers).
class RemotePromotionsSource implements PromotionsSource {
  final PromotionsRepository _repo;
  const RemotePromotionsSource(this._repo);

  @override
  Future<Result<List<PromotionItem>>> list() => _repo.list();
}

final promotionsSourceProvider = Provider<PromotionsSource>(
    (ref) => RemotePromotionsSource(ref.watch(promotionsRepositoryProvider)));
