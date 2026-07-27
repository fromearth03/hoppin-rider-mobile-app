import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hoppin_shared/hoppin_shared.dart';
import 'package:hoppin_ui/hoppin_ui.dart';

import '../location/jit_location_prompt.dart';
import '../location/location_providers.dart';

/// My SOS events — `GET /me/sos`.
final sosEventsProvider = FutureProvider.autoDispose<List<SosEvent>>((ref) {
  return ref.watch(safetyRepositoryProvider).myEvents();
});

/// Safety hub: raise an SOS (optionally tied to a ride) + past events.
/// Reachable from home and from the trip screen (which passes its rideId).
class SafetyScreen extends ConsumerStatefulWidget {
  const SafetyScreen({this.rideId, super.key});

  /// When opened from a live trip, the SOS is attached to that ride.
  final String? rideId;

  @override
  ConsumerState<SafetyScreen> createState() => _SafetyScreenState();
}

class _SafetyScreenState extends ConsumerState<SafetyScreen> {
  bool _busy = false;

  /// The JIT location prompt (COMPLY-02) — offered *beside* the SOS, never in
  /// front of it. Granting location makes the next SOS more precise; refusing
  /// it does not stop the next SOS from firing.
  Future<void> _offerLocationPermission() async {
    final service = ref.read(locationServiceProvider);
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      backgroundColor: context.hoppin.colors.card,
      builder: (sheetContext) => JitLocationPrompt(
        service: service,
        onResult: (_) => Navigator.of(sheetContext).pop(),
      ),
    );
  }

  Future<void> _confirmAndRaise() async {
    final note = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      barrierColor: context.hoppin.colors.scrim,
      builder: (dialogContext) => _SosConfirmDialog(
        note: note,
        onOfferLocation: _offerLocationPermission,
      ),
    );

    if (confirmed != true) {
      note.dispose();
      return;
    }
    final text = note.text.trim();
    note.dispose();

    if (!mounted) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);

    // GPS is BEST-EFFORT. SAFETY-01: the SOS is logged even when location is
    // denied or the trip is cancelled — a location failure DEGRADES the
    // payload, it NEVER blocks the alert. So: bounded wait, null on any
    // failure, fire regardless. A safety feature that fails closed on a denied
    // permission is worse than one that sends an imprecise alert.
    //
    // currentPosition() is contractually bounded and never throws, so this
    // await cannot hang and cannot escape into the catch below.
    final pos = await ref.read(locationServiceProvider).currentPosition();

    try {
      await ref.read(safetyRepositoryProvider).raiseSos(
            rideId: widget.rideId, // may be null — cancelled / no trip
            lat: pos?.lat, // may be null — denied / timeout / refused
            lng: pos?.lng, // never fabricated: no fix means no coordinate
            note: text.isEmpty ? null : text,
          );
      ref.invalidate(sosEventsProvider);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            pos == null
                // HONEST: the rider is TOLD the alert went WITHOUT location, so
                // they know to say where they are. The confirm dialog said the
                // safety team would see their location — when we cannot keep
                // that promise we say so, rather than shipping a silently
                // locationless SOS.
                ? 'SOS raised — the safety team has been alerted. We could not '
                    'get your location, so tell them where you are.'
                : 'SOS raised — the safety team has been alerted with your '
                    'location.',
          ),
        ),
      );
    } on Exception catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(friendlyErrorMessage(e))),
      );
    } finally {
      // The SOS button never latches disabled: the rider can always raise
      // again, whatever happened to the location or the network.
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hoppin = context.hoppin;
    final colors = hoppin.colors;
    final type = hoppin.type;
    final events = ref.watch(sosEventsProvider);

    return Scaffold(
      backgroundColor: colors.canvas,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 🔴 THIS SCREEN HAD NO WAY OUT. It carried a stock Material
            // `AppBar`, whose back arrow only auto-draws when
            // `Navigator.canPop()` is true — and Safety is reached with
            // `context.go`, which REPLACES the route rather than pushing it. So
            // there was nothing to pop, the arrow never rendered, and the rider
            // was stranded. On the SOS screen, of all of them: the one surface
            // where panic is likeliest and being trapped costs the most. It is
            // off-shell too, so there was no bottom nav to escape by either.
            //
            // `onBack` is NEVER null — null hides the button, which is precisely
            // the bug. Pop when there is a stack; else fall back to Book, the
            // home tab this screen is reached from.
            HopTopBar(
              title: 'Safety',
              onBack: () =>
                  context.canPop() ? context.pop() : context.go('/book'),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async => ref.invalidate(sosEventsProvider),
                child: ListView(
                  padding: EdgeInsets.all(hoppin.spacing.gutter),
                  children: [
                    // The big red button — unmissable, thumb-reachable, guarded
                    // by a confirm dialog so it can't fire by accident. It is
                    // NEVER disabled by a location failure; `busy` only reflects
                    // the in-flight raise.
                    HopButton.red(
                      key: const Key('sos_raise_button'),
                      label: _busy ? 'Sending…' : 'Emergency — raise SOS',
                      icon: Icons.sos,
                      busy: _busy,
                      onPressed: _confirmAndRaise,
                    ),
                    SizedBox(height: hoppin.spacing.md),
                    // The 999 call-out is UNCONDITIONAL. It used to be shown
                    // only when there was NO active trip — replaced, during a
                    // live ride, by a logistics note. That inverted the risk:
                    // the rider in a stranger's moving car is the one who most
                    // needs to be told to dial 999, and was the only one who
                    // wasn't. Trip linkage and the 999 instruction are not
                    // alternatives; both are shown, and 999 outranks.
                    const _Call999Callout(key: Key('sos_call_999_callout')),
                    if (widget.rideId != null) ...[
                      SizedBox(height: hoppin.spacing.sm),
                      Text(
                        'This SOS will also be linked to your current trip.',
                        key: const Key('sos_trip_link_note'),
                        textAlign: TextAlign.center,
                        style: type.metaSmall.copyWith(color: colors.textMid),
                      ),
                    ],
                    SizedBox(height: hoppin.spacing.gutter),
                    Text('Previous alerts',
                        style: type.section.copyWith(color: colors.textHi)),
                    SizedBox(height: hoppin.spacing.sm),
                    events.when(
                      loading: () => Padding(
                        padding: EdgeInsets.all(hoppin.spacing.gutter),
                        child: const Center(child: CircularProgressIndicator()),
                      ),
                      error: (e, _) =>
                          StatusBanner.error(message: friendlyErrorMessage(e)),
                      data: (list) => list.isEmpty
                          ? Text(
                              'No SOS alerts raised.',
                              style: type.meta.copyWith(color: colors.textMid),
                            )
                          : Column(
                              children: [
                                for (final e in list) ...[
                                  HopCard(
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.sos,
                                          color: e.status == 'resolved'
                                              ? colors.textMid
                                              : colors.error,
                                        ),
                                        SizedBox(width: hoppin.spacing.md),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                e.note ?? 'SOS alert',
                                                style: type.bodyMedium.copyWith(
                                                    color: colors.textHi),
                                              ),
                                              Text(
                                                e.createdAt == null
                                                    ? e.status
                                                    : '${e.status} · '
                                                        '${formatShortDateTime(e.createdAt!)}',
                                                style: type.metaSmall.copyWith(
                                                    color: colors.textMid),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  SizedBox(height: hoppin.spacing.sm),
                                ],
                              ],
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The 999 instruction. It is the only genuinely life-saving thing on this
/// screen, so it is rendered as a full-width alert block — not a footnote —
/// and it renders in EVERY state of the screen.
///
/// It is text, not a dial button: this app never dials. `grep -rn "tel:"` is
/// empty monorepo-wide and pinned that way by test, so the rider is told to
/// dial rather than handed a link that would silently fail on web.
class _Call999Callout extends StatelessWidget {
  const _Call999Callout({this.compact = false, super.key});

  /// The dialog variant: same instruction, one line shorter, so the confirm and
  /// cancel buttons stay above the fold on a small screen. The 999 line itself
  /// is never dropped — only the second paragraph, which the screen behind the
  /// dialog already carries.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final hoppin = context.hoppin;
    final colors = hoppin.colors;
    final type = hoppin.type;

    return Container(
      padding: EdgeInsets.all(hoppin.spacing.md),
      decoration: BoxDecoration(
        color: colors.errorSubtle,
        border: Border.all(color: colors.error),
        borderRadius: BorderRadius.circular(hoppin.radii.input),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.phone_in_talk, color: colors.error),
          SizedBox(width: hoppin.spacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'In immediate danger? Call 999 first.',
                  style: type.bodyMedium.copyWith(color: colors.error),
                ),
                SizedBox(height: hoppin.spacing.xs),
                // Deliberately says what Hoppin CANNOT do without naming the
                // services it cannot reach: a test bans those words outright on
                // this screen, so no future copy edit can reintroduce the claim
                // that raising an SOS summons them.
                Text(
                  compact
                      ? 'An SOS does not dial 999 for you.'
                      : 'Raising an SOS does not dial 999 for you. Hoppin’s '
                          'safety team cannot send help to you — only 999 can.',
                  style: type.metaSmall.copyWith(color: colors.textHi),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The Figma SOS confirm frame (`Ride Now - Active trip (sos)`), on tokens.
///
/// The copy states exactly what `POST /me/sos` does and nothing more: it raises
/// a panic event on Hoppin's admin safety dashboard (DOCS/04 §Safety). There is
/// no 999 integration and no emergency-services gateway of any kind, so the
/// dialog must never let a rider believe the authorities have been alerted.
///
/// It likewise cannot promise driver information: `driverInfo()` is seam #5 and
/// always returns null, so the app has none to send.
///
/// The location promise IS honest, because [_SafetyScreenState._confirmAndRaise]
/// actually reads a fix and passes `lat`/`lng` — and when it cannot get one it
/// says so, rather than quietly shipping a locationless SOS.
class _SosConfirmDialog extends StatelessWidget {
  const _SosConfirmDialog({
    required this.note,
    required this.onOfferLocation,
  });

  final TextEditingController note;
  final Future<void> Function() onOfferLocation;

  @override
  Widget build(BuildContext context) {
    final hoppin = context.hoppin;
    final colors = hoppin.colors;
    final type = hoppin.type;

    return Dialog(
      backgroundColor: colors.card,
      insetPadding: EdgeInsets.all(hoppin.spacing.gutter),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(hoppin.radii.pillSmall),
      ),
      // The narrative scrolls; the two actions NEVER do. A panic dialog whose
      // "Trigger SOS" button can fall below the fold on a short screen is its
      // own safety defect, so the buttons are pinned outside the scroll view.
      child: Padding(
        padding: EdgeInsets.all(hoppin.spacing.gutter),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(Icons.warning_amber_rounded,
                        size: 48, color: colors.error),
                    SizedBox(height: hoppin.spacing.md),
                    Text(
                      'Trigger Emergency Alert?',
                      textAlign: TextAlign.center,
                      style: type.section.copyWith(color: colors.textHi),
                    ),
                    SizedBox(height: hoppin.spacing.sm),
                    Text(
                      'This alerts Hoppin’s safety team. They will see your '
                      'location and your trip, and will contact you.',
                      key: const Key('sos_confirm_what_happens'),
                      textAlign: TextAlign.center,
                      style: type.meta.copyWith(color: colors.textMid),
                    ),
                    SizedBox(height: hoppin.spacing.md),
                    // The rider is about to commit to the alarm. This is the
                    // last surface before that, so the 999 truth is repeated.
                    const _Call999Callout(
                      key: Key('sos_confirm_call_999'),
                      compact: true,
                    ),
                    SizedBox(height: hoppin.spacing.md),
                    Text(
                      'This action cannot be undone and will be logged as a '
                      'regulatory incident.',
                      textAlign: TextAlign.center,
                      style: type.metaSmall.copyWith(color: colors.error),
                    ),
                    SizedBox(height: hoppin.spacing.md),
                    TextField(
                      key: const Key('sos_note_field'),
                      controller: note,
                      maxLines: 2,
                      style: type.meta.copyWith(color: colors.textHi),
                      decoration: InputDecoration(
                        labelText: 'What is happening? (optional)',
                        labelStyle: type.meta.copyWith(color: colors.textMid),
                        border: OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(hoppin.radii.input),
                        ),
                      ),
                    ),
                    SizedBox(height: hoppin.spacing.md),
                    // COMPLY-02: the JIT prompt's first real mount site. It
                    // sits BESIDE the alarm, never in front of it — the SOS
                    // fires whether or not the rider ever taps this.
                    HopButton.ghost(
                      key: const Key('sos_location_prompt_button'),
                      label: 'Turn on location',
                      icon: Icons.my_location,
                      onPressed: onOfferLocation,
                    ),
                    SizedBox(height: hoppin.spacing.xs),
                    Text(
                      'A live fix gets help to you faster. Without it your SOS '
                      'still goes through — you will just need to say where '
                      'you are.',
                      textAlign: TextAlign.center,
                      style: type.metaSmall.copyWith(color: colors.textMid),
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(height: hoppin.spacing.md),
            HopButton.red(
              key: const Key('sos_confirm_button'),
              label: 'Trigger SOS',
              onPressed: () => Navigator.of(context).pop(true),
            ),
            SizedBox(height: hoppin.spacing.sm),
            HopButton.ghost(
              key: const Key('sos_cancel_button'),
              label: 'Cancel',
              onPressed: () => Navigator.of(context).pop(false),
            ),
          ],
        ),
      ),
    );
  }
}
