import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoppin_rider/features/notifications/fcm_gateway.dart';
import 'package:hoppin_rider/features/notifications/notification_feed.dart';
import 'package:hoppin_shared/hoppin_shared.dart';

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
  group('NOTIF-01: web registers with device_os "web"', () {
    test('web posts exactly once with "web"', () async {
      final repo = _RecordingProfileRepository();

      final outcome = await registerDeviceTokenIfSupported(
        gateway: const _TokenBearingGateway(),
        profiles: repo,
        isWeb: true,
        platform: TargetPlatform.android,
      );

      expect(outcome, TokenRegistration.registered);
      expect(repo.calls, hasLength(1));
      expect(repo.calls.single.deviceOs, 'web');
      expect(repo.calls.single.fcmToken, 'fcm-token-abc123');
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

      expect(repo.calls.map((c) => c.deviceOs), isNot(contains('android')));
      expect(repo.calls.single.deviceOs, 'web');
    });

    test('iOS Safari on web still sends "web"', () async {
      final repo = _RecordingProfileRepository();

      final outcome = await registerDeviceTokenIfSupported(
        gateway: const _TokenBearingGateway(),
        profiles: repo,
        isWeb: true,
        platform: TargetPlatform.iOS,
      );

      expect(outcome, TokenRegistration.registered);
      expect(repo.calls.single.deviceOs, 'web');
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

      expect(repo.calls, isEmpty);
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
      expect(outcome, TokenRegistration.gatedNoToken);
    });
  });
}
