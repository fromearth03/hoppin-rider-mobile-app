import 'fcm_gateway.dart';

/// The DEMO gateway — pure Dart, zero firebase imports.
///
/// It lives in the rider app (not in `hoppin_demo`) because the dependency
/// direction is app → package: `hoppin_demo` cannot import `apps/rider`, and so
/// cannot see `fcmGatewayProvider`. `main_demo.dart` registers it as a root
/// override; it is NOT part of `riderDemoOverrides`.
///
/// It scripts a few pushes so the presenter's notification centre is not empty
/// on stage. It is emphatically NOT on the live path — the live default stays
/// [NoopFcmGateway], because faking a push on the live path is precisely the
/// class of lie the no-holes rule forbids.
class FakeFcmGateway implements FcmGateway {
  /// Creates the demo gateway with an explicit script.
  const FakeFcmGateway(this._script);

  /// The demo script: the driver is assigned, arrives, and messages — the three
  /// beats the presenter walks through.
  factory FakeFcmGateway.scripted() => const FakeFcmGateway(<PushMessage>[
        PushMessage(
          type: PushType.driverAssigned,
          title: 'Your driver is on the way',
          body: 'Gurpreet is heading to your pickup.',
        ),
        PushMessage(
          type: PushType.driverArrived,
          title: 'Your driver has arrived',
          body: 'Meet Gurpreet at the pickup point.',
        ),
        PushMessage(
          type: PushType.newMessage,
          title: 'New message from your driver',
          body: "I'm outside.",
        ),
      ]);

  final List<PushMessage> _script;

  @override
  Future<FcmPermission> requestPermission() async => FcmPermission.granted;

  /// Even the demo fake refuses to mint a token. Gap 69 means we never register
  /// one anyway, and a fabricated token has no honest use.
  @override
  Future<String?> token() async => null;

  @override
  Stream<PushMessage> onMessage() => Stream<PushMessage>.fromIterable(_script);

  /// The demo never auto-navigates. A push that opened a screen by itself would
  /// be a surprise, not a demo — taps are the presenter's job.
  @override
  Stream<PushMessage> onMessageOpened() => const Stream.empty();

  @override
  Future<PushMessage?> initialMessage() async => null;
}
