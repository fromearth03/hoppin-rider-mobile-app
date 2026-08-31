import 'package:flutter_test/flutter_test.dart';
import 'package:hoppin_rider/core/api/api_client.dart';
import 'package:hoppin_rider/core/api/api_exception.dart';
import 'package:hoppin_rider/core/result.dart';
import 'package:hoppin_rider/features/chat/data/chat_repository.dart';
import 'package:mocktail/mocktail.dart';

class _MockApi extends Mock implements ApiClient {}

void main() {
  late _MockApi api;
  late ChatRepository repo;

  setUp(() {
    api = _MockApi();
    repo = ChatRepository(api);
  });

  group('RideMessage.fromJson', () {
    test('reads a message from the driver', () {
      final m = RideMessage.fromJson(const {
        'id': 'm1',
        'body': 'On my way',
        'sender_role': 'driver',
        'created_at': '2026-08-31T09:00:00Z',
      });

      expect(m.body, 'On my way');
      expect(m.isMine, isFalse);
      expect(m.replyToId, isNull);
    });

    test('a rider message is mine', () {
      final m = RideMessage.fromJson(const {
        'id': 'm2', 'body': 'Thanks', 'sender_role': 'rider',
        'created_at': '2026-08-31T09:01:00Z', 'status': 'read',
      });

      expect(m.isMine, isTrue);
      expect(m.status, 'read');
    });

    test('status is null on a message that is not mine', () {
      // Read receipts only exist for messages the rider sent; showing a tick
      // on the driver's message would claim the driver saw their own text.
      final m = RideMessage.fromJson(const {
        'id': 'm3', 'body': 'Here', 'sender_role': 'driver',
        'created_at': '2026-08-31T09:02:00Z',
      });

      expect(m.status, isNull);
    });

    test('carries a reply preview when the message quotes another', () {
      final m = RideMessage.fromJson(const {
        'id': 'm4', 'body': 'Yes', 'sender_role': 'rider',
        'created_at': '2026-08-31T09:03:00Z',
        'reply_to_id': 'm1',
        'reply_to': {'id': 'm1', 'body': 'On my way',
                     'sender_role': 'driver'},
      });

      expect(m.replyToId, 'm1');
      expect(m.replyToPreview, 'On my way');
    });

    test('a reply whose parent was deleted keeps the id but has no preview',
        () {
      final m = RideMessage.fromJson(const {
        'id': 'm5', 'body': 'Ok', 'sender_role': 'rider',
        'created_at': '2026-08-31T09:04:00Z',
        'reply_to_id': 'gone',
      });

      expect(m.replyToId, 'gone');
      expect(m.replyToPreview, isNull,
          reason: 'the bubble shows no quote rather than an empty one');
    });
  });

  group('messages', () {
    test('sends the since cursor as RFC3339 when given', () async {
      when(() => api.get<Map<String, dynamic>>(any(),
              query: any(named: 'query')))
          .thenAnswer((_) async => const Ok({'messages': []}));

      await repo.messages('ride-1',
          since: DateTime.utc(2026, 8, 31, 9, 0, 0));

      final q = verify(() => api.get<Map<String, dynamic>>(
          '/rides/ride-1/messages',
          query: captureAny(named: 'query'))).captured.single as Map;

      expect(q['since'], '2026-08-31T09:00:00.000Z');
    });

    test('omits the cursor entirely on the first load', () async {
      when(() => api.get<Map<String, dynamic>>(any(),
              query: any(named: 'query')))
          .thenAnswer((_) async => const Ok({'messages': []}));

      await repo.messages('ride-1');

      final q = verify(() => api.get<Map<String, dynamic>>(any(),
          query: captureAny(named: 'query'))).captured.single as Map;

      expect(q.containsKey('since'), isFalse,
          reason: 'an empty since would be rejected as a malformed timestamp');
    });
  });

  group('send', () {
    test('refuses an empty message without calling', () async {
      final result = await repo.send('ride-1', '   ');

      expect((result as Err).error.code, 'VALIDATION_FAILED');
      verifyNever(() => api.post<Map<String, dynamic>>(any(),
          body: any(named: 'body')));
    });

    test('includes reply_to_id only when replying', () async {
      when(() => api.post<Map<String, dynamic>>(any(),
              body: any(named: 'body')))
          .thenAnswer((_) async => const Ok({
                'id': 'm9', 'body': 'Hi', 'sender_role': 'rider',
                'created_at': '2026-08-31T09:05:00Z',
              }));

      await repo.send('ride-1', 'Hi');

      final body = verify(() => api.post<Map<String, dynamic>>(any(),
          body: captureAny(named: 'body'))).captured.single as Map;

      expect(body['body'], 'Hi');
      expect(body.containsKey('reply_to_id'), isFalse);
    });

    test('trims the body before sending', () async {
      when(() => api.post<Map<String, dynamic>>(any(),
              body: any(named: 'body')))
          .thenAnswer((_) async => const Ok({
                'id': 'm10', 'body': 'Hi', 'sender_role': 'rider',
                'created_at': '2026-08-31T09:06:00Z',
              }));

      await repo.send('ride-1', '  Hi  ');

      final body = verify(() => api.post<Map<String, dynamic>>(any(),
          body: captureAny(named: 'body'))).captured.single as Map;

      expect(body['body'], 'Hi');
    });

    test('surfaces FORBIDDEN when the rider is not on the ride', () async {
      when(() => api.post<Map<String, dynamic>>(any(),
              body: any(named: 'body')))
          .thenAnswer((_) async => Err(ApiException(
              'FORBIDDEN', 'you are not a participant of this ride', 403)));

      final result = await repo.send('ride-1', 'Hi');

      expect((result as Err).error.code, 'FORBIDDEN');
    });
  });
}
