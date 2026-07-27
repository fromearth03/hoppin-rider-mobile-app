import 'package:hoppin_shared/hoppin_shared.dart';

/// THE PHASE'S SIGNATURE INSTRUMENT — the recording fake that proves the write
/// path by its **EXCLUSIVITY**, not merely by its presence.
///
/// This is Phase 11's *"the app NEVER dials"* idiom generalised one level up:
/// from **zero dials** to **zero writes**. Phase 11 injected a recording
/// `UrlLauncher`, drove every control on the inert call screen, and asserted the
/// launch log was empty — turning "we never dial" from a code-review promise
/// into a machine assertion.
///
/// [SupportRepository] is the **only** thing in Phase 12 that may legitimately
/// write anything. So the write path is proved from BOTH directions:
///
/// * **Personal Information · Settings · Promotions · the consent block** —
///   drive every control on every one of them, and [createdTickets] must be
///   **EMPTY**. Nothing on those screens may open a ticket, because nothing on
///   those screens has anything to say to a human.
/// * **The deletion / export popup** — the inverse. **Exactly ONE** ticket per
///   action, under the right category. Never zero (the statutory right would go
///   unhonoured, silently) and never two (a duplicate Art. 17 request an ops
///   team then has to disambiguate by hand, against a one-month clock).
///
/// A test that only proved the popup writes would also pass on an app where
/// *everything* writes. Exclusivity is the assertion that actually holds.
///
/// (Promoted at convergence from the two byte-local copies Lanes A and B each
/// vendored while running in parallel — one harness, one behaviour, one place to
/// fix it.)
class RecordingSupportRepository implements SupportRepository {
  /// Every `createTicket` call, in order, with the full argument set.
  ///
  /// A `Map` rather than a record so a test can assert on any field — including
  /// the ones a lane did not think to care about, which is where the surprises
  /// live.
  final List<Map<String, Object?>> createdTickets = <Map<String, Object?>>[];

  /// The id handed back for each ticket. The deletion popup routes the rider to
  /// `/support/:id` with it, so the value must look like the real thing.
  String nextTicketId = 'c4000000-0000-4000-8000-000000000042';

  /// When set, `createTicket` throws this instead of recording.
  ///
  /// Deliberately `Object?`, not `Exception?`: a `StateError` is not an
  /// `Exception`, and a popup that catches only `Exception` strands the rider on
  /// a dead spinner having filed **nothing** — while believing they exercised a
  /// GDPR right. That is the manufactured appearance of compliance, and it is
  /// the failure this field exists to let a test reproduce.
  Object? failure;

  @override
  Future<String> createTicket({
    required String subject,
    String? category,
    String? typeCode,
    String? priority,
    String? rideId,
    String? body,
    List<String>? tags,
  }) async {
    if (failure != null) throw failure!;
    createdTickets.add(<String, Object?>{
      'subject': subject,
      'category': category,
      'type_code': typeCode,
      'priority': priority,
      'ride_id': rideId,
      'body': body,
      'tags': tags,
    });
    return nextTicketId;
  }

  @override
  Future<List<SupportTicket>> myTickets() async => const <SupportTicket>[];

  @override
  Future<TicketThread> thread(String ticketId) =>
      throw UnimplementedError('the recording fake never reads a thread');

  @override
  Future<void> reply({required String ticketId, required String body}) =>
      throw UnimplementedError('the recording fake never replies');
}
