import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Call-progress tones the caller hears: ringback while the other phone rings,
/// busy beeps when the call is declined or goes unanswered.
///
/// Android only for now (a native ToneGenerator in MainActivity); a no-op
/// elsewhere. Never throws: a missing tone must never disturb the call.
class CallTones {
  static const _channel = MethodChannel('tech.hoppin/call_tones');

  static Future<void> ringback() => _invoke('ringback');
  static Future<void> busy() => _invoke('busy');

  /// The phone's ringtone and vibration, for a call ringing this phone while
  /// the app is open.
  static Future<void> ring() => _invoke('ring');

  /// Loudspeaker on or off for call [callId]. Works for a call Android's
  /// Telecom owns (answered from the call notification) as well as one placed
  /// or answered in the app.
  static Future<void> speaker(String? callId, bool on) =>
      _invoke('speaker', {'callId': callId, 'on': on});

  /// Screen off at the ear while a call is connected (ignored on speaker).
  static Future<void> proximity(bool on) => _invoke('proximity', {'on': on});
  static Future<void> stop() => _invoke('stop');

  static Future<void> _invoke(String method, [Map<String, Object?>? args]) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _channel.invokeMethod<void>(method, args);
    } catch (e) {
      debugPrint('calls: tone $method unavailable: $e');
    }
  }
}
