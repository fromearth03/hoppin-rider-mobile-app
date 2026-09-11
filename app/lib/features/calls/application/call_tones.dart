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
  static Future<void> stop() => _invoke('stop');

  static Future<void> _invoke(String method) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _channel.invokeMethod<void>(method);
    } catch (e) {
      debugPrint('calls: tone $method unavailable: $e');
    }
  }
}
