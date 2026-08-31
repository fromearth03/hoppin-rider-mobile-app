import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
