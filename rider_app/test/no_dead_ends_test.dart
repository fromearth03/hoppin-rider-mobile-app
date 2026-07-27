import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 🔴 NO DEAD ENDS — every screen outside the shell's own tabs owes an exit.
///
/// **The bug this exists to prevent.** Four screens shipped with:
///
/// ```dart
/// onBack: Navigator.of(context).canPop()
///     ? () => Navigator.of(context).pop()
///     : null,          // <-- HIDES THE BACK BUTTON ENTIRELY
/// ```
///
/// Two things go wrong at once, and they compound:
///
/// 1. **`onBack: null` HIDES the button.** It does not disable it, it does not
///    grey it — it removes the only exit from the screen.
/// 2. **These screens are reached with `context.go`, which REPLACES rather than
///    pushes.** So `canPop()` is `false`, the `null` branch is taken, and the
///    button is gone. The condition that was supposed to be a safety check is
///    the thing that fires.
///
/// Result: the rider taps the bell, lands on the notification centre, and is
/// **stranded** — no back button, no bottom nav, no way home. Same on
/// Promotions (reached from the Profile hub) and on a support ticket (reached
/// from the deletion popup, which lands the rider on the very ticket they just
/// filed and then traps them there).
///
/// **The rule, stated once:** a screen either lives in the shell (and the bottom
/// nav is its exit) or it owes an unconditional `onBack`. `null` is never an
/// acceptable value — when there is no stack to pop, `go` somewhere sensible.
///
/// ```dart
/// onBack: () => context.canPop() ? context.pop() : context.go('/somewhere'),
/// ```
///
/// This is a source assertion rather than a widget one on purpose: the defect is
/// *the absence of a control*, and a widget test can only find what is there. It
/// is far too easy to write a green test for a screen whose exit does not exist.
void main() {
  test(
      '🔴 no screen hides its back button — `onBack: null` strands the rider',
      () {
    // `onBack:` followed (within a few lines) by a bare `null`. The pattern we
    // are hunting is the conditional that evaluates to null, not just a literal
    // `onBack: null` — that is exactly how all four shipped.
    // The four shell tabs (/book · /history · /payments · /support) are the ONE
    // legitimate exception: the bottom nav is always on screen, so it is always
    // an exit and a back arrow would be redundant. `onBack: null` there is a
    // deliberate statement, not a stranding. Every OTHER screen covers the shell
    // and owes its own way out.
    const shellTabs = {
      'lib/features/support/support_screen.dart',
      'lib/features/booking/booking_view.dart',
      'lib/features/history/history_screen.dart',
      'lib/features/wallet/wallet_screen.dart',
    };

    final offenders = <String>[];

    for (final file in Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      final relPath =
          'lib/${file.path.replaceAll(r'\', '/').split('lib/').last}';
      if (shellTabs.contains(relPath)) continue;
      final src = file.readAsStringSync();
      // Look at each `onBack:` and the 4 lines after it — long enough to catch
      // a ternary split across lines, short enough not to swallow the next
      // widget.
      final lines = src.split('\n');
      for (var i = 0; i < lines.length; i++) {
        if (!lines[i].contains('onBack:')) continue;
        final window = lines
            .sublist(i, (i + 5).clamp(0, lines.length))
            .join('\n');
        // A `: null,` or `onBack: null` inside the window is the defect. Ignore
        // comment lines, so the explanatory comments above each fix do not trip
        // their own guard.
        final code = window
            .split('\n')
            .where((l) => !l.trimLeft().startsWith('//'))
            .join('\n');
        if (RegExp(r'onBack:\s*null|:\s*null\s*,').hasMatch(code)) {
          final rel = file.path.replaceAll(r'\', '/').split('lib/').last;
          offenders.add('lib/$rel:${i + 1}');
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'These screens can render with NO back button, which strands the '
          'rider:\n'
          '  ${offenders.join('\n  ')}\n\n'
          '`onBack: null` HIDES the control — it does not disable it. And these '
          'screens are reached with `context.go`, which REPLACES rather than '
          'pushes, so `canPop()` is false and the null branch is exactly the one '
          'that fires. The guard is the bug.\n\n'
          'Every screen outside the shell tabs owes an unconditional exit:\n'
          '  onBack: () => context.canPop() '
          '? context.pop() : context.go(\'/somewhere\'),',
    );
  });

  test('no screen decides its BACK AFFORDANCE on plain Navigator', () {
    // `Navigator.of(context).canPop()` cannot see the go_router stack, so it
    // answers the wrong question. That was the other half of the same bug.
    //
    // Scoped to `onBack:` deliberately. `receipt_screen.dart` and
    // `trip_screen.dart` also call `Navigator.of(context).canPop()`, but they
    // use it CORRECTLY and INVERTED — receipt shows an explicit "Home" close
    // button precisely WHEN it cannot pop, so it always has an exit. Flagging
    // those would be flagging correct code, and a guard that cries wolf gets
    // switched off. The defect is specifically: an `onBack` whose value is
    // decided by an instrument that cannot see the router.
    final offenders = <String>[];

    for (final file in Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      final lines = file.readAsStringSync().split('\n');
      for (var i = 0; i < lines.length; i++) {
        if (!lines[i].contains('onBack:')) continue;
        final window = lines
            .sublist(i, (i + 5).clamp(0, lines.length))
            .where((l) => !l.trimLeft().startsWith('//'))
            .join('\n');
        if (window.contains('Navigator.of(context).canPop()')) {
          final rel = file.path.replaceAll(r'\', '/').split('lib/').last;
          offenders.add('lib/$rel:${i + 1}');
        }
      }
    }

    expect(offenders, isEmpty,
        reason: 'These decide a back affordance on plain `Navigator`, which '
            'cannot see the go_router stack — so it answers the wrong question '
            'and the affordance is decided on noise:\n'
            '  ${offenders.join('\n  ')}\n\n'
            'Use go_router\'s `context.canPop()`.');
  });
}
