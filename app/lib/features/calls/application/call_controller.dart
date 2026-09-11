import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:livekit_client/livekit_client.dart';

import '../../../core/result.dart';
import '../data/calls_repository.dart';
import 'call_tones.dart';

/// Where a call is. `ringing` is an outgoing call waiting for an answer;
/// `incoming` is one ringing on this phone.
enum CallPhase {
  idle,
  placing,
  ringing,
  incoming,
  connecting,
  connected,
  reconnecting,
  ended,
}

class CallState {
  final CallPhase phase;
  final String? callId;
  final String? rideId;
  final String peerName;
  final String peerRole;
  final bool muted;
  final bool speaker;
  final DateTime? connectedAt;

  /// Why the call ended, in words the rider can read.
  final String? endReason;

  const CallState({
    required this.phase,
    this.callId,
    this.rideId,
    this.peerName = '',
    this.peerRole = 'driver',
    this.muted = false,
    this.speaker = false,
    this.connectedAt,
    this.endReason,
  });

  const CallState.idle() : this(phase: CallPhase.idle);

  bool get isActive => phase != CallPhase.idle && phase != CallPhase.ended;

  CallState copyWith({
    CallPhase? phase,
    String? callId,
    String? peerName,
    String? peerRole,
    bool? muted,
    bool? speaker,
    DateTime? connectedAt,
    String? endReason,
  }) => CallState(
    phase: phase ?? this.phase,
    callId: callId ?? this.callId,
    rideId: rideId,
    peerName: peerName ?? this.peerName,
    peerRole: peerRole ?? this.peerRole,
    muted: muted ?? this.muted,
    speaker: speaker ?? this.speaker,
    connectedAt: connectedAt ?? this.connectedAt,
    endReason: endReason ?? this.endReason,
  );
}

/// Runs one in-app call at a time: places or answers it through the backend,
/// joins the call's LiveKit room, and turns room events and pushes into a
/// state the call screen draws.
///
/// The audio never touches Hoppin's backend. The backend only issues the ticket
/// that admits this phone to the room and rings the other one; LiveKit carries
/// the voices. No phone numbers are involved at any point.
class CallController extends Notifier<CallState> {
  /// Backend rings for 45 s; a little longer here so its verdict arrives first.
  static const _ringFallback = Duration(seconds: 50);

  Room? _room;
  EventsListener<RoomEvent>? _listener;
  Timer? _ringTimer;
  Timer? _poll;
  Timer? _reset;
  bool _hangingUp = false;
  bool _viaCallKit = false;

  @override
  CallState build() {
    ref.onDispose(_teardown);
    return const CallState.idle();
  }

  CallsRepository get _repo => ref.read(callsRepositoryProvider);

  /// Rings the driver on [rideId].
  Future<void> placeCall(String rideId, {String peerName = ''}) async {
    if (state.isActive) return;
    _begin(
      CallState(phase: CallPhase.placing, rideId: rideId, peerName: peerName),
    );
    final res = await _repo.start(rideId);
    switch (res) {
      case Err(:final error):
        _finish(
          CallsRepository.liveCallIdOf(error) != null
              ? 'A call with your driver is already in progress'
              : _friendly(error.code, error.message),
        );
      case Ok(:final value):
        state = state.copyWith(
          phase: CallPhase.ringing,
          callId: value.callId,
          peerName: value.peerName,
          peerRole: value.peerRole,
        );
        // Only a fallback: the backend decides when a call has rung out and
        // says so (push, and the 3 s poll). Counted on this phone's own clock,
        // never from rings_until — that is the server's wall-clock time, and a
        // server clock 40 s slow turned every call into "No answer" after ~5 s.
        _ringTimer = Timer(_ringFallback, () {
          if (state.phase == CallPhase.ringing) _endLocally('No answer');
        });
        _pollWhileRinging();
        await _join(value, answered: false);
    }
  }

