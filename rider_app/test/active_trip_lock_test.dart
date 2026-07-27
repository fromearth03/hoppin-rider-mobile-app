import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoppin_rider/providers.dart';
import 'package:hoppin_shared/hoppin_shared.dart';

/// Root-cause probe for the active-trip lock. The router redirect reads
/// [activeRideIdProvider], which derives synchronously from [historyProvider]'s
/// cache. If this returns null when a live trip exists, the redirect can never
/// fire and the rider is left on the Book shell — the demo bug.
void main() {
  Ride ride(String id, RideStatus status) =>
      Ride(id: id, riderId: 'rider-1', status: status);

  ProviderContainer containerWith(List<Ride> history) {
    final c = ProviderContainer(
      overrides: [
        ridesRepositoryProvider.overrideWithValue(_StubRides(history)),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  test('surfaces the live ride once history resolves', () async {
    final c = containerWith([ride('ride-1', RideStatus.accepted)]);
    await c.read(historyProvider.future);
    expect(c.read(activeRideIdProvider), 'ride-1');
  });

  test('is null before history resolves (the redirect-race window)', () {
    final c = containerWith([ride('ride-1', RideStatus.accepted)]);
    // No await: history is still loading. This is the exact instant the rider
    // first lands on /book — if the redirect reads here, it sees null.
    expect(c.read(activeRideIdProvider), isNull);
  });

  test('is null when the only ride is terminal', () async {
    final c = containerWith([ride('ride-1', RideStatus.completed)]);
    await c.read(historyProvider.future);
    expect(c.read(activeRideIdProvider), isNull);
  });
}

class _StubRides implements RidesRepository {
  _StubRides(this._history);
  final List<Ride> _history;
  @override
  Future<List<Ride>> history({int limit = 50}) async => _history;
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}
