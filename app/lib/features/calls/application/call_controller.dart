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

  /// Where a call to Hoppin support stands in the queue while it waits for a
  /// free team member (1 = next). 0 when not known or not queued.
  final int queuePosition;

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
    this.queuePosition = 0,
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
    int? queuePosition,
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
    queuePosition: queuePosition ?? this.queuePosition,
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
  /// A call to support waits in a queue for longer: the ticket says how long.
  static const _ringFallback = Duration(seconds: 50);

  static Duration _fallbackFor(CallTicket t) =>
      t.waitSeconds > 0 ? Duration(seconds: t.waitSeconds + 10) : _ringFallback;

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
  Future<void> placeCall(String rideId, {String peerName = ''}) =>
      _placeOutgoing(
        CallState(phase: CallPhase.placing, rideId: rideId, peerName: peerName),
        () => _repo.start(rideId),
        inProgress: 'A call with your driver is already in progress',
      );

  /// Rings Hoppin support. Whoever on the Hoppin team answers first takes it;
  /// [sosId] and [rideId] tell them what it is about.
  Future<void> placeSupportCall({String? sosId, String? rideId}) =>
      _placeOutgoing(
        CallState(
          phase: CallPhase.placing,
          rideId: rideId,
          peerName: supportName,
          peerRole: 'support',
        ),
        () => _repo.callSupport(sosId: sosId, rideId: rideId),
        inProgress: 'You are already on a call with Hoppin Support',
      );

  static const supportName = 'Hoppin Support';

  /// What an unanswered call says. Support is a team, not a person who "did
  /// not answer", so it gets its own wording.
  String get _noAnswer => state.peerRole == 'support'
      ? 'No one from support was free. We will call you back as soon as we can.'
      : 'No answer';

  Future<void> _placeOutgoing(
    CallState initial,
    Future<Result<CallTicket>> Function() start, {
    required String inProgress,
  }) async {
    if (state.isActive) return;
    _begin(initial);
    final res = await start();
    switch (res) {
      case Err(:final error):
        _finish(
          CallsRepository.liveCallIdOf(error) != null
              ? inProgress
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
        _ringTimer = Timer(_fallbackFor(value), () {
          if (state.phase == CallPhase.ringing) _endLocally(_noAnswer);
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

  /// A call ringing this phone while the app is open (Android). It goes
  /// straight onto Hoppin's own call screen with Answer and Decline, and the
  /// phone rings, the moment the push arrives: no system notification to wait
  /// for. In the background or when closed, the native call screen rings
  /// instead (see call_push.dart).
  void showIncoming(Map<String, dynamic> data) {
    final id = data['call_id'] as String?;
    if (id == null || id.isEmpty) return;
    if (state.isActive) return; // on another call: this one rings out
    final role = switch (data['caller_role']) {
      'support' => 'support',
      'driver' => 'driver',
      _ => 'rider',
    };
    final name = (data['caller_name'] as String?)?.trim() ?? '';
    _viaCallKit = false;
    _begin(
      CallState(
        phase: CallPhase.incoming,
        callId: id,
        rideId: data['ride_id'] as String?,
        peerName: role == 'support'
            ? supportName
            : (name.isNotEmpty
                  ? name
                  : (role == 'driver' ? 'Your driver' : 'Your rider')),
        peerRole: role,
      ),
    );
    unawaited(CallTones.ring());
    // The backend stops it sooner with a call_cancelled / call_missed push.
    _ringTimer = Timer(_ringFallback, () {
      if (state.phase == CallPhase.incoming) {
        unawaited(CallTones.stop());
        _finish('Missed call');
      }
    });
  }

  /// Answer pressed on Hoppin's own incoming-call screen.
  Future<void> answerShown() async {
    final id = state.callId;
    if (state.phase != CallPhase.incoming || id == null) return;
    _ringTimer?.cancel();
    await CallTones.stop();
    await acceptIncoming(id, peerName: state.peerName);
  }

  /// Decline pressed on Hoppin's own incoming-call screen.
  Future<void> declineShown() async {
    final id = state.callId;
    if (state.phase != CallPhase.incoming || id == null) return;
    _ringTimer?.cancel();
    unawaited(CallTones.stop());
    _finish('Call declined');
    await _repo.decline(id);
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
    // LiveKit's own preference (forced, so a paired watch or car does not
    // win over the loudspeaker), then the actual route. On Android the
    // second step is what moves the sound: a call answered from the call
    // notification belongs to Android's Telecom, which ignored the first.
    try {
      await AudioManager.instance.setSpeakerOutputPreferred(on, force: on);
    } catch (e) {
      debugPrint('calls: speaker preference refused: $e');
    }
    await CallTones.speaker(state.callId, on);
    state = state.copyWith(speaker: on);
  }

  /// A push about the current call: declined, rang out, or given up on.
  void onSignal(Map<String, dynamic> data) {
    if (data['call_id'] != state.callId || !state.isActive) return;
    switch (data['type']) {
      case 'call_declined':
        _endLocally('Declined');
      case 'call_unanswered':
        _endLocally(_noAnswer);
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
    // Screen off at the ear, like a phone call (native ignores it on speaker).
    unawaited(CallTones.proximity(true));
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
        if (value.status == 'ringing' &&
            value.queuePosition != state.queuePosition) {
          state = state.copyWith(queuePosition: value.queuePosition);
        }
        switch (value.status) {
          case 'declined':
            _endLocally('Declined');
          case 'missed':
            _endLocally(_noAnswer);
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
      reason == 'Declined' || reason == _noAnswer
          ? CallTones.busy()
          : CallTones.stop(),
    );
    // The screen closes FIRST. Waiting for the room to disconnect before
    // closing left the call screen stuck after a hang-up whenever that
    // disconnect stalled (a weak connection, or Android's Telecom still
    // holding the call). The backend and the other phone are told at once;
    // the room is torn down in the background, bounded so it cannot hang.
    _finish(reason);
    if (id != null) {
      unawaited(_repo.end(id)); // idempotent; tells the backend and the other phone
      if (_viaCallKit) unawaited(FlutterCallkitIncoming.endCall(id));
    }
    unawaited(_teardownRoom().timeout(const Duration(seconds: 5), onTimeout: () {}));
  }

  void _begin(CallState s) {
    _reset?.cancel();
    _hangingUp = false;
    state = s;
  }

  void _finish(String reason) {
    unawaited(CallTones.proximity(false));
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
    unawaited(CallTones.proximity(false));
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
    'SUPPORT_CALL_NOT_ALLOWED' =>
      'Calling support is not available for this account.',
    _ => message.isNotEmpty ? message : "Couldn't place the call",
  };
}

final callControllerProvider = NotifierProvider<CallController, CallState>(
  CallController.new,
);
