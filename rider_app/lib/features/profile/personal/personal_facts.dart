import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hoppin_shared/hoppin_shared.dart';

/// The WHOLE list of things the app can honestly say it knows about a rider.
///
/// Not "the fields the Figma drew". Not "the fields a profile normally has".
/// These four, and nothing else, because there is no `GET /me/profile` (gap 70,
/// SL-5) and the session is the only source there is.
///
/// What is deliberately absent, and why:
/// - **city** — does not exist anywhere. Not in the JWT, not in the session,
///   not in DOCS/04, not in any endpoint. The city the Figma frame prints is a
///   fabrication, and this class deliberately gives it nowhere to live.
/// - **avatar** — there is no avatar endpoint and nowhere to upload to.
/// - **date of birth** — captured at signup into an in-memory holder that dies
///   on reload (gap 55). Surfacing it here would claim it was stored.
///
/// Every field below is nullable because every one of them genuinely can be
/// unknown, and the screen omits the row rather than filling it with a
/// placeholder. "—" and "Not set" both read as *you haven't filled this in*
/// when the truth is *we can't tell you*.
class PersonalFacts {
  /// Creates the honest fact-set for one rider session.
  const PersonalFacts({
    this.fullName,
    this.email,
    this.phone,
    this.memberSince,
  });

  /// `user_metadata.full_name`, written at signup. Null for accounts created
  /// without one — the screen then falls back to [email], as the Profile hub
  /// already does.
  final String? fullName;

  /// The account's own identifier. The one field a signed-in session always
  /// carries.
  final String? email;

  /// The session's phone number. **Only OTP-signup riders have one** — the
  /// email/password path never sets it. Null is the honest, common case, and
  /// the screen OMITS the row entirely when it is null.
  final String? phone;

  /// The account creation timestamp, as the session's raw ISO-8601 string.
  /// A real fact, so it is honest to show it.
  final String? memberSince;
}

/// Derives [PersonalFacts] from the live session.
///
/// ⚠️ **Handover to Lane F (12-06).** This provider reads `phone` and
/// `createdAt` off the Supabase `User` hanging from `AuthService.currentSession`
/// because `AuthService` does not expose them as getters and this lane may not
/// edit `hoppin_shared` during a parallel milestone. When Lane F lands the two
/// one-line getters (`AuthService.phone`, `AuthService.createdAt`), the two
/// lines below become `auth.phone` / `auth.createdAt` and nothing else changes.
///
/// Tests override this provider directly rather than fabricating a Supabase
/// `Session`.
final personalFactsProvider = Provider<PersonalFacts>((ref) {
  final auth = ref.watch(authServiceProvider);
  final user = auth.currentSession?.user;
  return PersonalFacts(
    fullName: auth.fullName,
    email: auth.email,
    phone: user?.phone,
    memberSince: user?.createdAt,
  );
});
