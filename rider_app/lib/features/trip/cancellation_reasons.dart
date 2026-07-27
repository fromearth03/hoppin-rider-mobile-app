import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hoppin_shared/hoppin_shared.dart';

/// A reason the rider can pick when cancelling.
class CancellationReason {
  const CancellationReason({required this.id, required this.label});

  final String id;
  final String label;
}

/// The rider's cancellation reasons — `GET /cancellation-reasons` (BOUND).
///
/// 🔴 **This was the "cancellation is broken on live" bug, and it is fixed by
/// reading the REAL reasons instead of fabricated placeholders.** The old body
/// returned four made-up uuids that were not in the database, so
/// `PATCH /rides/:id/cancel` rejected every one with `VALIDATION_FAILED` and no
/// rider could ever cancel. The endpoint existed the whole time as
/// `GET /cancellation-reasons` (the mobile note was hunting the wrong path,
/// `/me/cancellation-reasons`); its rows carry the real seeded uuids that the
/// cancel endpoint validates against.
///
/// Filtered to `actor_type == 'rider'` (the endpoint serves both actors), and
/// returns an empty list on failure — the cancel sheet then shows its honest
/// "reasons unavailable" state rather than a confident button over a request
/// that would 400. An empty result is a genuine fact (no rider reasons seeded),
/// never a fabricated stand-in.
final cancellationReasonsProvider =
    FutureProvider.autoDispose<List<CancellationReason>>((ref) async {
  final rows = await ref.watch(ridesRepositoryProvider).cancellationReasons();
  return rows
      .where((r) => r.actorType == 'rider')
      .map((r) => CancellationReason(id: r.id, label: r.reasonText))
      .toList();
});
