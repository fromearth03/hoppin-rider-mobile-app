import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hoppin_ui/hoppin_ui.dart';

import 'consent_notifier.dart' show noticeVersion;

/// The bundled terms of service — `/legal/terms`.
///
/// Same posture as the privacy notice: bundled, versioned, and it **resolves**.
/// The Help & Support frame promises a Terms link, and a link that 404s is a
/// dead end that lies.
///
/// ⚠️ **HUMAN-VERIFY ONLY: the legal adequacy of this text needs a solicitor.**
/// A green test proves the route resolves and the text is non-empty. It proves
/// nothing about whether these terms are enforceable or complete.
class TermsScreen extends StatelessWidget {
  /// Creates the bundled terms.
  const TermsScreen({super.key});

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
            // Same trap the privacy notice had, for the same reason: this screen
            // is off-shell and was reached with `context.go`, which REPLACES the
            // route — so `canPop()` was false, the stock AppBar drew no back
            // arrow, and the reader had no way out. Signup links here too, so
            // pop comes FIRST: it returns a half-registered user to the form
            // they left. `onBack` is never null — null hides the button.
            HopTopBar(
              title: 'Terms of Service',
              onBack: () =>
                  context.canPop() ? context.pop() : context.go('/book'),
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.all(hoppin.spacing.gutter),
                children: [
                  Text(
                    'Terms of Service',
                    style: type.h1.copyWith(color: colors.textHi),
                  ),
                  SizedBox(height: hoppin.spacing.xs),
                  Text(
                    'Version $noticeVersion',
                    style: type.metaSmall.copyWith(color: colors.textMid),
                  ),
                  SizedBox(height: hoppin.spacing.gutter),
                  const _Section(
                    heading: 'Using Hoppin',
                    body:
                        'Hoppin connects you with licensed private-hire drivers. '
                        'You must be 18 or over to hold an account, and the '
                        'details you give us must be your own and accurate.',
                  ),
                  const _Section(
                    heading: 'Booking a ride',
                    body: 'When you book, you are asking a driver to carry out '
                        'a journey and agreeing to pay the fare for it. Fares '
                        'shown before you book are estimates: the final fare '
                        'depends on the route actually taken, waiting time, and '
                        'any tolls or charges along the way.',
                  ),
                  const _Section(
                    heading: 'Cancelling',
                    body: 'You can cancel a ride. If a driver is already on '
                        'their way, a cancellation fee may apply, and we will '
                        'tell you before you confirm.',
                  ),
                  const _Section(
                    heading: 'Paying',
                    body: 'Payment is taken through Stripe using the method on '
                        'your account. If a payment fails, we may hold your '
                        'account until it is settled.',
                  ),
                  const _Section(
                    heading: 'Behaviour',
                    body: 'Drivers and riders are both expected to be civil and '
                        'safe. We may suspend an account after serious or '
                        'repeated reports.',
                  ),
                  const _Section(
                    heading: 'Your data',
                    body: 'How we handle your personal data is set out in the '
                        'Privacy Notice, which you can read from Help & Support.',
                  ),
                  const _Section(
                    heading: 'Complaints and disputes',
                    body: 'Open a support ticket from Profile. A person reads '
                        'it. If we cannot resolve it between us, nothing in '
                        'these terms takes away rights you have under consumer '
                        'law.',
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
