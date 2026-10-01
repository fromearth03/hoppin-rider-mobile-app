import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/result.dart';

/// One banner ad from `GET /ads`. The server already filters to ads that are
/// active, inside their dates, for riders, and still within their budget.
class Ad {
  final String id;
  final String title;
  final String body;

  /// Public image URL, or empty for a text-only banner.
  final String imageUrl;

  /// What tapping does, by name: promotions, trips, payments, support,
  /// notifications. Empty means the banner is not tappable. A name this
  /// build does not know is treated as empty, never as a dead tap.
  final String action;

  const Ad({
    required this.id,
    required this.title,
    required this.body,
    required this.imageUrl,
    required this.action,
  });

  static Ad? tryParse(Map<String, dynamic> j) {
    final id = j['id'] as String? ?? '';
    final title = (j['title'] as String? ?? '').trim();
    if (id.isEmpty || title.isEmpty) return null;
    return Ad(
      id: id,
      title: title,
      body: (j['body'] as String? ?? '').trim(),
      imageUrl: (j['image_url'] as String? ?? '').trim(),
      action: (j['target_url'] as String? ?? '').trim(),
    );
  }
}

class AdsRepository {
  final ApiClient _api;
  const AdsRepository(this._api);

  Future<Result<List<Ad>>> active() async {
    final res = await _api.get<dynamic>('/ads');
    return switch (res) {
      Ok(:final value) => Ok(
        (value is List ? value : const [])
            .whereType<Map<String, dynamic>>()
            .map(Ad.tryParse)
            .whereType<Ad>()
            .toList(growable: false),
      ),
      Err(:final error) => Err(error),
    };
  }

  /// Engagement the admin panel reports as impressions, clicks, CTR and
  /// reach. Fire-and-forget: a lost event must never get in the rider's way.
  Future<void> impression(String id) async {
    await _api.post<dynamic>('/ads/$id/impression');
  }

  Future<void> click(String id) async {
    await _api.post<dynamic>('/ads/$id/click');
  }
}

final adsRepositoryProvider = Provider<AdsRepository>(
  (ref) => AdsRepository(ref.watch(apiClientProvider)),
);

/// The banners for the home screen. Re-fetched each time Home is shown, so
/// an ad switched off in the panel disappears on the next visit. A failure
/// shows nothing rather than an error: ads are never worth a red box.
final activeAdsProvider = FutureProvider.autoDispose<List<Ad>>((ref) async {
  final res = await ref.watch(adsRepositoryProvider).active();
  return switch (res) {
    Ok(:final value) => value,
    Err() => const [],
  };
});
