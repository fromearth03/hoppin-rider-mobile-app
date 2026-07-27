import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hoppin_ui/hoppin_ui.dart';

import 'consent_notifier.dart' show noticeVersion;

export 'consent_notifier.dart' show noticeVersion;

/// The bundled, VERSIONED privacy notice — `/legal/privacy` (COMPLY-01).
///
/// 🔴 This screen is the highest-priority item in the release gate, and the
/// reason is structural: a **missing privacy notice is a bigger compliance hole
/// than the missing consent endpoint.** Gap 42 blocks marketing *sends*; a
/// missing notice undermines the lawful basis for **all** processing, rides
/// included. Arts. 13/14 transparency is what MAKES the contract basis lawful.
///
/// The notice is BUNDLED in-app rather than linked to a hosted URL. That choice
/// is deliberate and fully under our control:
///
///  * it means the app never renders a link that **404s** — a dead end that
///    lies is worse than one that admits it;
///  * it makes the *"what they were told"* half of Art. 7(1) demonstrable
///    consent **real and versionable** ([noticeVersion]) for the day gap 42
///    lands — the consent record will carry this version string;
///  * the Help & Support frame promises the link regardless.
///
/// ⚠️ **HUMAN-VERIFY ONLY: the legal ADEQUACY of this text needs a solicitor.**
/// A test can prove the link resolves and the text is non-empty. It cannot
/// prove the notice is *sufficient*. A green suite is NOT legal sign-off. The
/// content spec — including every question only the owner or a solicitor can
/// answer (retention, data residency, DPO, Art. 22) — is `DOCS/09`. A published
/// notice at a stable hosted URL, supplied by the owner, is the preferred end
/// state; this bundled notice is what ships until then, because nothing is not
/// an acceptable alternative.
class PrivacyNoticeScreen extends StatelessWidget {
  /// Creates the bundled privacy notice.
  const PrivacyNoticeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final hoppin = context.hoppin;
    final colors = hoppin.colors;
    final type = hoppin.type;

    return Scaffold(
      backgroundColor: colors.canvas,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // This screen was reached with `context.go`, which REPLACES the
            // route rather than pushing it — so `canPop()` was false, the stock
            // AppBar's back arrow (which only auto-draws when it is true) never
            // rendered, and the reader was trapped. It is off-shell, so there is
            // no bottom nav to escape by either. Worst here of anywhere: the
            // SIGNUP consent text links to this notice, so a new user could open
            // it and never get back to finish registering.
            //
            // Pop FIRST. When the caller pushed, popping returns them exactly
            // where they were; `/book` only catches a stackless entry. `onBack`
            // is never null, because null hides the button — which IS the bug.
            HopTopBar(
              title: 'Privacy Notice',
              onBack: () =>
                  context.canPop() ? context.pop() : context.go('/book'),
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.all(hoppin.spacing.gutter),
                children: [
                  Text(
                    'Privacy Notice',
                    style: type.h1.copyWith(color: colors.textHi),
                  ),
                  SizedBox(height: hoppin.spacing.xs),
                  Text(
                    'Version $noticeVersion',
                    style: type.metaSmall.copyWith(color: colors.textMid),
                  ),
                  SizedBox(height: hoppin.spacing.gutter),
                  const _Section(
                    heading: 'Who we are',
                    body: 'Hoppin operates this app and the private-hire '
                        'booking service behind it. We are the controller of '
                        'the personal data described below. If you want to '
                        'reach us about your data, open a support ticket from '
                        'Profile and we will route it to the right person.',
                  ),
                  const _Section(
                    heading: 'What we collect, and why',
                    body: 'Your name, email and phone number, so we can hold '
                        'your account and contact you about a ride.\n\n'
                        'Your date of birth and your confirmation that you are '
                        '18 or over, because you must be an adult to hold an '
                        'account.\n\n'
                        'Your location when you book and while you are on a '
                        'ride, so we can send a car to you, navigate, and work '
                        'out the fare. Without it we cannot dispatch a car.\n\n'
                        'Your ride history, receipts and fares, so we can bill '
                        'you and sort out any dispute.\n\n'
                        'Your payment method, held as a token by Stripe. Your '
                        'card details never touch our servers.\n\n'
                        'Messages you send the driver, and any support ticket '
                        'you open, so we can coordinate your pickup and answer '
                        'you.\n\n'
                        'Emergency contacts you add — their name, phone number '
                        'and relationship to you — so we can reach them if you '
                        'use SOS. These belong to someone else: please make '
                        'sure they are happy for you to give them to us.',
                  ),
                  const _Section(
                    heading: 'The legal basis for using it',
                    body: 'For everything needed to actually run your ride — '
                        'your account, your location, your route, your fare, '
                        'your payment — our lawful basis is contract: we '
                        'process it because it is necessary to provide the '
                        'service you asked us for. We do not ask you to consent '
                        'to it, because there is no ride without it, and '
                        'consent you cannot refuse would not be real '
                        'consent.\n\n'
                        'For marketing and product updates, our basis is your '
                        'consent, given by turning the toggle on. It is off '
                        'unless you turn it on, and you can turn it off again '
                        'at any time in Settings.\n\n'
                        'For safety and service quality — ratings, fraud checks '
                        '— our basis is our legitimate interests in running a '
                        'safe service. If you use SOS, we act on your vital '
                        'interests.',
                  ),
                  const _Section(
                    heading: 'Who we share it with',
                    body: 'The driver matched to your ride sees your name, your '
                        'pickup point and a way to contact you.\n\n'
                        'We use Supabase to hold your account, Stripe to take '
                        'payment, and a push-notification provider to send you '
                        'ride alerts. They process data on our instructions.\n\n'
                        'We do not sell your data to anyone.',
                  ),
                  const _Section(
                    heading: 'How long we keep it',
                    body: 'We keep ride and payment records for as long as '
                        'private hire licensing and tax rules require us to. '
                        'That means some records survive a deletion request — '
                        'we will tell you which ones, and we will not pretend '
                        'to have erased something we are legally required to '
                        'keep.',
                  ),
                  const _Section(
                    heading: 'Your rights',
                    body: 'You can ask for a copy of your data, ask us to '
                        'correct it, ask us to delete it, ask for it in a '
                        'portable format, or object to how we use it. Open a '
                        'support ticket from Profile and a person will action '
                        'it — the request goes to a real queue with a real '
                        'human at the end of it, not into a void.\n\n'
                        'Where we rely on your consent (marketing), you can '
                        'withdraw it at any time, and withdrawing is as easy as '
                        'giving.',
                  ),
                  const _Section(
                    heading: 'Complaining',
                    body: "If you're unhappy with how we handle your data, tell "
                        'us first and we will try to put it right. You also '
                        'have the right to complain to the Information '
                        'Commissioner, the UK data protection regulator, at '
                        'ico.org.uk.',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One heading + body block of a bundled legal document.
class _Section extends StatelessWidget {
  const _Section({required this.heading, required this.body});

  final String heading;
  final String body;

  @override
  Widget build(BuildContext context) {
    final hoppin = context.hoppin;
    final colors = hoppin.colors;
    final type = hoppin.type;

    return Padding(
      padding: EdgeInsets.only(bottom: hoppin.spacing.gutter),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            heading,
            style: type.titleSmall.copyWith(color: colors.textHi),
          ),
          SizedBox(height: hoppin.spacing.sm),
          Text(
            body,
            style: type.body.copyWith(color: colors.textMid, height: 1.5),
          ),
        ],
      ),
    );
  }
}
