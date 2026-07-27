import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 🔴 ONE SCREEN, ONE HEADER — and every screen has a way out.
///
/// **The bugs this exists to prevent.** Three symptoms, one root cause: the
/// navigation layer had **no shared rule about who owns the chrome**, so every
/// screen guessed, and guessed differently.
///
///   * **Two stacked headers on Support.** `/support` is a shell tab, and the
///     shell already renders a `HopTopBar` above every tab. The screen built a
///     SECOND one, so the rider saw the title bar twice — the shell's (with the
///     real unread badge) sitting on the screen's (without it). `TicketScreen`
///     had it too.
///
///   * **Profile could not reach Notifications.** Profile sits OUTSIDE the
///     shell, so it does not inherit the shell's bar — which is where the bell
///     lives. It built its own and passed no `onBell`, so no bell rendered.
///     There was no control on the page to reach the notification centre.
///
///   * **🔴 FIVE SCREENS HAD NO EXIT AT ALL** — Safety/SOS, Saved places,
///     Emergency contacts, Privacy notice and Terms. They used a stock Material
///     `AppBar`, which only auto-draws a back arrow when `Navigator.canPop()`
///     is true. These screens are reached with `context.go`, which **REPLACES**
///     rather than pushes — so there is nothing to pop, the arrow never
///     renders, and the rider is **trapped**. On the SOS screen, of all places.
///     The legal pair is reached from the SIGNUP consent link, so a new user
///     could read the privacy notice and never get back to finish signing up.
///
/// **The rule, stated once:**
///
///   1. A screen INSIDE the shell must NOT build its own `HopTopBar` — the
///      shell renders one for it. Two bars is the bug.
///   2. A screen OUTSIDE the shell MUST build a `HopTopBar` with a NON-NULL
///      `onBack`. Nothing else will give it an exit. A stock `AppBar` is not
///      good enough: its back arrow is conditional on a stack that `go` has
///      already destroyed.
///   3. Off-shell leaves must be reached with **`context.push`**, so that
///      `pop()` returns the rider whence they came instead of falling through
///      to a hardcoded fallback.
///
/// **These are SOURCE tests, and deliberately so.** The defect is the ABSENCE
/// of a control (and the PRESENCE of one that should not exist). A widget test
/// can only assert about a screen you already thought to pump — it cannot sweep
/// the app for a rule violation. The previous `no_dead_ends_test` missed all
/// five trapped screens for exactly this reason: it checked screens that HAD a
/// `HopTopBar` for a null `onBack`, so a screen with **no bar at all** sailed
/// straight through. It could not see the absence of the thing it was checking.
///
/// The off-shell screen list is derived FROM THE ROUTER, not hand-maintained,
/// so a screen nobody remembered cannot slip through again.
void main() {
  final routerSrc = File('lib/router.dart').readAsStringSync();

  /// Everything under `StatefulShellRoute` — the shell owns their chrome.
  /// Anything else with a builder is off-shell and owes its own.
  final shellStart = routerSrc.indexOf('StatefulShellRoute');
  final shellEnd = routerSrc.indexOf(
    'Top-level pushes OVER the shell',
  );

  final inShellSrc = routerSrc.substring(shellStart, shellEnd);
  final offShellSrc = routerSrc.substring(shellEnd);

  /// `builder: (_, _) => const FooScreen()` / `(_, state) => FooScreen(`
  final screenRe = RegExp(r'=>\s*(?:const\s+)?(\w+Screen)\s*\(');

  Set<String> screensIn(String src) =>
      screenRe.allMatches(src).map((m) => m.group(1)!).toSet();

  final inShell = screensIn(inShellSrc);
  final offShell = screensIn(offShellSrc)
    // The 404 screen is the router's own fallback and is not navigable-to.
    ..remove('RouteNotFoundScreen');

  /// Map a class name back to its source file.
  ///
  /// The filename must match EXACTLY. An `endsWith` match looks equivalent and
  /// is not: `SupportScreen` → `support_screen.dart` also endsWith-matches
  /// `help/help_support_screen.dart`, so the test blamed the wrong file — and a
  /// test that names an innocent file is worse than no test, because someone
  /// will "fix" the file it accused.
  File? fileFor(String className) {
    final snake =
        '${className.replaceAllMapped(
          RegExp('([a-z0-9])([A-Z])'),
          (m) => '${m[1]}_${m[2]}',
        ).toLowerCase()}.dart';

    for (final e in Directory('lib/features').listSync(recursive: true)) {
      if (e is! File) continue;
      final name = e.uri.pathSegments.last;
      if (name == snake) return e;
    }
    return null;
  }

  /// A file's CODE, with comments stripped.
  ///
  /// This test greps source text, and source text includes prose. Two screens
  /// were falsely accused of shipping `onBack: null` because their comments
  /// **quoted the bug verbatim** while explaining it — the documentation was so
  /// accurate it became the defect it described.
  ///
  /// The wrong fix is to reword the comments until the grep stops matching:
  /// that silently forbids writing down what went wrong, which is the most
  /// valuable thing in these files. The right fix is for the test to read code
  /// and not prose.
  String codeOf(File f) => f
      .readAsStringSync()
      .replaceAll(RegExp(r'^\s*///.*$', multiLine: true), '')
      .replaceAll(RegExp(r'^\s*//.*$', multiLine: true), '')
      .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '');

  test('the router still yields both sets (guards the test itself)', () {
    expect(
      shellStart >= 0 && shellEnd > shellStart,
      isTrue,
      reason:
          'Could not locate the shell boundary in router.dart. If the router '
          'was restructured, update the markers this test keys on — do NOT '
          'delete the test.',
    );
    expect(inShell, isNotEmpty, reason: 'No in-shell screens found.');
    expect(offShell, isNotEmpty, reason: 'No off-shell screens found.');
  });

  test('no screen INSIDE the shell builds its own HopTopBar', () {
    final offenders = <String>[];

    for (final screen in inShell) {
      final f = fileFor(screen);
      if (f == null) continue;
      if (codeOf(f).contains('HopTopBar(')) {
        offenders.add('$screen (${f.path})');
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'These screens live inside the shell, which ALREADY renders a '
          'HopTopBar above every tab. Building a second one stacks two headers '
          '— the duplicate "Support" bar the rider reported. Delete the '
          'screen-level bar; the shell owns the chrome.\n'
          'Offenders:\n  ${offenders.join('\n  ')}',
    );
  });

  // NO ALLOWLIST. There was one here, for exactly one screen, and it was wrong.
  //
  // `CallScreen` looked like the legitimate exception: a full-bleed in-call
  // surface that exits by its own end-call button, where a back arrow would be
  // ambiguous (does it hang up?). That reasoning was plausible and FALSE. The
  // end-call button is `onPressed: null` — DELIBERATELY disabled, because on
  // seam #45 there is no call to hang up. So the "exit" the exemption trusted
  // does nothing, and the screen's own close control called a bare
  // `context.pop()` on a route reached with `go` — also a no-op. The screen had
  // ZERO working exits, and the exemption would have waved it straight through.
  //
  // The lesson is the point: an allowlist asserts a screen is safe, and an
  // assertion nobody re-checks is how the original bug shipped. Every off-shell
  // screen proves its exit the same way, with no exceptions. If a future screen
  // genuinely cannot carry a top bar, make it prove a real exit some other way
  // — do not exempt it from having to prove one.

  test('🔴 every screen OUTSIDE the shell has a real, unconditional exit', () {
    final trapped = <String>[];

    for (final screen in offShell) {
      final f = fileFor(screen);
      if (f == null) continue;
      final src = codeOf(f);

      // It must use the design system's bar...
      if (!src.contains('HopTopBar(')) {
        trapped.add(
          '$screen — NO HopTopBar (${f.path}). '
          'A stock AppBar hides its back arrow when canPop() is false, which '
          'is ALWAYS, because `go` replaced the route.',
        );
        continue;
      }
      // ...and that bar must actually offer a way back.
      if (!src.contains('onBack:')) {
        trapped.add('$screen — HopTopBar with NO onBack (${f.path})');
        continue;
      }
      if (RegExp(r'onBack:\s*null').hasMatch(src)) {
        trapped.add(
          '$screen — `onBack: null` HIDES the button entirely (${f.path})',
        );
      }
    }

    expect(
      trapped,
      isEmpty,
      reason:
          'A screen outside the shell has NO bottom nav and NO shell bar. '
          'Without its own HopTopBar carrying a non-null onBack, the rider is '
          'STRANDED. This trapped the rider on the SOS screen — the one screen '
          'where panic is likeliest — and on the privacy notice linked from '
          'signup.\n'
          'Trapped:\n  ${trapped.join('\n  ')}',
    );
  });

  test('the Profile hub offers the bell', () {
    final src = codeOf(File('lib/features/profile/profile_screen.dart'));

    expect(
      src.contains('onBell:'),
      isTrue,
      reason:
          'Profile is off-shell, so it does not inherit the shell bell. '
          'Without an onBell here the rider CANNOT REACH the notification '
          'centre from their profile — exactly the bug reported.',
    );
  });

  test('off-shell leaves are PUSHED, never GONE-to', () {
    /// Routes the rider is expected to come BACK from. `go` on any of these
    /// destroys the stack, so `pop()` cannot return them.
    ///
    /// The `/trip/*` leaves are here because they were the LAST hiding place of
    /// this bug: `trip_router.dart` reached chat, call, the receipt and safety
    /// with `go`, and the sweep below never saw it — the exclusion was written
    /// as `endsWith('router.dart')`, which was meant to skip the app's route
    /// TABLE and silently skipped every feature router too.
    const mustPush = <String>[
      '/notifications',
      '/profile/personal',
      '/profile/settings',
      '/profile/promotions',
      '/profile/help',
      '/safety',
      '/places',
      '/contacts',
      '/legal/privacy',
      '/legal/terms',
      '/chat',
      '/call',
      '/receipt',
    ];

    final offenders = <String>[];

    for (final e in Directory('lib').listSync(recursive: true)) {
      if (e is! File || !e.path.endsWith('.dart')) continue;
      // Skip ONLY the app's route table — it DECLARES paths rather than
      // navigating to them, and its auth redirect legitimately uses `go` (a
      // login bounce must not be poppable back into). Feature routers like
      // `trip_router.dart` are NOT exempt: they navigate, so they are exactly
      // what this sweep is for.
      if (e.uri.pathSegments.last == 'router.dart') continue;

      final src = codeOf(e);
      for (final route in mustPush) {
        // Match the route wherever it appears in a `go` call — trailing query
        // strings (`/safety?rideId=$id`) and interpolated segments
        // (`/trip/$rideId/chat`) must not let it slip past an exact match.
        final goRe = RegExp(
          r'''context\.go\(\s*['"][^'"]*''' + RegExp.escape(route),
        );
        if (goRe.hasMatch(src)) {
          offenders.add('${e.path} → context.go(… $route …)');
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          '`context.go` REPLACES the route, so `canPop()` is false forever: the '
          'back button falls through to a hardcoded fallback and the rider is '
          'teleported somewhere they never came from (Profile → bell → back → '
          'dumped on Book). Worse, a stock AppBar simply hides its arrow. Use '
          '`context.push` for off-shell leaves so `pop()` returns them.\n'
          'Offenders:\n  ${offenders.join('\n  ')}',
    );
  });
}
