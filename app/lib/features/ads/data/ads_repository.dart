import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/device/device_id.dart' show secureStorageProvider;
import '../../../core/result.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// One banner ad from `GET /ads`. The server already filters to ads that are
/// active, inside their dates, for riders, and still within their budget.
class Ad {
  final String id;
  final String title;
  final String body;

  /// Public image URL, or empty for a text-only banner.
  final String imageUrl;

  /// What tapping does: a key from the server's tap-action catalog
  /// (app_tap_actions). Empty means the banner is not tappable. A key this
  /// build does not know is treated as empty, never as a dead tap.
  final String action;

  /// The https link, for the `url` action. Empty otherwise.
  final String tapUrl;

  const Ad({
    required this.id,
    required this.title,
    required this.body,
    required this.imageUrl,
    required this.action,
    this.tapUrl = '',
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
      tapUrl: (j['tap_url'] as String? ?? '').trim(),
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

/// Ads the rider closed on Home. Kept on the phone: the banner stays hidden
/// until an ad they have not dismissed is published.
class DismissedAds extends StateNotifier<Set<String>> {
  DismissedAds(this._storage) : super(const {}) {
    _load();
  }

  final FlutterSecureStorage _storage;
  static const _key = 'hoppin_dismissed_ads';

  Future<void> _load() async {
    try {
      final raw = await _storage.read(key: _key);
      if (raw != null && raw.isNotEmpty) state = raw.split(',').toSet();
    } catch (_) {
      // A broken store only means the banner shows again.
    }
  }

  Future<void> dismiss(Iterable<String> ids) async {
    state = {...state, ...ids};
    try {
      await _storage.write(key: _key, value: state.join(','));
    } catch (_) {}
  }
}

final dismissedAdsProvider = StateNotifierProvider<DismissedAds, Set<String>>(
  (ref) => DismissedAds(ref.watch(secureStorageProvider)),
);
