import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hoppin_shared/hoppin_shared.dart';

import 'providers.dart';
import 'features/auth/login_screen.dart';
import 'features/auth/otp_verify_screen.dart';
import 'features/auth/reset_landing_screen.dart';
import 'features/auth/signup_screen.dart';
import 'features/booking/booking_builder.dart';
import 'features/history/history_screen.dart';
import 'features/legal/privacy_notice_screen.dart';
import 'features/legal/terms_screen.dart';
import 'features/notifications/notification_centre_screen.dart';
import 'features/notifications/push_tap_router.dart';
import 'features/places/saved_locations_screen.dart';
import 'features/promotions/promotions_screen.dart';
import 'features/scheduled/scheduled_screen.dart';
import 'features/profile/emergency_contacts_screen.dart';
import 'features/profile/personal/personal_info_screen.dart';
import 'features/profile/profile_screen.dart';
import 'features/safety/safety_screen.dart';
import 'features/settings/settings_screen.dart';
import 'features/shell/rider_shell.dart';
import 'features/shell/route_not_found_screen.dart';
import 'features/support/help/help_support_screen.dart';
import 'features/support/support_screen.dart';
import 'features/support/ticket_screen.dart';
import 'features/trip/call_screen.dart';
import 'features/trip/chat_screen.dart';
import 'features/trip/receipt_screen.dart';
import 'features/trip/trip_screen.dart';
import 'features/wallet/wallet_screen.dart';

/// The rider app's navigation graph (go_router 17.x).
///
/// Shape: a [StatefulShellRoute.indexedStack] hosting the 4-tab shell
/// (Book · History · Payments · Support), each branch keeping its own nav
/// stack, wrapped by [RiderShell] (bottom nav + top bar). The Profile hub and
/// the cross-cutting routes (/trip, /safety, /places, /contacts) are
/// TOP-LEVEL routes OUTSIDE the shell, so they cover it with no bottom nav.
///
/// `redirect` gates everything on auth: signed-out users are bounced to
/// /login; signed-in users hitting /login are sent to the Book tab.
/// Root navigator key — lets context-free code (e.g. the Stripe card sheet)
/// present modals over the app. Injected into [GoRouter] below.
final rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'rootNavigator');

