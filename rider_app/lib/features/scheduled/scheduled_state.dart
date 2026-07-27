import 'package:flutter/foundation.dart';
import 'package:hoppin_shared/hoppin_shared.dart';

/// Where the scheduled-rides surface currently is.
enum ScheduledPhase {
  /// Nothing loaded yet.
  idle,

  /// A `GET /scheduled-rides` read or a `POST /scheduled-rides` write is in
  /// flight.
  loading,

  /// The list is loaded / a create landed — `rides` holds the current set.
  ready,

  /// A read/write failed — `error` holds a display-ready message.
  error,
}

/// Immutable snapshot of the scheduled riblet (riblet anatomy, DOCS/05). One
/// class + a phase enum, the BookingState shape mirrored.
@immutable
class ScheduledState {
  const ScheduledState({
    this.phase = ScheduledPhase.idle,
    this.rides = const [],
    this.error,
  });

  final ScheduledPhase phase;

  /// The rider's scheduled rides — `GET /scheduled-rides`, as loaded.
  final List<ScheduledRide> rides;

  /// Set when [phase] == [ScheduledPhase.error]; always the friendly message,
  /// never a raw API body (gap #22 500 must never reach the rider).
  final String? error;

  /// Sentinel that lets [copyWith] distinguish "not passed" from "set null".
  static const Object _unset = Object();

  ScheduledState copyWith({
    ScheduledPhase? phase,
    List<ScheduledRide>? rides,
    Object? error = _unset,
  }) {
    return ScheduledState(
      phase: phase ?? this.phase,
      rides: rides ?? this.rides,
      error: identical(error, _unset) ? this.error : error as String?,
    );
  }
}
