/// Build-time configuration, supplied with `--dart-define-from-file`.
///
/// `String.fromEnvironment` is a compile-time constant: the values are baked
/// into the binary, so there is no config file inside the bundle for anyone to
/// extract. See `config/README.md` for why that matters and how to run.
class AppConfig {
  AppConfig._();

  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  static const stripePublishableKey =
      String.fromEnvironment('STRIPE_PUBLISHABLE_KEY');
  static const sentryDsn = String.fromEnvironment('SENTRY_DSN');

  static const apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://api.hoppin.tech/api/v1',
  );

  /// Whether the app has enough configuration to reach Supabase at all.
  /// Checked at startup so a missing --dart-define fails with a clear message
  /// rather than an opaque error on the first sign-in attempt.
  static bool get hasSupabase =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  /// Human-readable reason the config is unusable, or null when it is fine.
  static String? get missingReason {
    if (supabaseUrl.isEmpty && supabaseAnonKey.isEmpty) {
      return 'No configuration supplied. Run with '
          '--dart-define-from-file=config/dev.json';
    }
    if (supabaseUrl.isEmpty) return 'SUPABASE_URL is missing.';
    if (supabaseAnonKey.isEmpty) return 'SUPABASE_ANON_KEY is missing.';
    return null;
  }
}
