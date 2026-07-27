import 'package:flutter/material.dart';
import 'package:hoppin_ui/hoppin_ui.dart';

/// The designed unavailable-state for ACCOUNT DELETION and DATA EXPORT
/// (gap 73 → backend gap 43). **AUTH-05 and DATA-01.**
///
/// 🔴 **This rung is unlike every other one in the codebase: it does not merely
/// disclose, it OFFERS THE WORKING ROUTE.** Its state is `MISSING_BE` because
/// there is no `DELETE /me` and no `GET /me/data-export` — but the action the
/// rider takes is **fully bound**. It files a real support ticket, into a real
/// database, that a real human reads and actions against the admin API
/// (`DOCS/10-gdpr-rights-runbook.md`). It is the only seam in this project
/// where the rider's need is genuinely met.
///
/// A future reader WILL be tempted to make the button inert "for consistency"
/// with the other rungs. **Do not.** Art. 17 requires the route to exist, and
/// an inert button here is exactly what the owner rejected.
///
/// ## 🔴 The copy is legally constrained, and it must not promise erasure
///
/// The admin endpoint behind this ticket is `DELETE /users/:id`, and it returns
/// **`status: "anonymised"` — not `"deleted"`**. It anonymises and bans; it
/// does not erase. Private-hire licensing and HMRC impose **minimum retention**
/// on ride and financial records, and full erasure would breach those
/// obligations. Anonymisation is the *correct* implementation, not a
/// shortcoming: it satisfies Art. 17 for the personal data while preserving the
/// legally-mandated records in a form no longer tied to a person.
///
/// So this widget must never say "your data will be deleted". That is a lie the
/// backend does not perform. It says, plainly: **personal details are removed,
/// the account is closed, and ride and payment records are kept in anonymised
/// form because the law requires it.**
///
/// The four beats it must carry:
/// 1. **The right** — this is a legal right, not a favour.
/// 2. **How it actually happens** — by hand, by a person, within one month.
///    One month is the statutory *maximum* (Art. 12(3)). It promises no faster
///    and it never promises instant.
/// 3. **What actually happens to the data** — anonymised, not erased.
/// 4. **The honest delays** — active trips, open disputes, legal retention. The
///    right to erasure is **not absolute**; this is the law, not a fudge.
///
/// It is CONSTRUCTED by `delete_account_popup.dart`, presented from
/// `settings_screen.dart` via `showDeleteAccountPopup(`. That mount site is
/// what the Group C reachability check looks for.
class DeletionViaSupportNotice extends StatelessWidget {
  /// Creates the gap-73 data-rights disclosure.
  const DeletionViaSupportNotice({super.key});

  @override
  Widget build(BuildContext context) {
    final hoppin = context.hoppin;
    final colors = hoppin.colors;

    final body = hoppin.type.meta.copyWith(color: colors.textMid);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // 1. The right.
        Text(
          'You can ask us to close your account and remove your personal '
          'details. That is your right under UK data-protection law.',
          style: body,
        ),
        SizedBox(height: hoppin.spacing.md),

        // 2. How it actually happens. No euphemism, no automation theatre.
        Text(
          'We do this by hand today. Your request opens a support ticket and a '
          'person acts on it. We will come back to you within one month.',
          style: body,
        ),
        SizedBox(height: hoppin.spacing.md),

        // 3. 🔴 What actually happens to the data. The backend ANONYMISES.
        //    This paragraph is the one that must never be softened into a
        //    promise of erasure.
        Text(
          'What that means: your personal details are removed and your account '
          'is closed. Your ride and payment records are kept in anonymised '
          'form — with nothing in them that identifies you — because taxi '
          'licensing and tax law require us to keep them for a set period.',
          style: body,
        ),
        SizedBox(height: hoppin.spacing.md),

        // 4. The honest delays. This is the law, not a fudge — the right to
        //    erasure is not absolute.
        Text(
          'It can take longer if you have a trip in progress, an open dispute '
          'with us, or where the law requires us to hold on to something for '
          'a while.',
          style: body,
        ),
      ],
    );
  }
}
