/// One failed call, in the shape the ride service actually returns:
/// `{"error": "<message>", "code": "<CODE>"}`.
///
/// Match on [code]. Display [message] — it is server-owned copy and some codes
/// carry two unrelated meanings that only the message distinguishes
/// (`ACCOUNT_NOT_ELIGIBLE` is both "account is not active" and "riders must be
/// 13 or older"). Synthesising copy from the code alone would tell a suspended
/// rider they are too young.
class ApiException implements Exception {
  final String code;

  /// Server-owned. Safe to show; never rewrite it.
  final String message;

  final int status;

  /// Extra top-level keys some codes add — `blockers` on `DELETION_BLOCKED`,
  /// `seconds` on `NO_SHOW_TOO_EARLY`, `reason` on `NOT_ELIGIBLE`. Preserved
  /// rather than dropped so a screen can use them without a second call.
  final Map<String, dynamic> fields;

  const ApiException(
    this.code,
    this.message,
    this.status, {
    this.fields = const {},
  });

  /// True when retrying the identical request could plausibly succeed.
  /// Everything else needs the underlying state to change first, so an
  /// automatic retry would only burn battery.
  bool get isRetryable => switch (code) {
        'INTERNAL' => true,
        'STORAGE_DISABLED' => true,
        'DEVICE_STATUS_UNAVAILABLE' => true,
        'POSITION_UNAVAILABLE' => true,
        'NO_DRIVER_ASSIGNED' => true,
        _ => false,
      };

  /// The session is gone and cannot be refreshed — sign out, do not retry.
  bool get isTerminalAuth => switch (code) {
        'SESSION_REPLACED' => true,
        'ACCOUNT_SUSPENDED' => true,
        'ACCOUNT_BANNED' => true,
        'DEVICE_BLACKLISTED' => true,
        _ => false,
      };

  @override
  String toString() => 'ApiException($code, $status): $message';
}
