import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:hoppin_shared/hoppin_shared.dart';
import 'package:hoppin_ui/hoppin_ui.dart';

/// The contract floor: a scheduled pickup must sit at least this far ahead
/// (rides_repository.dart:159 — the server rejects anything closer with
/// `VALIDATION_FAILED`). Enforced client-side too so the rider is told the
/// rule before the round-trip.
const Duration kScheduleFloor = Duration(minutes: 30);

/// Plain-English statement of the ≥30-min rule (shown when a pick is too
/// soon). No raw error codes — the rider reads the rule in words.
const String scheduleFloorMessage =
    'Scheduled rides must be at least 30 minutes from now.';

/// True when [when] is far enough ahead to satisfy the ≥30-min floor. Uses
/// [clock.now] (never `DateTime.now`) so it runs deterministically under
/// `fake_async`/`withClock`.
bool isValidScheduleTime(DateTime when) {
  final floor = clock.now().add(kScheduleFloor);
  // `isBefore` is strict; an exactly-30-min pick is valid.
  return !when.isBefore(floor);
}

/// The scheduled-ride date/time entry (Figma "Book (Schedule) - date"). Lets
/// the rider pick a future date + time via Material's themed
/// `showDatePicker`/`showTimePicker` (zero extra dependency), enforces the
/// ≥30-min floor client-side, and confirms the chosen [DateTime] via
/// [onConfirm]. Presentation-only — the create call lives in the interactor.
class SchedulePicker extends StatefulWidget {
  const SchedulePicker({
    required this.onConfirm,
    this.initialSelection,
    super.key,
  });

  /// Emits the chosen pickup time once the rider confirms a valid selection.
  final ValueChanged<DateTime> onConfirm;

  /// Optional seeded selection (tests + "edit" entry). When absent the picker
  /// opens with no selection and the CTA stays disabled until one is made.
  final DateTime? initialSelection;

  @override
  State<SchedulePicker> createState() => _SchedulePickerState();
}

class _SchedulePickerState extends State<SchedulePicker> {
  DateTime? _selection;

  @override
  void initState() {
    super.initState();
    _selection = widget.initialSelection;
  }

  bool get _valid => _selection != null && isValidScheduleTime(_selection!);

  Future<void> _pick() async {
    final now = clock.now();
    final base = _selection ?? now.add(kScheduleFloor);
    final date = await showDatePicker(
      context: context,
      initialDate: base,
      firstDate: now,
      lastDate: now.add(const Duration(days: 90)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(base),
    );
    if (time == null || !mounted) return;
    setState(() {
      _selection = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final hoppin = context.hoppin;
    final colors = hoppin.colors;
    final type = hoppin.type;
    final selection = _selection;

    return Padding(
      padding: EdgeInsets.all(hoppin.spacing.gutter),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Schedule your ride',
            style: type.section.copyWith(color: colors.textHi),
          ),
          SizedBox(height: hoppin.spacing.md),
          // The date/time entry row — taps into the Material pickers.
          HopCard(
            onTap: _pick,
            padding: EdgeInsets.symmetric(
              horizontal: hoppin.spacing.lg,
              vertical: hoppin.spacing.md,
            ),
            child: Row(
              children: [
                Icon(Icons.event, color: colors.accent),
                SizedBox(width: hoppin.spacing.md),
                Expanded(
                  child: Text(
                    selection == null
                        ? 'Choose date & time'
                        : formatShortDateTime(selection),
                    style: type.bodyMedium.copyWith(
                      color: selection == null ? colors.textMid : colors.textHi,
                    ),
                  ),
                ),
                Icon(Icons.chevron_right, color: colors.textMid),
              ],
            ),
          ),
          SizedBox(height: hoppin.spacing.sm),
          // The floor rule: always visible as guidance; turns into an active
          // warning tone once a too-soon selection is made.
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.info_outline,
                size: 16,
                color: (selection != null && !_valid)
                    ? colors.error
                    : colors.textMid,
              ),
              SizedBox(width: hoppin.spacing.xs),
              Expanded(
                child: Text(
                  scheduleFloorMessage,
                  style: type.metaSmall.copyWith(
                    color: (selection != null && !_valid)
                        ? colors.error
                        : colors.textMid,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: hoppin.spacing.lg),
          HopButton.primary(
            label: 'Confirm schedule',
            onPressed: _valid ? () => widget.onConfirm(_selection!) : null,
          ),
        ],
      ),
    );
  }
}