  /// Answers [callId], which is ringing on this phone.
  Future<void> acceptIncoming(
    String callId, {
    String peerName = '',
    bool viaCallKit = false,
  }) async {
    if (state.isActive && state.callId != callId) {
      return; // already on another call
    }
    _viaCallKit = viaCallKit;
    _begin(
      CallState(
        phase: CallPhase.connecting,
        callId: callId,
        peerName: peerName,
      ),
    );
    final res = await _repo.accept(callId);
    switch (res) {
      case Err(:final error):
        if (viaCallKit) unawaited(FlutterCallkitIncoming.endCall(callId));
        _finish(
          error.code == 'CALL_NOT_RINGING'
              ? 'The call had already ended'
              : _friendly(error.code, error.message),
        );
      case Ok(:final value):
        state = state.copyWith(
          peerName: value.peerName,
          peerRole: value.peerRole,
        );
        await _join(value, answered: true);
    }
  }

  /// Turns down [callId]; the driver is told at once rather than left to
  /// listen to it ring out.
  Future<void> declineIncoming(String callId) async {
    unawaited(FlutterCallkitIncoming.endCall(callId));
    await _repo.decline(callId);
  }

  Future<void> hangUp() => _endLocally('Call ended');

  Future<void> toggleMute() async {
    final mute = !state.muted;
    await _room?.localParticipant?.setMicrophoneEnabled(!mute);
    state = state.copyWith(muted: mute);
  }

  Future<void> toggleSpeaker() async {
    final on = !state.speaker;
    await AudioManager.instance.setSpeakerOutputPreferred(on);
    state = state.copyWith(speaker: on);
  }

  /// A push about the current call: declined, rang out, or given up on.
  void onSignal(Map<String, dynamic> data) {
    if (data['call_id'] != state.callId || !state.isActive) return;
    switch (data['type']) {
      case 'call_declined':
        _endLocally('Declined');
      case 'call_unanswered':
        _endLocally('No answer');
      case 'call_cancelled':
      case 'call_missed':
        _endLocally('Missed call');
    }
  }

  Future<void> _join(CallTicket t, {required bool answered}) async {
    final room = Room(
      roomOptions: const RoomOptions(adaptiveStream: false, dynacast: false),
    );
    _room = room;
    _listener = room.createListener()
      ..on<ParticipantConnectedEvent>((_) => _peerJoined())
      ..on<ParticipantDisconnectedEvent>((_) {
        // A two-person call is over the moment the other person leaves.
        if (state.phase == CallPhase.connected ||
            state.phase == CallPhase.reconnecting) {
          _endLocally('Call ended');
        }
      })
      ..on<RoomReconnectingEvent>((_) {
        if (state.phase == CallPhase.connected) {
          state = state.copyWith(phase: CallPhase.reconnecting);
        }
      })
      ..on<RoomReconnectedEvent>((_) {
        if (state.phase == CallPhase.reconnecting) {
          state = state.copyWith(phase: CallPhase.connected);
        }
      })
      ..on<RoomDisconnectedEvent>((_) {
        if (!_hangingUp && state.isActive) _endLocally('Call dropped');
      });
    // Three steps, three outcomes. Only the first two can sink a call: an
    // earpiece/speaker preference the platform refuses must not hang up a
    // call that has already connected (it did exactly that on Android — the
    // phone joined, published its mic, then called it "couldn't connect").
    try {
      await room.connect(t.url, t.token);
    } catch (e) {
      await _endLocally(_why("Couldn't reach the call server", e));
      return;
    }
    try {
      // The microphone permission is asked for here, the first time.
      await room.localParticipant?.setMicrophoneEnabled(true);
    } catch (e) {
      await _endLocally(
        _why('Microphone unavailable. Allow it for Hoppin in Settings.', e),
      );
      return;
    }
    try {
      await AudioManager.instance.setSpeakerOutputPreferred(false);
    } catch (e) {
      debugPrint(
        'calls: earpiece preference refused, using default output: $e',
      );
    }
    // Ringback ("brr-brr … brr-brr") until they pick up. Started only now,
    // once joining has put the phone into call-audio mode: started before, the
    // mode switch cut it and the caller heard nothing.
    if (!answered &&
        state.phase == CallPhase.ringing &&
        room.remoteParticipants.isEmpty) {
      unawaited(CallTones.ringback());
    }
    // Answering joins a room the caller is already waiting in.
    if (answered || room.remoteParticipants.isNotEmpty) _peerJoined();
  }

