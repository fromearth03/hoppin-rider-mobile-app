import 'api_exception.dart';

/// Fallback copy for the codes a RIDER can reach.
///
/// Derived by reading the handlers in `Go_ride_service` — there is no
/// rider-side error reference from the backend (the one they wrote covers the
/// driver app). Source lines are cited so a claim here can be re-checked.
///
/// **This is a fallback, not the primary copy.** The server sends a message with
/// every error and that message is what the user sees. These strings cover the
/// case where the envelope is missing or malformed — a proxy error page, a
/// truncated response, a 502 from something in front of the service.
class RiderErrorCopy {
  RiderErrorCopy._();

  /// Codes a rider JWT can actually reach. `VEHICLE_CATEGORY_MISMATCH` is
  /// deliberately absent: it fires only on driver accept/arrive, despite the
  /// backend's driver-facing doc listing it as rider-reachable.
  static const _copy = <String, String>{
    // Booking guards — ride_handler.go:830-844
    'ACCOUNT_NOT_ELIGIBLE': 'Your account cannot book a ride right now.',
    'ACTIVE_TRIP_EXISTS': 'You already have a trip in progress.',
    'OUTSIDE_SERVICE_AREA': 'Hoppin is not available at this pickup location.',
    'NO_PAYMENT_METHOD': 'Add a payment card to book a ride.',
    'NO_ZONE': 'We do not have pricing for this pickup point yet.',
    'NO_TARIFF': 'Pricing is unavailable here right now. Try again shortly.',
    'IDEMPOTENT_REPLAY': 'This booking has already been submitted.',

    // Promotions — chat_handler.go:227-248
    'PROMO_NOT_FOUND': 'That promo code was not found.',
    'PROMO_INACTIVE': 'That promo code is not currently active.',
    'PROMO_EXHAUSTED': 'That promo code has reached its usage limit.',
    'PROMO_USED': 'That promo code has already been used.',
    'PROMO_INELIGIBLE': 'This ride is not eligible for a promo.',
    'PROMO_NOT_FOR_RIDERS': 'That promo code cannot be used on a ride.',
    'PROMO_NO_FARE': 'The fare is not final yet, so a promo cannot be applied.',
    'PROMO_MIN_RIDE': "This ride is below the promo's minimum fare.",
    'PROMO_NEW_USERS_ONLY': 'That promo is for new riders only.',
    'PROMO_BUDGET_EXHAUSTED': 'That promo campaign has ended.',
    // A code can be scoped to a zone. /promotions/validate has no pickup
    // context, so a code may validate and still fail here — handle both.
    'PROMO_WRONG_ZONE': "This code isn't available in your pickup area.",

    // Live map — a rider hits these while watching a trip
    'NO_DRIVER_ASSIGNED': 'Still finding you a driver.',
    'RIDE_NOT_ACTIVE': 'This trip is no longer active.',
    'POSITION_UNAVAILABLE': "We cannot see the driver's position yet.",
    'SHARE_LINK_INVALID': 'This tracking link is no longer active.',

    // Supabase auth — mapped from GoTrue's structured error codes
    'WEAK_PASSWORD': 'Choose a stronger password.',
    'EMAIL_TAKEN': 'An account with that email already exists.',
    'INVALID_CREDENTIALS': 'That email or password is not right.',
    'TOO_MANY_ATTEMPTS': 'Too many attempts. Wait a moment and try again.',
    'EXPIRED_LINK': 'That link has expired. Request a new one.',
    'AUTH_FAILED': 'We could not sign you in. Try again.',

    // Account / session — auth gates
    'SESSION_REPLACED': 'You signed in on another device.',
    'ACCOUNT_SUSPENDED': 'Your account is suspended. Contact support.',
    'ACCOUNT_BANNED': 'Your account has been closed. Contact support.',
    'DEVICE_BLACKLISTED': 'This device has been blocked. Contact support.',
    'DEVICE_STATUS_UNAVAILABLE':
        'We could not verify this device. Try again in a moment.',
    'DELETION_BLOCKED': 'Your account cannot be deleted yet.',
    'PHONE_TAKEN': 'That phone number is already in use.',
    'USER_NOT_FOUND': 'We could not find your profile.',

    // Global
    'VALIDATION_FAILED': 'Something in that request was not valid.',
    'FORBIDDEN': 'You do not have access to that.',
    'NOT_FOUND': 'That could not be found.',
    'RIDE_NOT_FOUND': 'That trip no longer exists.',
    'INTERNAL': 'Something went wrong on our side. Try again.',
    'STORAGE_DISABLED': 'Uploads are unavailable right now.',
  };

  /// The message to show. Server copy wins; this is the safety net.
  static String messageFor(ApiException e) {
    final server = e.message.trim();
    if (server.isNotEmpty) return server;
    return _copy[e.code] ?? 'Something went wrong. Try again.';
  }

  /// Fallback copy for a code, ignoring any server message. For tests and for
  /// the rare screen that needs the generic phrasing.
  static String? forCode(String code) => _copy[code];
}
