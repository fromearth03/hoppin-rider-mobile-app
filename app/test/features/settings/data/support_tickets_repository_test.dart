import 'package:flutter_test/flutter_test.dart';
import 'package:hoppin_rider/core/api/api_client.dart';
import 'package:hoppin_rider/core/api/api_exception.dart';
import 'package:hoppin_rider/core/result.dart';
import 'package:hoppin_rider/features/settings/data/support_tickets_repository.dart';
import 'package:mocktail/mocktail.dart';

class _MockApi extends Mock implements ApiClient {}

void main() {
  late _MockApi api;
  late SupportTicketsRepository repo;

  setUp(() {
    api = _MockApi();
    repo = SupportTicketsRepository(api);
  });

  test('open sends subject, optional type code and body', () async {
    when(() => api.post<Map<String, dynamic>>(any(), body: any(named: 'body')))
        .thenAnswer((_) async => const Ok({'id': 't-1', 'status': 'open'}));

    final result = await repo.open(
      subject: 'Driver took a longer route',
      typeCode: 'route_dispute',
      body: 'The trip took 20 minutes longer than quoted.',
    );

    expect(result, isA<Ok<void>>());
    final captured = verify(() => api.post<Map<String, dynamic>>(
          captureAny(),
          body: captureAny(named: 'body'),
        )).captured;
    expect(captured[0], '/me/support-tickets');
    expect(captured[1], {
      'subject': 'Driver took a longer route',
      'type_code': 'route_dispute',
      'body': 'The trip took 20 minutes longer than quoted.',
    });
  });

  test('an inactive complaint type surfaces the server copy', () async {
    when(() => api.post<Map<String, dynamic>>(any(), body: any(named: 'body')))
        .thenAnswer((_) async => const Err(ApiException('VALIDATION_FAILED',
            'complaint type is inactive or does not exist', 400)));

    final result = await repo.open(subject: 'Anything', typeCode: 'gone');

    expect((result as Err).error.message,
        'complaint type is inactive or does not exist');
  });

  test('list parses the bare ticket array and drops idless rows', () async {
    when(() => api.get<List<dynamic>>('/me/support-tickets'))
        .thenAnswer((_) async => const Ok([
              {
                'id': 't-1',
                'subject': 'Overcharged waiting time',
                'category': 'billing',
                'priority': 'normal',
                'status': 'open',
                'created_at': '2026-09-01T10:00:00Z',
              },
              {'subject': 'no id'},
            ]));

    final list = ((await repo.list()) as Ok<List<SupportTicket>>).value;

    expect(list, hasLength(1));
    expect(list.first.subject, 'Overcharged waiting time');
    expect(list.first.status, 'open');
    expect(list.first.createdAt, DateTime.utc(2026, 9, 1, 10));
  });

  test('complaint types unwrap their envelope and fall back to the code',
      () async {
    when(() => api.get<Map<String, dynamic>>('/complaint-types'))
        .thenAnswer((_) async => const Ok({
              'complaint_types': [
                {'code': 'route_dispute', 'label': 'Route dispute'},
                {'code': 'bare_code_only'},
                {'no_code': true},
              ],
            }));

    final types =
        ((await repo.complaintTypes()) as Ok<List<ComplaintType>>).value;

    expect(types, hasLength(2));
    expect(types.first.label, 'Route dispute');
    expect(types.last.label, 'bare_code_only');
  });
}
