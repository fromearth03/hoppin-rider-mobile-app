import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';

/// Shows the phone's native incoming-call screen for an `incoming_call` push.
///
/// Native rather than an in-app dialog, because a call has to ring when the app
/// is in the background or closed, and on the lock screen — only the OS call UI
/// can do that. Used for foreground calls too, so a call always looks the same.
///
/// The backend sends these data-only, precisely so this code gets to run: a push
/// with a notification block is drawn by the OS itself and never reaches here.
Future<void> showIncomingCall(Map<String, dynamic> data) async {
  final id = data['call_id'] as String?;
  if (id == null || id.isEmpty) return;
  final role = data['caller_role'] == 'driver' ? 'Your driver' : 'Your rider';
  final name = (data['caller_name'] as String?)?.trim() ?? '';

  // The backend rings for 45 s and stops this screen early with a
  // call_cancelled / call_missed push. Not derived from rings_until: that is
  // the server's wall-clock time, and a server clock 40 s slow made incoming
  // calls ring for ~5 s.
  const ms = 45000;

  await FlutterCallkitIncoming.showCallkitIncoming(
    CallKitParams(
      id: id,
      nameCaller: name.isEmpty ? role : name,
      appName: 'Hoppin',
      // Where a phone number would appear. There isn't one — that is the point.
      handle: role,
      type: 0, // audio only
      duration: ms,
      extra: <String, dynamic>{'ride_id': data['ride_id'] ?? ''},
      missedCallNotification: const NotificationParams(
        showNotification: true,
        subtitle: 'Missed call',
        isShowCallback: false,
      ),
      android: const AndroidParams(
        // The phone's own ringtone. Left empty, the plugin plays a sound it
        // bundles itself.
        ringtonePath: 'system_ringtone_default',
        isCustomNotification: true,
        isShowFullLockedScreen: true,
        // false, not true: with true the plugin opens its ring screen
        // directly and skips the one step that starts the ringtone, so calls
        // arrived silent. The notification route rings first, and its
        // full-screen alert still opens the same ring screen on a locked phone.
        isFullScreen: false,
        backgroundColor: '#14172B',
        actionColor: '#4CAF50',
        textAccept: 'Answer',
        textDecline: 'Decline',
        incomingCallNotificationChannelName: 'Incoming calls',
        missedCallNotificationChannelName: 'Missed calls',
      ),
    ),
  );
}

/// Stops this phone ringing — the caller hung up, or it rang out.
Future<void> stopRinging(Map<String, dynamic> data) async {
  final id = data['call_id'] as String?;
  if (id != null && id.isNotEmpty) await FlutterCallkitIncoming.endCall(id);
}

/// Runs in its own isolate while the app is in the background or closed, so
/// only native UI is possible here: ring, or stop ringing. Answering happens in
/// the app once the rider taps Answer.
@pragma('vm:entry-point')
Future<void> hoppinCallBackgroundMessage(RemoteMessage message) async {
  final data = message.data;
  switch (data['type']) {
    case 'incoming_call':
      await showIncomingCall(data);
    case 'call_cancelled' || 'call_missed':
      await stopRinging(data);
  }
}

/// Registers [hoppinCallBackgroundMessage]. Only once Firebase has come up —
/// without it there are no pushes to handle, and calls can still be placed.
void registerCallBackgroundHandler() {
  if (kIsWeb || Firebase.apps.isEmpty) return;
  FirebaseMessaging.onBackgroundMessage(hoppinCallBackgroundMessage);
}
