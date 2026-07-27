import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hoppin_rider/router.dart';
import 'package:hoppin_shared/hoppin_shared.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// 🔴 THE CHECK THAT WAS MISSING — every navigation target in `lib/` must
/// RESOLVE against the real route table.
///
/// **Why this file exists.** Phase 12's honesty audit found SEVEN `context.go`
/// targets in `lib/` that pointed at routes `router.dart` did not contain: the
/// four Profile-hub rows (`/profile/personal`, `/profile/promotions`,
/// `/profile/help`, `/profile/settings`), both legal links (`/legal/terms`,
/// `/legal/privacy`), and the home screen's `/wallet` quick-link — which had
/// never existed at all (the wallet lives on `/payments`). Every one of them
/// dropped the rider on go_router's raw exception page.
///
/// **The suite was green throughout.** It was green *because of how it was
/// written*: three Phase-12 test files hand-built a throwaway `GoRouter`
/// containing exactly the `GoRoute` production was missing, then asserted the
/// screen rendered at it. A test that builds its own router proves its own
/// router works. It cannot, even in principle, see that the app's router lacks
/// the route — and it reads like integration coverage, which is what makes it
/// worse than a bare-harness test rather than better.
///
/// The other near-miss is worth naming, because it looks like this check and is
/// not: `help_support_test.dart` asserted the legal routes by GREPPING the
/// screen's own source for the string `/legal/privacy`. It passed. The path was
/// in the source; it just did not resolve anywhere. Its `reason:` string even
/// said *"Terms must resolve too"* — an assertion structurally incapable of
/// seeing that they did not.
///
/// So: this test asks the ROUTER, not the source. It is the one instrument that
/// would have failed on the day `profile_screen.dart` was first written, and it
/// is deliberately a plain unit test over the real `riderRouterProvider` — no
/// widgets, no pumping, nothing to fake.
void main() {
  /// Every string literal passed to `context.go(...)` / `context.push(...)` in
  /// `lib/`, with its file and line, so a failure names the call site.
  ///
  /// Deliberately literal-only. A computed target (`'/trip/$id'`) cannot be
  /// resolved statically, and the interpolated ones are covered below by their
  /// own explicit sample paths. Better to check what we CAN check exactly than
  /// to half-check everything with a regex that lies.
  final navTargets = <({String path, String file, int line})>[];

  setUpAll(() {
    final callPattern = RegExp(
      r"""(?:context|GoRouterHelper\([^)]*\))\.(?:go|push|replace|pushReplacement)\(\s*'([^'$]+)'""",
    );
    for (final file in Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        for (final m in callPattern.allMatches(lines[i])) {
          navTargets.add(
            (path: m.group(1)!, file: file.path, line: i + 1),
          );
        }
      }
    }
  });

  /// The real router, built exactly as the app builds it.
  GoRouter buildRouter() {
    final container = ProviderContainer(
      overrides: [
        authServiceProvider.overrideWithValue(_RoutingOnlyAuthService()),
      ],
    );
    addTearDown(container.dispose);
    return container.read(riderRouterProvider);
  }

  /// Ask the ROUTER — not the source, not a hand-built stand-in — whether a
  /// path resolves. `configuration.findMatch` is go_router's own resolver: the
  /// same code that decides, at runtime, whether the rider sees a screen or an
  /// exception dump.
  bool resolves(GoRouter router, String path) {
    final match = router.configuration.findMatch(Uri.parse(path));
    return match.routes.isNotEmpty;
  }

  test(
      '🔴 every context.go/push literal in lib/ resolves against the REAL route '
      'table', () {
    final router = buildRouter();

    final dead = navTargets.where((t) => !resolves(router, t.path)).toList();

    expect(
      dead,
      isEmpty,
      reason:
          'These navigation targets exist in lib/ but NOT in the router. Each '
          'one drops the rider on go_router\'s error page.\n\n'
          '${dead.map((t) => '  ${t.file}:${t.line} → ${t.path}').join('\n')}\n\n'
          'This is the check that was missing. Seven such targets shipped — the '
          'four Profile rows, both legal links, and /wallet (which never '
          'existed; the wallet is /payments). The suite stayed green because '
          'three test files built their OWN GoRouter containing exactly the '
          'route production lacked.\n\n'
          'If you are here because you added a route: add it to router.dart. Do '
          'NOT add it to a test-local router.',
    );
  });

  test('the parameterised routes resolve for a representative id', () {
    // The literal sweep above skips interpolated targets (`'/trip/$id'`) by
    // design — a static check cannot resolve them. They are not thereby
    // exempt, so they are pinned here explicitly. Adding a new `/x/:id` route
    // means adding a line here; that is the intended friction.
    final router = buildRouter();
    for (final path in const [
      '/trip/ride-1',
      '/trip/ride-1/receipt',
      '/trip/ride-1/chat',
      '/trip/ride-1/call',
      '/support/ticket-1',
    ]) {
      expect(resolves(router, path), isTrue,
          reason: '$path must resolve — it is reached by interpolation, which '
              'the literal sweep above cannot see');
    }
  });

  test('the six Phase-12 surfaces are in the REAL route table', () {
    // Named explicitly, and not merely covered by the sweep above, because the
    // sweep only proves *what lib/ asks for* resolves. If someone deleted the
    // hub row AND the route together, the sweep would go green on an app with
    // no route to the privacy notice — which is an Art. 13 problem, not a
    // navigation one. These six are owed regardless of who links to them.
    final router = buildRouter();
    for (final path in const [
      '/profile/personal',
      '/profile/settings',
      '/profile/promotions',
      '/profile/help',
      '/legal/privacy',
      '/legal/terms',
    ]) {
      expect(resolves(router, path), isTrue,
          reason: 'Phase 12 built the screen for $path. A screen with no route '
              'is not shipped — it is dead code wearing a compliance badge.');
    }
  });

  test('an unresolvable path is a DESIGNED screen, not an exception dump', () {
    final router = buildRouter();

    expect(resolves(router, '/this-route-does-not-exist'), isFalse,
        reason: 'sanity: the resolver must actually be able to say no, or every '
            'assertion above is vacuous');
    expect(router.configuration.topRedirect, isNotNull,
        reason: 'sanity: the router under test is the real one');

    // The errorBuilder is what stands between a bad deep link and go_router's
    // default grey page + raw exception text. Deep links and push payloads
    // carry paths from OUTSIDE the binary, so route hygiene in lib/ cannot make
    // this unreachable — only a designed screen can make it survivable.
    final source = File('lib/router.dart').readAsStringSync();
    expect(source.contains('errorBuilder'), isTrue,
        reason: 'router.dart must set an errorBuilder. Without one, go_router '
            'renders "Page not found" over an exception dump — in a shipped '
            'consumer app. RouteNotFoundScreen is the designed landing.');
  });
}

/// The router reads exactly two things off [AuthService]: `isSignedIn` (the
/// redirect) and `onAuthStateChange` (the refresh listenable). Everything else
/// throws, so that a future router change which quietly starts depending on
/// more of the auth surface fails loudly here instead of silently passing.
class _RoutingOnlyAuthService implements AuthService {
  @override
  bool get isSignedIn => true;

  @override
  Stream<AuthState> get onAuthStateChange => const Stream.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
        'router_reachability_test drives ONLY the route table. The router '
        'reached for ${invocation.memberName} — if that is deliberate, add it '
        'to this fake explicitly.',
      );
}
