import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:hoppin_shared/hoppin_shared.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'features/notifications/fcm_gateway.dart';
import 'features/notifications/firebase_fcm_gateway.dart';
import 'package:flutter_stripe/flutter_stripe.dart';

import 'features/payments/stripe_sdk_gateway.dart';
import 'features/payments/web_stripe_gateway.dart';
import 'features/profile/platform_avatar_picker.dart';
import 'router.dart';
import 'url_strategy_stub.dart'
    if (dart.library.html) 'url_strategy_web.dart';

/// Entry point for the Hoppin RIDER app.
///
/// Run (once the Flutter SDK is installed):
///   flutter run \
///     --dart-define=SUPABASE_URL=... \
///     --dart-define=SUPABASE_ANON_KEY=... \
///     --dart-define=RIDE_SERVICE_URL=http://localhost:8080/api/v1
///
/// Push (NOTIF-01) is OPTIONAL and OFF by default. To enable it, add the five
/// FCM defines (FCM_API_KEY / FCM_PROJECT_ID / FCM_SENDER_ID / FCM_APP_ID /
/// FCM_VAPID_KEY). Without them the app boots on the 3s poll floor, exactly as
/// it does today — push is ADDITIVE, never a boot dependency.
Future<void> main() async {
  hoppinCaptureAuthLink();
  WidgetsFlutterBinding.ensureInitialized();
  Env.assertConfigured();

  // Supabase must be initialised before any provider touches the client.
  await Supabase.initialize(
    url: Env.supabaseUrl,
    publishableKey: Env.supabaseAnonKey,
  );
  // After GoTrue has read `#access_token=` / `?code=` from the bar.
  hoppinUsePathUrlStrategy();

  // ── FCM boot: GATED ──────────────────────────────────────────────────────
  // The ONLY Firebase.initializeApp() in the repository.
  //
  // With no dart-defines (today's reality) this whole block is skipped,
  // firebase_core is never initialised, and the app runs on the 3s poll floor
  // with the NoopFcmGateway default.
  //
  // 🔴 THE TRAP: on web an unconfigured initializeApp() throws a bare
  // `TypeError`, NOT a `FirebaseException`. `on FirebaseException catch` does
  // NOT catch it, and an unguarded `await` here — before runApp() — WHITE-SCREENS
  // the app. So there are two guards: the compile-time Env.fcmConfigured flag
  // (primary), and a bare `catch (_)` (backstop). Never narrow that catch.
  // The camera/gallery seam for the profile photo. `hoppin_shared` ships no
  // default (it must not depend on a platform plugin), so the app supplies the
  // real picker here and tests inject a fake.
  final overrides = <Override>[
    avatarPickerProvider.overrideWithValue(PlatformAvatarPicker()),
  ];

  // Card entry: GATED on a Stripe publishable key. With it, wire the real
  // web gateway (Stripe CardField + confirmSetupIntent); without it the app
  // keeps the honest 'card payments coming soon' no-op.
  if (Env.stripeConfigured) {
    Stripe.publishableKey = Env.stripePublishableKey;
    overrides.add(
      stripeGatewayProvider
          .overrideWithValue(WebStripeGateway(rootNavigatorKey)),
    );
  }
  if (Env.fcmConfigured || !kIsWeb) {
    try {
      if (Env.fcmConfigured) {
        await Firebase.initializeApp(
          options: const FirebaseOptions(
            apiKey: Env.fcmApiKey,
            appId: Env.fcmAppId,
            messagingSenderId: Env.fcmSenderId,
            projectId: Env.fcmProjectId,
          ),
        );
      } else {
        await Firebase.initializeApp();
      }
      overrides.add(
        fcmGatewayProvider.overrideWithValue(const FirebaseFcmGateway()),
      );
    } catch (_) {
      // Any init failure — bad config, a refused service worker, Safari —
      // degrades to the no-op. Push is additive; it may NEVER stop the app.
    }
  }

  // ProviderScope is the Riverpod root — it holds all provider state.
  runApp(ProviderScope(
    retry: (retryCount, error) => null,
    overrides: overrides,
    child: const RiderApp(),
  ));
}
