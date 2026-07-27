import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The version of the privacy notice currently bundled in the app.
///
/// This exists so the *"what they were told"* half of demonstrable consent is
/// REAL and versionable on the day `POST /me/consents` (gap 42) ships — the
/// consent record will carry this string alongside the choice and the
/// timestamp. Bump it whenever the notice text changes materially.
const String noticeVersion = 'v1-2026-07';

/// The rider's marketing / analytics consent choice, SESSION-SCOPED.
///
/// Default `false` — PECR requires opt-**IN**, and a pre-ticked box is
/// unlawful. Silence and inactivity are not consent; a positive act is.
///
/// NOT persisted. Deliberately. A record that lives only on the rider's own
/// device is invisible to us, dies on cache-clear, does not follow them to a
/// new device, and — for consent — is NOT LEGAL EVIDENCE. UK GDPR Art. 7(1)
/// requires consent to be DEMONSTRABLE: who consented, when (timestamped), how,
/// and what they were told (the notice version in force). We can supply WHO
/// (the JWT subject) and WHAT (see [noticeVersion]); we have nowhere to write
/// WHEN and HOW. Caching the choice to disk would convert that known gap into a
/// false comfort.
///
/// The honest consequence, said out loud in `ConsentRecordUnavailable`: an
/// opted-IN rider's choice evaporates when the app closes, so the system
/// behaves identically for opted-in and opted-out riders — **we send no
/// marketing at all.** That behaviour is lawful. Under-collecting is always
/// safe; PECR punishes sending *without* consent, never the reverse.
///
/// This is the body-swap seat for gap 42: when `POST /me/consents` ships, [set]
/// calls it and the rung disappears. Zero view change.
///
/// Ride processing does NOT depend on this. Rides rest on the CONTRACT basis
/// (Art. 6(1)(b)). Gap 42 blocks marketing SENDS; it does not block rides.
final marketingConsentProvider =
    NotifierProvider<MarketingConsent, bool>(MarketingConsent.new);

/// Session-scoped holder for the marketing consent choice.
class MarketingConsent extends Notifier<bool> {
  @override
  bool build() => false;

  /// Records the rider's positive act (or their withdrawal).
  ///
  /// Withdrawal must be as easy as giving (Art. 7(3)) — which is why the
  /// Settings "Promotional Offers" row drives this same setter.
  ///
  /// Today this changes session state and NOTHING ELSE: no HTTP call (there is
  /// no `POST /me/consents` — gap 42) and no disk write (see above). When the
  /// endpoint lands, the write goes here.
  void set({required bool granted}) => state = granted;

  /// Convenience for a switch's `onChanged`.
  void toggle() => state = !state;
}