final riderRouterProvider = Provider<GoRouter>((ref) {
  final auth = ref.watch(authServiceProvider);

  // Re-run `redirect` whenever Supabase auth state changes (sign-in/out,
  // token refresh) — otherwise a successful login wouldn't navigate anywhere.
  // Pitfall 5: drive refresh off this listenable, NOT a per-rebuild re-watch
  // of the auth provider, so the GoRouter instance stays stable and the
  // shell's branch navigators (and active tab index) are preserved.
  final authChanges = StreamListenable(auth.onAuthStateChange);
  ref.onDispose(authChanges.dispose);

  // ACTIVE-TRIP LOCK refresh signal. The redirect below reads the rider's live
  // trip from historyProvider; go_router only re-runs `redirect` when a
  // refreshListenable fires, so the lock would engage/release a beat late (or
  // not at all) unless history changes also poke a refresh. This ChangeNotifier
  // fires whenever historyProvider changes — a booking creates a ride, or
  // TripInteractor invalidates history on a terminal poll — so /book locks the
  // instant a trip goes live and unlocks the instant it ends.
  final tripChanges = _PokableNotifier();
  final sub = ref.listen<AsyncValue<List<Ride>>>(
    historyProvider,
    (_, _) => tripChanges.poke(),
    // fireImmediately so the subscription warms historyProvider at router
    // construction (a FutureProvider only fetches once read), not lazily when
    // the Book screen first paints. Without this the redirect loses a race on
    // cold start: the rider lands on /book, historyProvider is still null, the
    // active-trip check reads null, and the lock never engages — the rider is
    // stranded on the Book shell with a "Trip in progress" banner behind the
    // app bar instead of being taken to /trip/:id.
    fireImmediately: true,
  );
  ref.onDispose(sub.close);
  ref.onDispose(tripChanges.dispose);
  // Force the first fetch now. `ref.listen` subscribes but does not itself
  // await; reading the provider kicks off GET /rides so the cache is populating
  // before the rider can reach /book, and the poke above re-runs the redirect
  // the instant it lands.
  ref.read(historyProvider);

  // PHASE 11 (Lane A trap 6). A notification tap that arrives BEFORE auth
  // settles used to be swallowed: the signed-out redirect bounced it to
  // /login, and the post-login redirect hard-coded `return '/book'` — so the
  // rider tapped "your driver is here" and landed on the Book screen with no
  // explanation. The tap-router was correct; the redirect ate it.
  //
  // We now remember the intended location across the auth settle and hand the
  // rider back to it once. One-shot: consumed on the first post-login redirect,
  // so a later manual visit to /login still lands on /book as before.
  String? pendingDeepLink;

  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: '/book',
    refreshListenable: Listenable.merge([authChanges, tripChanges]),
    redirect: (context, state) {
      // COPY VERBATIM from the pre-shell router — only the post-login target
      // moves from '/' to '/book' (the shell's landing branch).
      final signedIn = auth.isSignedIn;
      final onLogin = state.matchedLocation == '/login';
      // Allowlist the signed-out auth entry points so a deep link (or the
      // signup/verify flow) renders instead of being bounced to /login.
      // Pitfall 3 (09-RESEARCH): the reset-landing MUST survive redirect while
      // signed-out, or its honest GATED state (#49) is never seen.
      //
      // PHASE 12 (owner ruling, 2026-07-13): `/legal/*` is READABLE PRE-LOGIN.
      // The consent notice mounts on SIGNUP, so the rider is asked to read the
      // privacy notice BEFORE the account exists. Art. 13 owes transparency AT
      // the point of collection, and signup IS that point — a privacy link that
      // bounces the very person being asked to trust it is the exact defect this
      // phase exists to kill. It is static bundled content: no personal data, no
      // endpoint, nothing to leak.
      //
      // Everything else Phase 12 adds (`/profile/*`) is an AUTHENTICATED
      // surface and is deliberately NOT allowlisted.
      if (hoppinIsAuthCallback(state.uri) &&
          state.matchedLocation != '/reset') {
        return '/reset${hoppinResetRedirectQuery(state.uri, signedIn: signedIn)}';
      }
      final onSignedOutAuthRoute = onLogin ||
          state.matchedLocation == '/signup' ||
          state.matchedLocation == '/verify' ||
          state.matchedLocation == '/reset' ||
          state.matchedLocation.startsWith('/legal/');
      if (!signedIn) {
        if (onSignedOutAuthRoute) return null;
        // Remember where they were actually trying to go (the push target),
        // then send them through the sign-in they legitimately owe us.
        pendingDeepLink = state.uri.toString();
        return '/login';
      }
      if (state.matchedLocation == '/reset') {
        if (signedIn && state.uri.queryParameters.containsKey('code')) {
          return '/reset${hoppinResetRedirectQuery(state.uri, signedIn: true)}';
        }
        return null;
      }
      if (onLogin) {
        final pending = pendingDeepLink;
        pendingDeepLink = null;
        return pending ?? '/book';
      }

      // ACTIVE-TRIP LOCK (scope B: only the ride-start surface is locked).
      // An Uber-style app is captive to the trip screen while a ride is live —
      // the rider can never reach the booking form to start a second concurrent
      // trip, whether they tab-tap, deep-link, or back out of the trip screen.
      // History/Wallet/Support/Profile stay viewable mid-trip by design.
      //
      // The active ride id is read synchronously from historyProvider's cache;
      // `tripChanges` (above) re-runs this redirect the moment that cache flips.
      // Guarded to '/book' only so it never fights the trip screen's own leaves
      // (/trip/:id/receipt|chat|call) or the other tabs.
      if (state.matchedLocation == '/book') {
        final activeId = ref.read(activeRideIdProvider);
        if (activeId != null) return '/trip/$activeId';
      }
      return null;
    },
    // PHASE 12 — the designed dead end.
    //
    // With no `errorBuilder`, go_router ships its OWN default for an
    // unresolvable path: a grey page reading "Page not found" over a raw
    // exception dump. That was live, in a consumer app, and it was REACHABLE —
    // seven `context.go` targets in `lib/` pointed at routes the table did not
    // contain (the four Profile rows, both legal links, and home's `/wallet`).
    // Phase 12 mounts all seven, so no internal navigation should land here now.
    //
    // It stays because deep links and push payloads carry paths from OUTSIDE the
    // binary, which route hygiene cannot constrain — and because the next dead
    // `context.go` anyone writes should land on a designed screen with a way
    // out, not on a stack trace.
    errorBuilder: (_, _) => const RouteNotFoundScreen(),
    routes: [
      // PHASE 11: every route is nested under one ShellRoute so that
      // `PushNavigationHost` sits INSIDE the router (it calls `context.go`, so
      // it cannot wrap the GoRouter itself) and is alive for every surface —
      // including a cold start on /login.
      //
      // It is a genuine NO-OP today: the live `fcmGatewayProvider` default is
      // `NoopFcmGateway`, whose `onMessageOpened()` is `const Stream.empty()`
      // and whose `initialMessage()` answers null. So in every test and in the
      // demo this adds one inert widget and changes nothing.
      ShellRoute(
        builder: (_, _, child) => PushNavigationHost(child: child),
        routes: [
          GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
          GoRoute(path: '/signup', builder: (_, _) => const SignupScreen()),
          GoRoute(
            path: '/verify',
            builder: (_, state) => OtpVerifyScreen(
              phone: state.uri.queryParameters['phone'] ?? '',
            ),
          ),
          // Password-reset / invite landing. Allowlisted while signed-out so
          // the emailed link can open the set-password form.
          GoRoute(
            path: '/reset',
            builder: (context, _) => ResetLandingScreen(
              onBackToSignIn: () => context.go('/login'),
            ),
          ),

          // ── The 4-tab shell ───────────────────────────────────────────
          StatefulShellRoute.indexedStack(
            builder: (_, _, navigationShell) =>
                RiderShell(navigationShell: navigationShell),
            branches: [
              StatefulShellBranch(
                routes: [
                  GoRoute(
                    path: '/book',
                    builder: (_, _) => const BookingFlow(),
                  ),
                ],
              ),
              StatefulShellBranch(
                routes: [
                  GoRoute(
                    path: '/history',
                    builder: (_, _) => const HistoryScreen(),
                  ),
                ],
              ),
              StatefulShellBranch(
                routes: [
                  // /wallet → /payments under the new shell.
                  GoRoute(
                    path: '/payments',
                    builder: (_, _) => const WalletScreen(),
                  ),
                ],
              ),
              StatefulShellBranch(
                routes: [
                  GoRoute(
                    path: '/support',
                    builder: (_, _) => const SupportScreen(),
                    routes: [
                      GoRoute(
                        path: ':ticketId',
                        builder: (_, state) => TicketScreen(
                          ticketId: state.pathParameters['ticketId']!,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),

          // ── Top-level pushes OVER the shell (no bottom nav) ────────────
          // Profile hub — reached via the top-bar avatar.
          //
          // PHASE 12: its four feature screens nest UNDER it, so back-navigation
          // from each lands on the hub for free. All four are AUTHENTICATED
          // surfaces and are NOT in the signed-out allowlist above — a signed-out
          // visit to any `/profile/*` bounces to /login (pinned by test).
          GoRoute(
            path: '/profile',
            builder: (_, _) => const ProfileScreen(),
            routes: [
              // ACCT-02 / seam #70 — read-only over the four facts the session
              // genuinely holds. Save is visible and inert.
              GoRoute(
                path: 'personal',
                builder: (_, _) => const PersonalInfoScreen(),
              ),
              // ACCT-03 / seam #71 — seven inert switches under ONE rung, and
              // the theme toggle, which is the one control that does what it
              // says. Hosts the seam-#73 deletion popup.
              GoRoute(
                path: 'settings',
                builder: (_, _) => const SettingsScreen(),
              ),
              // ACCT-04 / seam #72 — half-real and visibly so: the BOUND /ads
              // banners above, the permanently-null promo-codes rung below.
              GoRoute(
                path: 'promotions',
                builder: (_, _) => const PromotionsScreen(),
              ),
              // SUPPORT-01 / Figma #38 — FAQ + contact + legal. NOT the ticket
              // tab. The hub's "Help & Support" row pointed at `/support` for
              // the app's entire life, which is why nobody noticed this screen
              // had never been built: the row LOOKED wired.
              GoRoute(
                path: 'help',
                builder: (_, _) => const HelpSupportScreen(),
              ),
            ],
          ),

          // ── COMPLY-01 — the legal surfaces. ALLOWLISTED PRE-LOGIN (see the
          //    redirect above). The consent notice on SIGNUP links here, so a
          //    login gate would kill the link exactly when it matters most.
          GoRoute(
            path: '/legal/privacy',
            builder: (_, _) => const PrivacyNoticeScreen(),
          ),
          GoRoute(
            path: '/legal/terms',
            builder: (_, _) => const TermsScreen(),
          ),
          // The notification centre (NOTIF-02) — reached from the shell bell,
          // and the fallback target for any push whose `type` we do not know.
          // History is SEAMED (#68): the centre discloses that older history
          // cannot be READ; it never asserts there is none.
          GoRoute(
            path: kNotificationCentreRoute,
            builder: (_, _) => const NotificationCentreScreen(),
          ),
          GoRoute(
            path: '/places',
            builder: (_, _) => const SavedLocationsScreen(),
          ),
          // Scheduled rides (BOOK-03) — the date/time picker list, reached
          // from the Book screen's "Schedule Ride" segment.
          GoRoute(
            path: '/scheduled',
            builder: (_, _) => const ScheduledScreen(),
          ),
          GoRoute(
            path: '/contacts',
            builder: (_, _) => const EmergencyContactsScreen(),
          ),
          GoRoute(
            path: '/safety',
            builder: (_, state) => SafetyScreen(
              rideId: state.uri.queryParameters['rideId'],
            ),
          ),
          GoRoute(
            path: '/trip/:id',
            builder: (_, state) =>
                TripScreen(rideId: state.pathParameters['id']!),
            routes: [
              GoRoute(
                path: 'receipt',
                builder: (_, state) =>
                    ReceiptScreen(rideId: state.pathParameters['id']!),
              ),
              GoRoute(
                path: 'chat',
                builder: (_, state) =>
                    ChatScreen(rideId: state.pathParameters['id']!),
              ),
              // COMMS-02, seam #45. The inert masked-call surface — a sibling
              // of chat and receipt, reached from the trip screen's distinct
              // `phone_outlined` affordance and from MatchedDriverCard.onCall.
              // It NEVER dials.
              GoRoute(
                path: 'call',
                builder: (_, state) =>
                    CallScreen(rideId: state.pathParameters['id']!),
              ),
            ],
          ),
        ],
      ),
    ],
  );
});

/// A [ChangeNotifier] whose notification is pokable from outside — go_router's
/// refreshListenable needs an external signal (a Riverpod history change) to
/// fire it, but `notifyListeners` is `@protected`. This exposes a public [poke]
/// so the router's history subscription can drive the active-trip-lock refresh.
class _PokableNotifier extends ChangeNotifier {
  void poke() => notifyListeners();
}
