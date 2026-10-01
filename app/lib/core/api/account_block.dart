import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_exception.dart';

/// The codes that mean this rider or this phone may not use Hoppin at all
/// right now. Any request answered with one of them puts the whole app behind
/// the block screen (AppGate), rather than leaving the rider on a screen where
/// every button fails with a toast.
const accountBlockCodes = {
  'DEVICE_BLACKLISTED',
  'ACCOUNT_SUSPENDED',
  'ACCOUNT_BANNED',
};

/// The block the server last reported, or null. Cleared by "Try again" and by
/// signing out.
final accountBlockProvider = StateProvider<ApiException?>((ref) => null);
