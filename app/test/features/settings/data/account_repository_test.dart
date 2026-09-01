import 'package:flutter_test/flutter_test.dart';
import 'package:hoppin_rider/core/api/api_client.dart';
import 'package:hoppin_rider/core/api/api_exception.dart';
import 'package:hoppin_rider/core/result.dart';
import 'package:hoppin_rider/features/settings/data/account_repository.dart';
import 'package:mocktail/mocktail.dart';

class _MockApi extends Mock implements ApiClient {}

void main() {
  late _MockApi api;
  late AccountRepository repo;

  setUp(() {
    api = _MockApi();
    repo = AccountRepository(api);
  });

  test('posts to /me/delete-account with no body', () async {
    // The handler takes the caller's identity from the JWT; there is nothing
    // to send and nothing to confirm server-side.
    when(() => api.post<dynamic>(any())).thenAnswer((_) async =>
        const Ok<dynamic>({
          'message': 'Your account has been deleted and your personal data '
              'erased.',
          'status': 'deleted',
        }));

    await repo.deleteAccount();

    verify(() => api.post<dynamic>('/me/delete-account')).called(1);
  });

  test('reads the server message verbatim on success', () async {
    when(() => api.post<dynamic>(any())).thenAnswer((_) async =>
        const Ok<dynamic>({
          'message': 'Your account has been deleted and your personal data '
              'erased.',
          'status': 'deleted',
        }));

    final outcome =
        ((await repo.deleteAccount()) as Ok<AccountDeletion>).value;

    expect(outcome.message,
        'Your account has been deleted and your personal data erased.');
    expect(outcome.status, 'deleted');
  });

  test('a 200 with no message still succeeds', () async {
    // The Ok is what says the account is gone; the copy is a courtesy.
    when(() => api.post<dynamic>(any()))
        .thenAnswer((_) async => const Ok<dynamic>({'status': 'deleted'}));

    final outcome =
        ((await repo.deleteAccount()) as Ok<AccountDeletion>).value;

    expect(outcome.message, isNull);
    expect(outcome.status, 'deleted');
  });

  group('409 DELETION_BLOCKED', () {
    test('surfaces the blocker reasons the server listed', () async {
      // The handler returns 409 with a `blockers` array when an active trip,
      // an unresolved dispute or an outstanding balance holds. ApiClient's
      // parseError keeps extra top-level keys in `fields`.
      when(() => api.post<dynamic>(any())).thenAnswer((_) async =>
          const Err<dynamic>(ApiException(
            'DELETION_BLOCKED',
            'account cannot be deleted yet',
            409,
            fields: {
              'blockers': ['You have a ride in progress.', 'A dispute is open.'],
            },
          )));

      final error = ((await repo.deleteAccount()) as Err<AccountDeletion>).error;

      expect(error.code, 'DELETION_BLOCKED');
      expect(AccountRepository.blockersOf(error),
          ['You have a ride in progress.', 'A dispute is open.']);
    });

    test('a blockers array with non-strings does not crash the reader',
        () async {
      // whereType keeps a stray null or number from throwing out of a
      // method whose signature promises a plain list of lines to render.
      const error = ApiException(
        'DELETION_BLOCKED',
        'account cannot be deleted yet',
        409,
        fields: {
          'blockers': ['A dispute is open.', null, 42],
        },
      );

      expect(AccountRepository.blockersOf(error), ['A dispute is open.']);
    });

    test('no blockers key reads as an empty list, not a crash', () {
      const error =
          ApiException('DELETION_BLOCKED', 'cannot delete', 409);

      expect(AccountRepository.blockersOf(error), isEmpty);
    });
  });

  test('surfaces an ordinary failure rather than claiming deletion', () async {
    when(() => api.post<dynamic>(any())).thenAnswer((_) async =>
        const Err<dynamic>(ApiException('INTERNAL', 'server error', 500)));

    final result = await repo.deleteAccount();

    expect((result as Err).error.code, 'INTERNAL');
  });
}
