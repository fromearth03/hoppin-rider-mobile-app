import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hoppin_shared/hoppin_shared.dart';
import 'package:hoppin_ui/hoppin_ui.dart';

/// Post-trip rating (RIDER-05), converted to a riblet-lite: the submit
/// logic lives in [RatingInteractor] (zero widget imports in its logic —
/// score/busy/error state, `POST /rides/:id/rating` via the repository
/// interface) and the sheet is a dumb view over it. Skippable by design:
/// dismissing costs nothing, and the trip flow never re-prompts.

/// Immutable state for one rating flow.
@immutable
class RatingState {
  const RatingState({this.score = 0, this.busy = false, this.error});

  /// 1-5 once picked; 0 = nothing selected yet.
  final int score;

  /// True while the submit call is in flight.
  final bool busy;

  /// Display-ready validation/submit failure.
  final String? error;

  RatingState copyWith({int? score, bool? busy, String? Function()? error}) =>
      RatingState(
        score: score ?? this.score,
        busy: busy ?? this.busy,
        error: error == null ? this.error : error(),
      );
}

/// The rating brain: validates, guards double-submits, calls the rides
/// surface. Family-keyed by ride id, auto-disposed with the sheet.
class RatingInteractor extends Notifier<RatingState> {
  RatingInteractor(this.rideId);

  final String rideId;

  @override
  RatingState build() => const RatingState();

  void setScore(int score) {
    if (state.busy) return;
    state = state.copyWith(score: score, error: () => null);
  }

  /// Submits the picked score; true on success. Failures surface as
  /// display-ready copy on [RatingState.error].
  Future<bool> submit({String? comments}) async {
    if (state.busy) return false;
    if (state.score < 1) {
      state = state.copyWith(error: () => 'Pick a star rating first.');
      return false;
    }
    state = state.copyWith(busy: true, error: () => null);
    final trimmed = comments?.trim();
    try {
      await ref.read(ridesRepositoryProvider).rate(
            rideId: rideId,
            score: state.score,
            comments: (trimmed == null || trimmed.isEmpty) ? null : trimmed,
          );
      if (!ref.mounted) return true;
      state = state.copyWith(busy: false);
      return true;
    } on Exception catch (e) {
      if (!ref.mounted) return false;
      state = state.copyWith(busy: false, error: () => friendlyErrorMessage(e));
      return false;
    }
  }
}

/// Builder for the rating riblet-lite.
final ratingInteractorProvider =
    NotifierProvider.autoDispose.family<RatingInteractor, RatingState, String>(
  RatingInteractor.new,
);

/// Presents the rating sheet. [driverFirstName]/[driverInitials] address the
/// prompt to the human ("How was your trip with Gurpreet?"); both fall back
/// gracefully when the identity seam answered null.
Future<void> showRatingSheet(
  BuildContext context, {
  required String rideId,
  String? driverFirstName,
  String? driverInitials,
}) {
  final colors = context.hoppin.colors;
  return showModalBottomSheet<void>(
    context: context,
    // Keyboard-safe for the comments field; HopSheet draws its own surface.
    isScrollControlled: true,
    useSafeArea: true,
    elevation: 0,
    backgroundColor: Colors.transparent,
    barrierColor: colors.scrim,
    builder: (sheetContext) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
      ),
      child: HopSheet(
        child: _RatingSheetView(
          rideId: rideId,
          driverFirstName: driverFirstName,
          driverInitials: driverInitials,
        ),
      ),
    ),
  );
}

class _RatingSheetView extends ConsumerStatefulWidget {
  const _RatingSheetView({
    required this.rideId,
    this.driverFirstName,
    this.driverInitials,
  });

  final String rideId;
  final String? driverFirstName;
  final String? driverInitials;

  @override
  ConsumerState<_RatingSheetView> createState() => _RatingSheetViewState();
}

class _RatingSheetViewState extends ConsumerState<_RatingSheetView> {
  final _commentsCtrl = TextEditingController();

  @override
  void dispose() {
    _commentsCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final ok = await ref
        .read(ratingInteractorProvider(widget.rideId).notifier)
        .submit(comments: _commentsCtrl.text);
    if (!mounted || !ok) return;
    navigator.pop();
    messenger.showSnackBar(
      const SnackBar(content: Text('Thanks for the feedback!')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rating = ref.watch(ratingInteractorProvider(widget.rideId));
    final notifier = ref.read(ratingInteractorProvider(widget.rideId).notifier);
    final hoppin = context.hoppin;
    final colors = hoppin.colors;
    final type = hoppin.type;
    final initials = widget.driverInitials;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (initials != null) ...[
          Center(
            child: Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: colors.accentSubtle,
                shape: BoxShape.circle,
              ),
              child: Text(
                initials,
                style: type.label.copyWith(
                  color: colors.accent,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          SizedBox(height: hoppin.spacing.sm),
        ],
        Text(
          widget.driverFirstName != null
              ? 'How was your trip with ${widget.driverFirstName}?'
              : 'How was your trip?',
          textAlign: TextAlign.center,
          style: type.title.copyWith(color: colors.textHi),
        ),
        SizedBox(height: hoppin.spacing.md),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 1; i <= 5; i++)
              IconButton(
                onPressed: rating.busy ? null : () => notifier.setScore(i),
                iconSize: 36,
                constraints:
                    const BoxConstraints(minWidth: 48, minHeight: 48),
                tooltip: '$i star${i > 1 ? 's' : ''}',
                icon: Icon(
                  i <= rating.score ? Icons.star : Icons.star_border,
                  color: colors.accent,
                ),
              ),
          ],
        ),
        SizedBox(height: hoppin.spacing.sm),
        TextField(
          controller: _commentsCtrl,
          enabled: !rating.busy,
          maxLines: 2,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Comments (optional)',
            alignLabelWithHint: true,
          ),
        ),
        if (rating.error != null) ...[
          SizedBox(height: hoppin.spacing.sm),
          Text(rating.error!,
              style: type.bodySmall.copyWith(color: colors.error)),
        ],
        SizedBox(height: hoppin.spacing.md),
        HopButton.primary(
          label: 'Submit rating',
          onPressed: rating.busy ? null : _submit,
          busy: rating.busy,
        ),
        SizedBox(height: hoppin.spacing.xs),
        // Skippable = dismiss without penalty (RIDER-05) — a quiet ghost.
        HopButton.ghost(
          label: 'Skip',
          onPressed: rating.busy ? null : () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}
