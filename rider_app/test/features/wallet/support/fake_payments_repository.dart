import 'package:hoppin_shared/hoppin_shared.dart';

/// A configurable fake of [PaymentsRepository] for the wallet widget tests.
///
/// - [setupIntentError] (default: the live `503 PAYMENTS_DISABLED`) is thrown
///   from [createSetupIntent] so the gated add-card path can be exercised.
/// - [cards] seeds the saved-card list; [txns] seeds the transaction history.
/// - [setDefaultCalls] / [removeCalls] record the mutations so tests can
///   assert the list/default/remove path is truly BOUND (calls the repo).
class RecordingPaymentsRepository implements PaymentsRepository {
  RecordingPaymentsRepository({
    this.cards = const [],
    this.txns = const [],
    Object? setupIntentError,
    SetupIntentInfo? setupIntent,
  }) : _setupIntentError =
           setupIntentError ??
           (setupIntent == null
               ? const ApiException(
                   statusCode: 503,
                   message: 'Card payments are temporarily unavailable.',
                   code: 'PAYMENTS_DISABLED',
                 )
               : null),
       _setupIntent = setupIntent;

  final List<PaymentMethod> cards;
  final List<Transaction> txns;
  final Object? _setupIntentError;
  final SetupIntentInfo? _setupIntent;

  final List<String> setDefaultCalls = [];
  final List<String> removeCalls = [];
  int createSetupIntentCalls = 0;

  @override
  Future<SetupIntentInfo> createSetupIntent() async {
    createSetupIntentCalls++;
    if (_setupIntentError != null) throw _setupIntentError;
    return _setupIntent!;
  }

  @override
  Future<List<PaymentMethod>> paymentMethods() async => cards;

  @override
  Future<void> setDefault(String paymentMethodId) async {
    setDefaultCalls.add(paymentMethodId);
  }

  @override
  Future<void> removeCard(String paymentMethodId) async {
    removeCalls.add(paymentMethodId);
  }

  @override
  Future<List<Transaction>> transactions({int limit = 50}) async => txns;
}
