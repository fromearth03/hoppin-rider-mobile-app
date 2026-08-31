import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/config.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Fail loudly and early. Without config every call fails later with an
  // opaque error, which is far harder to diagnose than a missing --dart-define.
  final missing = AppConfig.missingReason;
  if (missing != null) {
    runApp(_ConfigError(message: missing));
    return;
  }

  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    publishableKey: AppConfig.supabaseAnonKey,
  );

  // flutter_stripe has no web platform implementation in the version this
  // app depends on - CardField is only ever shown on mobile (see
  // payment_methods_screen.dart), so initialising the SDK on web would just
  // be dead weight. A missing key on mobile is handled by the payment
  // methods screen disabling "Add card" and explaining why, rather than
  // failing here - every other screen must keep working even if payments
  // cannot be set up.
  if (!kIsWeb && AppConfig.stripePublishableKey.isNotEmpty) {
    Stripe.publishableKey = AppConfig.stripePublishableKey;
    await Stripe.instance.applySettings();
  }

  runApp(const ProviderScope(child: HoppinApp()));
}

class _ConfigError extends StatelessWidget {
  final String message;
  const _ConfigError({required this.message});

  @override
  Widget build(BuildContext context) => MaterialApp(
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Text(message, textAlign: TextAlign.center),
            ),
          ),
        ),
      );
}
