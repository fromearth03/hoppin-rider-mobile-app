import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/push/call_push.dart';
import 'call_controller.dart';

/// Connects the outside world to the call controller: pushes about calls while
/// the app is open, and taps on the phone's native incoming-call screen.
///
/// Created at start-up (see HoppinApp) so a call can ring whatever screen the
/// rider happens to be on.
class CallCoordinator {
  CallCoordinator(this._ref) {
    _start();
  }

  final Ref _ref;
  final _subs = <StreamSubscription<dynamic>>[];

  CallController get _calls => _ref.read(callControllerProvider.notifier);

  void _start() {
    if (kIsWeb) return; // no native call screen, no background push on web
    if (Firebase.apps.isNotEmpty) {
      _subs.add(FirebaseMessaging.onMessage.listen((m) => _onPush(m.data)));
    }
    _subs.add(FlutterCallkitIncoming.onEvent.listen(_onCallKit));
  }

  void _onPush(Map<String, dynamic> data) {
    switch (data['type']) {
      case 'incoming_call':
        // App open on Android: Hoppin's own call screen, at once. The native
        // call notification is for when the app is in the background or
        // closed; in the foreground it arrived seconds after the vibration
        // and looked nothing like the rest of the call. iOS keeps CallKit,
        // which is instant and native there.
        if (defaultTargetPlatform == TargetPlatform.android) {
          _calls.showIncoming(data);
        } else {
          unawaited(showIncomingCall(data));
        }
      case 'call_cancelled' || 'call_missed':
        unawaited(stopRinging(data));
        _calls.onSignal(data);
      case 'call_declined' || 'call_unanswered':
        _calls.onSignal(data);
    }
  }

  void _onCallKit(CallEvent? event) {
    switch (event) {
      case CallEventActionCallAccept(:final callKitParams):
        unawaited(
          _calls.acceptIncoming(
            callKitParams.id,
            peerName: callKitParams.nameCaller ?? '',
            viaCallKit: true,
          ),
        );
      case CallEventActionCallDecline(:final callKitParams):
        unawaited(_calls.declineIncoming(callKitParams.id));
      default:
        break;
    }
  }

  void dispose() {
    for (final s in _subs) {
      unawaited(s.cancel());
    }
  }
}

final callCoordinatorProvider = Provider<CallCoordinator>((ref) {
  final c = CallCoordinator(ref);
  ref.onDispose(c.dispose);
  return c;
});