  void _peerJoined() {
    if (state.phase == CallPhase.connected) return;
    _ringTimer?.cancel();
    _poll?.cancel();
    unawaited(CallTones.stop());
    state = state.copyWith(
      phase: CallPhase.connected,
      connectedAt: DateTime.now(),
    );
    final id = state.callId;
    if (_viaCallKit && id != null) {
      unawaited(FlutterCallkitIncoming.setCallConnected(id));
    }
  }

  /// Pushes can be late or lost, so an outgoing call also asks the backend
  /// every few seconds whether the driver declined or it rang out.
  void _pollWhileRinging() {
    _poll = Timer.periodic(const Duration(seconds: 3), (_) async {
      final id = state.callId;
      if (id == null || state.phase != CallPhase.ringing) return;
      final res = await _repo.status(id);
      if (res case Ok(:final value)) {
        switch (value.status) {
          case 'declined':
            _endLocally('Declined');
          case 'missed':
            _endLocally('No answer');
          case 'cancelled' || 'failed' || 'ended':
            _endLocally('Call ended');
        }
      }
    });
  }

  Future<void> _endLocally(String reason) async {
    if (!state.isActive) return;
    final id = state.callId;
    _hangingUp = true;
    // Busy beeps when the other side declined or never picked up; silence
    // for everything else, including hanging up yourself.
    unawaited(
      reason == 'Declined' || reason == 'No answer'
          ? CallTones.busy()
          : CallTones.stop(),
    );
    await _teardownRoom();
    if (id != null) {
      unawaited(
        _repo.end(id),
      ); // idempotent; tells the backend and the other phone
      if (_viaCallKit) unawaited(FlutterCallkitIncoming.endCall(id));
    }
    _finish(reason);
  }

  void _begin(CallState s) {
    _reset?.cancel();
    _hangingUp = false;
    state = s;
  }

  void _finish(String reason) {
    _ringTimer?.cancel();
    _poll?.cancel();
    state = state.copyWith(phase: CallPhase.ended, endReason: reason);
    final ended = state;
    // A failure carries its error on a second line; leave it up long enough
    // to read or screenshot.
    _reset = Timer(Duration(seconds: reason.contains('\n') ? 6 : 2), () {
      if (identical(state, ended)) state = const CallState.idle();
    });
  }

  Future<void> _teardownRoom() async {
    _listener?.dispose();
    _listener = null;
    final room = _room;
    _room = null;
    if (room != null) {
      try {
        await room.disconnect();
        await room.dispose();
      } catch (_) {}
    }
  }

  void _teardown() {
    unawaited(CallTones.stop());
    _ringTimer?.cancel();
    _poll?.cancel();
    _reset?.cancel();
    unawaited(_teardownRoom());
  }

  /// [reason] plus the underlying error, so a failed call can be diagnosed
  /// from a screenshot of the ended screen.
  static String _why(String reason, Object e) {
    final detail = e.toString();
    return '$reason\n${detail.length > 90 ? '${detail.substring(0, 90)}…' : detail}';
  }

  static String _friendly(String code, String message) => switch (code) {
    'RIDE_NOT_CALLABLE' =>
      'You can call your driver once they have accepted the ride.',
    'NO_DRIVER_ASSIGNED' => 'No driver yet — you can call once one accepts.',
    'FORBIDDEN' => 'This call is not available.',
    _ => message.isNotEmpty ? message : "Couldn't place the call",
  };
}

final callControllerProvider = NotifierProvider<CallController, CallState>(
  CallController.new,
);
