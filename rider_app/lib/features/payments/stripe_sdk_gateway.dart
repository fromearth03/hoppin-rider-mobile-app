import 'package:flutter_riverpod/flutter_riverpod.dart';

/// L1c seam over the platform Stripe SDK (RIDER-APP-ONLY).
///
/// This is the single abstraction the add-card path talks to when a
/// `SetupIntent` `clientSecret` is available. Keeping it here — never in
/// `hoppin_shared`/`hoppin_demo` — is deliberate: it isolates `flutter_stripe`
/// to the rider app (mirroring the Phase-6 `maplibre_gl` isolation) so the
/// shared/demo layers stay SDK-free and the phase-gate isolation grep passes.
///
/// The concrete confirm widget is intentionally DEFERRED behind this seam:
/// `flutter_stripe` PaymentSheet is web-unsupported (research Pitfall 1), and
/// the whole add-card path is GATED on `503 PAYMENTS_DISABLED` today, so no
/// live implementation is wired. The live target is [NoopStripeGateway], which
/// reports the seam as unavailable rather than confirming anything. When the
/// Java payment service + Stripe test secrets land (Phase-13-adjacent), the
/// web `flutter_stripe_web` Confirm Payment Element (and mobile PaymentSheet)
/// slot in behind this interface — nothing above the seam changes.
///
/// Registered by the convergence plan (09-05) in `kSeamRegistry` as GATED
/// (payments-stripe-sandbox); the designed unavailable-state is the wallet's
/// `ComingSoonSheet`.
abstract interface class StripeSdkGateway {
  /// Confirm a server-issued SetupIntent [clientSecret], attaching a reusable
  /// card. Returns a [GatewayResult] describing the outcome. Implementations
  /// MUST NOT call `Stripe.instance.presentPaymentSheet()` on web (it does not
  /// exist there) — the web path is the Confirm Payment Element.
  Future<GatewayResult> confirmSetupIntent(String clientSecret);
}

/// The outcome of a [StripeSdkGateway.confirmSetupIntent] call.
class GatewayResult {
  const GatewayResult._({
    required this.status,
    this.setupIntentId,
    this.message,
  });

  /// The SDK confirmed the SetupIntent and a card is now attached.
  const GatewayResult.succeeded(String setupIntentId)
      : this._(status: GatewayStatus.succeeded, setupIntentId: setupIntentId);

  /// The rider dismissed the confirm surface without completing it.
  const GatewayResult.cancelled()
      : this._(status: GatewayStatus.cancelled);

  /// The SDK path is not available (no live service/secrets wired yet). This
  /// is the current live outcome — the add-card path is GATED, so the caller
  /// renders the honest "coming soon" state rather than a fake success.
  const GatewayResult.unavailable([String? message])
      : this._(status: GatewayStatus.unavailable, message: message);

  /// The confirm attempt failed for a reason worth surfacing.
  const GatewayResult.failed(String message)
      : this._(status: GatewayStatus.failed, message: message);

  final GatewayStatus status;
  final String? setupIntentId;
  final String? message;

  bool get isSucceeded => status == GatewayStatus.succeeded;
}

/// Discrete outcomes of a confirm attempt.
enum GatewayStatus { succeeded, cancelled, unavailable, failed }

/// The current live gateway: the confirm flow is not wired, so it reports the
/// seam as unavailable. Mirrors `FakePaymentsRepository.createSetupIntent`,
/// which throws `UnsupportedError('Not part of the demo')` — a no-op seam,
/// never a fabricated success. The wallet never reaches here in practice
/// because `createSetupIntent` returns `503 PAYMENTS_DISABLED` first; this is
/// the belt-and-braces backstop if a `clientSecret` ever arrives before the
/// concrete SDK implementation lands.
class NoopStripeGateway implements StripeSdkGateway {
  const NoopStripeGateway();

  @override
  Future<GatewayResult> confirmSetupIntent(String clientSecret) async {
    return const GatewayResult.unavailable(
      'Card entry is not available in this build yet.',
    );
  }
}

/// Exposes the active [StripeSdkGateway]. Defaults to [NoopStripeGateway]
/// (the GATED live target); overridden with the concrete SDK implementation
/// when the payment service goes online.
final stripeGatewayProvider = Provider<StripeSdkGateway>(
  (ref) => const NoopStripeGateway(),
);
