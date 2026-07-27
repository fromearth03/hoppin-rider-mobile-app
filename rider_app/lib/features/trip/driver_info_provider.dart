import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hoppin_shared/hoppin_shared.dart';

/// Driver identity + telemetry for one ride via the DEMO-07 capability seam.
///
/// Null data is a VALID resolved state, not an error: the live backend
/// serves no driver-identity endpoint yet, so [RidesRepository.driverInfo]
/// answers null and consumers render the graceful fallback. The demo
/// composition overrides the repository, never this provider.
final driverInfoProvider =
    FutureProvider.autoDispose.family<RideDriverInfo?, String>(
  (ref, rideId) => ref.watch(ridesRepositoryProvider).driverInfo(rideId),
);
