import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoppin_rider/features/notifications/fcm_gateway.dart';
import 'package:hoppin_rider/features/notifications/notification_feed.dart';
import 'package:hoppin_shared/hoppin_shared.dart';

/// NOTIF-01 / gap 69 — the honest-by-default assertion.
///
/// `POST /me/device-tokens` validates `device_os` ∈ {"ios","android"}
/// (DOCS/04:184). There is NO "web". Hoppin ships WEB. So the one genuinely
/// BOUND piece of the notification rail is unreachable on our only platform.
///
/// The tempting fix — `deviceOs: kIsWeb ? 'android' : ...` — writes a LIE into
/// the backend's database, poisons per-platform targeting, and misroutes
/// Web-Push subscriptions down an FCM-Android path that cannot deliver to them.
/// This file exists to pin that we never do it.
class _RecordingProfileRepository implements ProfileRepository {
  final List<({String fcmToken, String deviceOs})> calls = [];

  @override
  Future<void> registerDeviceToken({
    required String fcmToken,
    required String deviceOs,
  }) async {
    calls.add((fcmToken: fcmToken, deviceOs: deviceOs));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Not part of this test: ${invocation.memberName}');
}

/// A gateway that WOULD hand us a token — so the only reason registration is
/// skipped is the `device_os` contract, not a missing token.
class _TokenBearingGateway implements FcmGateway {
  const _TokenBearingGateway();

  @override
  Future<FcmPermission> requestPermission() async => FcmPermission.granted;

  @override
  Future<String?> token() async => 'fcm-token-abc123';

  @override
  Stream<PushMessage> onMessage() => const Stream.empty();

  @override
  Stream<PushMessage> onMessageOpened() => const Stream.empty();

  @override
  Future<PushMessage?> initialMessage() async => null;
}

void main() {
  group('NOTIF-01 gap 69: registerDeviceToken is NOT called on web', () {
    test('web is skipped — the recorder sees ZERO calls', () async {
      final repo = _RecordingProfileRepository();

      final outcome = await registerDeviceTokenIfSupported(
        gateway: const _TokenBearingGateway(),
        profiles: repo,
        isWeb: true,
        platform: TargetPlatform.android, // the browser's reported host OS
      );

      expect(
        repo.calls,
        isEmpty,
        reason:
            'The gateway HAD a token. We still did not register it, because '
            '`device_os` has no "web" value (gap 69). Skipping is the honest '
            'act; sending a false value is not.',
      );
      expect(
        outcome,
        TokenRegistration.gatedNoWebPlatform,
        reason:
            'The skip must be a DISCLOSED, named outcome — not a silent '
            'no-op that looks like success.',
      );
    });

    test('"android" is NEVER sent from web, even when the host OS is Android',
        () async {
      final repo = _RecordingProfileRepository();

      await registerDeviceTokenIfSupported(
        gateway: const _TokenBearingGateway(),
        profiles: repo,
        isWeb: true,
        platform: TargetPlatform.android,
      );

      expect(
        repo.calls.map((c) => c.deviceOs),
        isNot(contains('android')),
        reason:
            'THE assertion this file exists for. Chrome-on-Android reports '
            'TargetPlatform.android, so the lazy path is one line away. It '
            'would write a lie into the backend database.',
      );
      expect(
        repo.calls.map((c) => c.deviceOs),
        isNot(contains('web')),
        reason:
            'The contract rejects "web" with 400 VALIDATION_FAILED. We do not '
            'send it either — we do not send anything.',
      );
    });

    test('iOS Safari on web is also skipped — the platform is the BROWSER',
        () async {
      final repo = _RecordingProfileRepository();

      final outcome = await registerDeviceTokenIfSupported(
        gateway: const _TokenBearingGateway(),
        profiles: repo,
        isWeb: true,
        platform: TargetPlatform.iOS,
      );

      expect(repo.calls, isEmpty);
      expect(outcome, TokenRegistration.gatedNoWebPlatform);
    });
  });

  group('NOTIF-01: native platforms register exactly once, with a legal value',
      () {
    test('iOS registers with device_os "ios"', () async {
      final repo = _RecordingProfileRepository();

      final outcome = await registerDeviceTokenIfSupported(
        gateway: const _TokenBearingGateway(),
        profiles: repo,
        isWeb: false,
        platform: TargetPlatform.iOS,
      );

      expect(repo.calls, hasLength(1), reason: 'Exactly once.');
      expect(repo.calls.single.deviceOs, 'ios');
      expect(repo.calls.single.fcmToken, 'fcm-token-abc123');
      expect(outcome, TokenRegistration.registered);
    });

    test('Android registers with device_os "android"', () async {
      final repo = _RecordingProfileRepository();

      final outcome = await registerDeviceTokenIfSupported(
        gateway: const _TokenBearingGateway(),
        profiles: repo,
        isWeb: false,
        platform: TargetPlatform.android,
      );

      expect(repo.calls, hasLength(1));
      expect(repo.calls.single.deviceOs, 'android');
      expect(outcome, TokenRegistration.registered);
    });

    test('a native platform with NO contract-legal device_os is skipped',
        () async {
      final repo = _RecordingProfileRepository();

      final outcome = await registerDeviceTokenIfSupported(
        gateway: const _TokenBearingGateway(),
        profiles: repo,
        isWeb: false,
        platform: TargetPlatform.macOS,
      );

      expect(
        repo.calls,
        isEmpty,
        reason: 'macOS/Windows/Linux have no legal `device_os` either.',
      );
      expect(outcome, TokenRegistration.gatedNoWebPlatform);
    });
  });

  group('NOTIF-01: no token → no call (the Noop live default)', () {
    test('the Noop gateway yields no token, so nothing is registered',
        () async {
      final repo = _RecordingProfileRepository();

      final outcome = await registerDeviceTokenIfSupported(
        gateway: const NoopFcmGateway(),
        profiles: repo,
        isWeb: false,
        platform: TargetPlatform.android,
      );

      expect(repo.calls, isEmpty);
      expect(
        outcome,
        TokenRegistration.gatedNoToken,
        reason:
            'The live default IS the Noop (delivery is GATED on the backend '
            'FCM creds, gaps 15/16). No token exists to register.',
      );
    });
  });
}
