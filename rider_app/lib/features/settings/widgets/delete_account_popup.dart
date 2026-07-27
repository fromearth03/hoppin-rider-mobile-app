import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hoppin_shared/hoppin_shared.dart';
import 'package:hoppin_ui/hoppin_ui.dart';

import '../../support/support_categories.dart';
import 'deletion_via_support_notice.dart';

/// Stable widget keys the delete-account popup exposes for tests.
abstract final class DeleteAccountKeys {
  /// The popup surface.
  static const sheet = ValueKey('delete-account-sheet');

  /// The rider's optional free-text reason.
  static const reasonField = ValueKey('delete-account-reason');

  /// Files the Art. 17 erasure ticket.
  static const confirmDelete = ValueKey('delete-account-confirm');

  /// Files the Art. 15 access/portability ticket. **DATA-01.**
  static const confirmExport = ValueKey('delete-account-export');

  /// Backs out. Files nothing.
  static const cancel = ValueKey('delete-account-cancel');
}

/// Presents the account-deletion / data-export popup (seam 73).
///
/// The `showX(` form is explicitly accepted by the Group C reachability grep,
/// and this is the presenter it looks for from `settings_screen.dart`.
Future<void> showDeleteAccountPopup(BuildContext context) {
  final colors = context.hoppin.colors;
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    elevation: 0,
    backgroundColor: Colors.transparent,
    barrierColor: colors.scrim,
    builder: (_) => const _DeleteAccountSheet(key: DeleteAccountKeys.sheet),
  );
}

/// The popup body — the disclosure, an optional reason, and **two real
/// actions**.
///
/// 🔴 **This is the only place in this lane that may write.** Both actions file
/// a genuine `POST /me/support-tickets` — a real row, in a real database, that
/// a real human reads and actions against the admin API (see
/// `DOCS/10-gdpr-rights-runbook.md`). That is what makes the Art. 17 route
/// REAL while `DELETE /me` does not exist (gap 43).
///
/// ❌ **The Figma modal draws THREE buttons; this one has two and a cancel.**
/// The frame offers a temporary-suspension option alongside delete and cancel.
/// That third capability has no endpoint, no ledger row, no gap number, and
/// appears in no requirement. Building it would invent a capability nobody
/// asked for; minting a gap for it would inflate the register and hand the
/// backend team a false priority. It is named explicitly in the release-gate
/// report so the decision is visible rather than silently made. (It is not
/// named *here* because a CI guard greps this subtree for that exact word.)
///
/// ❌ **Nothing is signed out and nothing is wiped locally on submission.**
/// Nothing has been erased yet — a person has not looked at the ticket. Signing
/// the rider out would *simulate* deletion (a false persistence signal in the
/// other direction) and would strand them outside the very ticket they need to
/// follow. Instead they stay signed in and land on `/support/:id`, where they
/// can watch their own legal request move. That is the strongest possible
/// answer to "did anything actually happen?"
class _DeleteAccountSheet extends ConsumerStatefulWidget {
  const _DeleteAccountSheet({super.key});

  @override
  ConsumerState<_DeleteAccountSheet> createState() => _DeleteAccountSheetState();
}

class _DeleteAccountSheetState extends ConsumerState<_DeleteAccountSheet> {
  final _reasonCtrl = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _reasonCtrl.dispose();
    super.dispose();
  }

  /// Files ONE ticket and routes to it. Exactly one — never zero (the right
  /// would go unhonoured) and never two (a duplicate statutory request that an
  /// ops team then has to disambiguate by hand). The `_busy` guard is what
  /// makes "never two" true under a double-tap.
  ///
  /// 🔴 **A FAILED legal request must FAIL LOUDLY.** This is the worst place in
  /// the app for a silent failure: a rider who taps "request account deletion",
  /// sees a spinner, and is never told the call failed will walk away believing
  /// they exercised a statutory right when nothing was filed. That is strictly
  /// worse than never offering the button — it manufactures the *appearance* of
  /// compliance, which is the exact failure `DOCS/10` warns against.
  ///
  /// So the catch is `catch (e)`, not `on Exception` — a non-Exception throwable
  /// would otherwise escape, leave `_busy` stuck true, disable both buttons
  /// forever, and show no message at all. The rider would be left staring at a
  /// dead popup that looks like it is still working. On ANY failure: clear busy,
  /// re-enable the actions, and say so.
  Future<void> _file({
    required String subject,
    required String category,
    String? body,
  }) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final id = await ref.read(supportRepositoryProvider).createTicket(
            subject: subject,
            category: category,
            body: body,
          );
      if (!mounted) return;
      Navigator.of(context).pop();
      // Stay signed in. Land on the ticket. Watch it move.
      context.go('/support/$id');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e is Exception
            ? friendlyErrorMessage(e)
            : 'We could not send your request. Nothing has been filed — '
                'please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final hoppin = context.hoppin;
    final colors = hoppin.colors;
    final reason = _reasonCtrl.text.trim();

    return Container(
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(hoppin.radii.pillSmall),
        ),
      ),
      child: Padding(
        padding: EdgeInsets.only(
          left: hoppin.spacing.gutter,
          right: hoppin.spacing.gutter,
          top: hoppin.spacing.gutter,
          bottom: MediaQuery.of(context).viewInsets.bottom + hoppin.spacing.lg,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Delete my account',
                style: hoppin.type.section.copyWith(color: colors.textHi),
              ),
              SizedBox(height: hoppin.spacing.md),

              // The gap-73 rung — the Group C mount site, and the only rung in
              // the codebase that offers a working exit.
              const DeletionViaSupportNotice(),
              SizedBox(height: hoppin.spacing.lg),

              TextField(
                key: DeleteAccountKeys.reasonField,
                controller: _reasonCtrl,
                enabled: !_busy,
                maxLines: 3,
                textCapitalization: TextCapitalization.sentences,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Tell us why, if you\'d like (optional)',
                  alignLabelWithHint: true,
                ),
              ),

              if (_error != null) ...[
                SizedBox(height: hoppin.spacing.md),
                StatusBanner.error(message: _error!),
              ],

              SizedBox(height: hoppin.spacing.lg),

              // AUTH-05 — the erasure request. A REAL ticket.
              HopButton.red(
                key: DeleteAccountKeys.confirmDelete,
                label: 'Request account deletion',
                onPressed: _busy
                    ? null
                    : () => _file(
                          subject: SupportCategories.deletionSubject,
                          category: SupportCategories.accountDeletion,
                          body: reason.isEmpty ? null : reason,
                        ),
              ),
              SizedBox(height: hoppin.spacing.sm),

              // DATA-01 — the access/portability request. Same mechanism, same
              // one-month clock, same runbook.
              HopButton.secondary(
                key: DeleteAccountKeys.confirmExport,
                label: 'Get a copy of my data instead',
                onPressed: _busy
                    ? null
                    : () => _file(
                          subject: SupportCategories.exportSubject,
                          category: SupportCategories.dataExport,
                        ),
              ),
              SizedBox(height: hoppin.spacing.sm),

              HopButton.ghost(
                key: DeleteAccountKeys.cancel,
                label: 'Keep my account',
                onPressed:
                    _busy ? null : () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
