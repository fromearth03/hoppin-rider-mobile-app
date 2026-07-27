import 'package:flutter/material.dart';
import 'package:hoppin_ui/hoppin_ui.dart';

/// The designed unavailable-state for the CONSENT RECORD (gap 74, ledger row 34
/// — backend gap 42: there is no `POST`/`GET /me/consents`).
///
/// UK GDPR Art. 7(1) requires consent to be **demonstrable**: who consented,
/// when (timestamped), how, and what they were told. We have WHO (the JWT
/// subject) and WHAT (the bundled, versioned privacy notice). We have nowhere
/// to write WHEN and HOW.
///
/// 🔴 Both sentences below are LOAD-BEARING and must not be softened.
///
/// The consequence is real and we say it plainly: with no server record and no
/// local write, an opted-**IN** rider's choice **evaporates**. The system
/// therefore behaves identically for opted-in and opted-out riders — **we send
/// no marketing at all.** That behaviour is lawful: under-collecting is always
/// safe, and PECR punishes sending *without* consent, never the reverse.
///
/// The alternative reading — *"the toggle is decorative"* — is exactly the
/// accusation this disclosure pre-empts. A silent inert control earns that
/// accusation. A control that tells you what it can and cannot do does not.
///
/// It is CONSTRUCTED at BOTH real mount sites: beneath the signup consent
/// toggle (the moment of collection) and in the Settings privacy group (where a
/// rider goes to CHANGE it). Group C reachability needs one. The honesty needs
/// both — a choice you can give but never revisit is not a choice, and
/// withdrawal must be as easy as giving (Art. 7(3)).
///
/// Body-swaps to the live record with zero view changes when the endpoint ships.
class ConsentRecordUnavailable extends StatelessWidget {
  /// Creates the gap-74 consent-record disclosure.
  const ConsentRecordUnavailable({super.key});

  @override
  Widget build(BuildContext context) {
    return const HopCard(
      child: HopEmptyState(
        compact: true,
        headline: "We can't store this choice on our servers yet, so we won't "
            'send you any marketing at all until we can.',
        supporting: "Your choice here isn't saved when you close the app. None "
            'of this affects your rides — booking a ride never depended on it.',
      ),
    );
  }
}
