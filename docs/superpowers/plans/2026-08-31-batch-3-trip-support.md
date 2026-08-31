# Batch 3 — Trip support data layer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`) syntax.

**Goal:** The chat and safety data layers — everything the in-ride messaging and SOS screens consume — built and tested against the real API shapes.

**Architecture:** Feature-first under `lib/features/chat/` and `lib/features/safety/`. Repositories return `Result<T>` through the existing `ApiClient`.

**Tech Stack:** Flutter 3.44.4 · Dart 3.12.2 · flutter_riverpod 2.6.1 · mocktail 1.0.5

**Worktree:** `C:\Users\Hp\c2o\Hoppin\rider-wt-batch3` on branch `feat/batch-3-trip-support`. This is a SEPARATE checkout from the main tree — batch 2 runs concurrently there. Never touch the other tree.

**Spec:** `docs/superpowers/specs/2026-08-30-rider-app-milestone1-design.md`

## Global Constraints

- **The backend is the source of truth.** No field the API does not return.
- **Money is never a `double`** — use `Pence`.
- **Server-owned copy is rendered verbatim.**
- **TDD throughout**, tests before implementation.
- Run tests with `flutter test` from the worktree's `app/` directory.
- Stage only the files each task creates. Never `git add -A`.

---

### Task 1: Ride chat

**Files:**
- Create: `app/lib/features/chat/data/chat_repository.dart`
- Test: `app/test/features/chat/data/chat_repository_test.dart`

**Interfaces:**
- Consumes: `ApiClient`, `apiClientProvider`, `Result`, `ApiException`.
- Produces: `RideMessage` (`id`, `body`, `senderRole`, `createdAt`, `status`, `replyToId`, `replyToPreview`, `isMine`); `ChatRepository.messages(String rideId, {DateTime? since})`; `ChatRepository.send(String rideId, String body, {String? replyToId})`; `chatRepositoryProvider`.

- [ ] **Step 1: Write the failing test**

```dart
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/chat/data/chat_repository_test.dart`
Expected: FAIL — URI does not exist.

- [ ] **Step 3: Write the implementation**

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_exception.dart';
import '../../../core/result.dart';

/// One message in a ride's chat thread.
///
/// Text only — `ride_messages` has a single content column. Attachments,
/// voice notes and presence are deferred to phase 2 because nothing backs
/// them.
class RideMessage {
  final String id;
  final String body;

  /// `rider` or `driver`.
  final String senderRole;
  final DateTime createdAt;

  /// `sent` or `read`, and ONLY on messages the rider sent. A tick on the
  /// driver's own message would claim they had read their own text.
  final String? status;

  /// Set when this message quotes another.
  final String? replyToId;

  /// The quoted body, for the preview above the bubble. Null when the parent
  /// was deleted — the bubble then shows no quote rather than an empty one.
  final String? replyToPreview;

  const RideMessage({
    required this.id,
    required this.body,
    required this.senderRole,
    required this.createdAt,
    required this.status,
    required this.replyToId,
    required this.replyToPreview,
  });

  bool get isMine => senderRole == 'rider';

  factory RideMessage.fromJson(Map<String, dynamic> json) {
    final parent = (json['reply_to'] as Map?)?.cast<String, dynamic>();
    return RideMessage(
      id: (json['id'] as String?) ?? '',
      body: (json['body'] as String?) ?? '',
      senderRole: (json['sender_role'] as String?) ?? '',
      createdAt:
          DateTime.tryParse((json['created_at'] as String?) ?? '')?.toUtc() ??
              DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      status: json['status'] as String?,
      replyToId: json['reply_to_id'] as String?,
      replyToPreview: parent?['body'] as String?,
    );
  }
}

class ChatRepository {
  final ApiClient _api;
  const ChatRepository(this._api);

  /// Messages for a ride, newest last.
  ///
  /// Pass [since] to fetch only what has arrived since the last poll. It is
  /// omitted on a first load — an empty `since` is rejected as a malformed
  /// timestamp rather than treated as "everything".
  ///
  /// Opening the thread clears `chat_unread` on `GET /rides/:id` server-side.
  Future<Result<List<RideMessage>>> messages(
    String rideId, {
    DateTime? since,
  }) async {
    final result = await _api.get<Map<String, dynamic>>(
      '/rides/$rideId/messages',
      query: {
        if (since != null) 'since': since.toUtc().toIso8601String(),
      },
    );

    return switch (result) {
      Ok(:final value) => Ok(((value['messages'] as List?) ?? [])
          .cast<Map<String, dynamic>>()
          .map(RideMessage.fromJson)
          .toList(growable: false)),
      Err(:final error) => Err(error),
    };
  }

  /// Sends a message, optionally quoting another.
  ///
  /// An empty body is refused here rather than sent: the server rejects it
  /// too, but a round trip to learn what the client already knows is waste,
  /// and the rider sees the refusal instantly.
  Future<Result<RideMessage>> send(
    String rideId,
    String body, {
    String? replyToId,
  }) async {
    final trimmed = body.trim();
    if (trimmed.isEmpty) {
      return Err(ApiException(
          'VALIDATION_FAILED', 'Type a message before sending.', 0));
    }

    final result = await _api.post<Map<String, dynamic>>(
      '/rides/$rideId/messages',
      body: {
        'body': trimmed,
        if (replyToId != null) 'reply_to_id': replyToId,
      },
    );

    return switch (result) {
      Ok(:final value) => Ok(RideMessage.fromJson(value)),
      Err(:final error) => Err(error),
    };
  }
}

final chatRepositoryProvider = Provider<ChatRepository>(
    (ref) => ChatRepository(ref.watch(apiClientProvider)));
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/features/chat/data/chat_repository_test.dart`
Expected: PASS (11 tests)

- [ ] **Step 5: Commit**

```bash
git add app/lib/features/chat/data/chat_repository.dart app/test/features/chat/data/chat_repository_test.dart
git commit -m "feat: ride chat repository

Read receipts appear only on messages the rider sent -- a tick on the
driver's own message would claim they had read their own text.

A reply whose parent was deleted keeps its id but has no preview, so the
bubble shows no quote rather than an empty one.

The since cursor is omitted on first load rather than sent empty, which
the server rejects as a malformed timestamp."
```

---

### Task 2: Safety — SOS, emergency contacts, share link

**Files:**
- Create: `app/lib/features/safety/data/safety_repository.dart`
- Test: `app/test/features/safety/data/safety_repository_test.dart`

**Interfaces:**
- Consumes: `ApiClient`, `Result`, `ApiException`.
- Produces: `EmergencyContact` (`id`, `name`, `phone`, `relationship`); `ShareLink` (`token`, `url`); `PlatformContacts` (`supportEmail`, `supportPhone`, `emergencyPhone`, `whatsappNumber`); `SafetyRepository` with `raiseSos({String? rideId, double? lat, double? lng})`, `listContacts()`, `addContact({required name, required phone, String? relationship})`, `deleteContact(String id)`, `createShareLink(String rideId)`, `revokeShareLink(String rideId)`, `platformContacts()`; `safetyRepositoryProvider`.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:hoppin_rider/core/api/api_client.dart';
import 'package:hoppin_rider/core/api/api_exception.dart';
import 'package:hoppin_rider/core/result.dart';
import 'package:hoppin_rider/features/safety/data/safety_repository.dart';
import 'package:mocktail/mocktail.dart';

class _MockApi extends Mock implements ApiClient {}

void main() {
  late _MockApi api;
  late SafetyRepository repo;

  setUp(() {
    api = _MockApi();
    repo = SafetyRepository(api);
  });

  group('raiseSos', () {
    test('sends position and ride when both are known', () async {
      when(() => api.post<Map<String, dynamic>>(any(),
              body: any(named: 'body')))
          .thenAnswer((_) async => const Ok({'id': 'sos-1'}));

      await repo.raiseSos(rideId: 'ride-1', lat: 52.58, lng: -2.12);

      final body = verify(() => api.post<Map<String, dynamic>>('/me/sos',
          body: captureAny(named: 'body'))).captured.single as Map;

      expect(body['ride_id'], 'ride-1');
      expect(body['lat'], 52.58);
      expect(body['lng'], -2.12);
    });

    test('still raises when there is no position fix', () async {
      // A rider in danger with no GPS must still be able to call for help.
      // Sending 0,0 would put them in the Atlantic on the safety dashboard.
      when(() => api.post<Map<String, dynamic>>(any(),
              body: any(named: 'body')))
          .thenAnswer((_) async => const Ok({'id': 'sos-2'}));

      final result = await repo.raiseSos();

      expect(result, isA<Ok>());
      final body = verify(() => api.post<Map<String, dynamic>>(any(),
          body: captureAny(named: 'body'))).captured.single as Map;

      expect(body.containsKey('lat'), isFalse);
      expect(body.containsKey('ride_id'), isFalse);
    });

    test('surfaces a failure rather than pretending help is coming', () async {
      when(() => api.post<Map<String, dynamic>>(any(),
              body: any(named: 'body')))
          .thenAnswer((_) async =>
              Err(ApiException('INTERNAL', 'server error', 500)));

      final result = await repo.raiseSos();

      expect((result as Err).error.code, 'INTERNAL',
          reason: 'a silent failure here is the worst possible outcome');
    });
  });

  group('emergency contacts', () {
    test('reads the list', () async {
      when(() => api.get<Map<String, dynamic>>(any()))
          .thenAnswer((_) async => const Ok({
                'contacts': [
                  {'id': 'c1', 'name': 'Mum', 'phone': '+447700900123',
                   'relationship': 'parent'},
                ],
              }));

      final result = await repo.listContacts();
      final list = (result as Ok<List<EmergencyContact>>).value;

      expect(list, hasLength(1));
      expect(list.first.name, 'Mum');
      expect(list.first.relationship, 'parent');
    });

    test('a contact with no relationship reads as null, not empty', () async {
      when(() => api.get<Map<String, dynamic>>(any()))
          .thenAnswer((_) async => const Ok({
                'contacts': [
                  {'id': 'c2', 'name': 'Sam', 'phone': '+447700900124',
                   'relationship': ''},
                ],
              }));

      final list =
          ((await repo.listContacts()) as Ok<List<EmergencyContact>>).value;

      expect(list.first.relationship, isNull,
          reason: 'so the row renders no relationship line at all');
    });

    test('refuses a contact with no phone before calling', () async {
      final result = await repo.addContact(name: 'Sam', phone: '  ');

      expect((result as Err).error.code, 'VALIDATION_FAILED');
      verifyNever(() => api.post<Map<String, dynamic>>(any(),
          body: any(named: 'body')));
    });

    test('refuses a contact with no name before calling', () async {
      final result = await repo.addContact(name: '', phone: '+447700900125');

      expect((result as Err).error.code, 'VALIDATION_FAILED');
      verifyNever(() => api.post<Map<String, dynamic>>(any(),
          body: any(named: 'body')));
    });
  });

  group('share link', () {
    test('reads the token and url', () async {
      when(() => api.post<Map<String, dynamic>>(any(),
              body: any(named: 'body')))
          .thenAnswer((_) async => const Ok({
                'token': 'tok-1',
                'url': 'https://api.hoppin.tech/trip-share/tok-1',
              }));

      final link =
          ((await repo.createShareLink('ride-1')) as Ok<ShareLink>).value;

      expect(link.token, 'tok-1');
      expect(link.url, contains('trip-share'));
    });
  });

  group('platform contacts', () {
    test('missing numbers read as null so no dead row is rendered', () async {
      // The server returns blanks rather than 404 when no row is configured.
      when(() => api.get<Map<String, dynamic>>(any()))
          .thenAnswer((_) async => const Ok({
                'support_email': 'help@hoppin.tech',
                'support_phone': '',
                'emergency_phone': '999',
                'whatsapp_number': '',
              }));

      final c =
          ((await repo.platformContacts()) as Ok<PlatformContacts>).value;

      expect(c.supportEmail, 'help@hoppin.tech');
      expect(c.supportPhone, isNull);
      expect(c.emergencyPhone, '999');
      expect(c.whatsappNumber, isNull);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/safety/data/safety_repository_test.dart`
Expected: FAIL — URI does not exist.

- [ ] **Step 3: Write the implementation**

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_exception.dart';
import '../../../core/result.dart';

String? _orNull(Object? v) {
  final s = v as String?;
  return (s == null || s.trim().isEmpty) ? null : s;
}

class EmergencyContact {
  final String id;
  final String name;
  final String phone;

  /// Null when unset, so the row renders no relationship line at all.
  final String? relationship;

  const EmergencyContact({
    required this.id,
    required this.name,
    required this.phone,
    required this.relationship,
  });

  factory EmergencyContact.fromJson(Map<String, dynamic> json) =>
      EmergencyContact(
        id: (json['id'] as String?) ?? '',
        name: (json['name'] as String?) ?? '',
        phone: (json['phone'] as String?) ?? '',
        relationship: _orNull(json['relationship']),
      );
}

/// A live-tracking link the rider can share. The token alone authorizes it.
class ShareLink {
  final String token;
  final String url;

  const ShareLink({required this.token, required this.url});

  factory ShareLink.fromJson(Map<String, dynamic> json) => ShareLink(
        token: (json['token'] as String?) ?? '',
        url: (json['url'] as String?) ?? '',
      );
}

/// Support and emergency numbers, read live so ops can change them without
/// an app release.
class PlatformContacts {
  final String? supportEmail;
  final String? supportPhone;
  final String? emergencyPhone;
  final String? whatsappNumber;

  const PlatformContacts({
    required this.supportEmail,
    required this.supportPhone,
    required this.emergencyPhone,
    required this.whatsappNumber,
  });

  factory PlatformContacts.fromJson(Map<String, dynamic> json) =>
      PlatformContacts(
        supportEmail: _orNull(json['support_email']),
        supportPhone: _orNull(json['support_phone']),
        emergencyPhone: _orNull(json['emergency_phone']),
        whatsappNumber: _orNull(json['whatsapp_number']),
      );
}

class SafetyRepository {
  final ApiClient _api;
  const SafetyRepository(this._api);

  /// Raises a panic alert, which surfaces on the admin safety dashboard.
  ///
  /// Every field is optional. A rider in danger with no GPS fix must still be
  /// able to call for help — sending 0,0 rather than omitting the position
  /// would place them in the Atlantic on the dashboard, which is worse than
  /// no position at all.
  Future<Result<Map<String, dynamic>>> raiseSos({
    String? rideId,
    double? lat,
    double? lng,
  }) =>
      _api.post<Map<String, dynamic>>('/me/sos', body: {
        if (rideId != null) 'ride_id': rideId,
        if (lat != null && lng != null) 'lat': lat,
        if (lat != null && lng != null) 'lng': lng,
      });

  Future<Result<List<EmergencyContact>>> listContacts() async {
    final result =
        await _api.get<Map<String, dynamic>>('/me/emergency-contacts');
    return switch (result) {
      Ok(:final value) => Ok(((value['contacts'] as List?) ?? [])
          .cast<Map<String, dynamic>>()
          .map(EmergencyContact.fromJson)
          .toList(growable: false)),
      Err(:final error) => Err(error),
    };
  }

  /// A contact with no name or no number cannot be called in an emergency,
  /// so it is refused here rather than stored as a row that looks usable.
  Future<Result<EmergencyContact>> addContact({
    required String name,
    required String phone,
    String? relationship,
  }) async {
    final trimmedName = name.trim();
    final trimmedPhone = phone.trim();
    if (trimmedName.isEmpty || trimmedPhone.isEmpty) {
      return Err(ApiException('VALIDATION_FAILED',
          'A contact needs both a name and a phone number.', 0));
    }

    final result = await _api
        .post<Map<String, dynamic>>('/me/emergency-contacts', body: {
      'name': trimmedName,
      'phone': trimmedPhone,
      if (relationship != null && relationship.trim().isNotEmpty)
        'relationship': relationship.trim(),
    });

    return switch (result) {
      Ok(:final value) => Ok(EmergencyContact.fromJson(value)),
      Err(:final error) => Err(error),
    };
  }

  Future<Result<void>> deleteContact(String id) async {
    final result =
        await _api.delete<dynamic>('/me/emergency-contacts/$id');
    return switch (result) {
      Ok() => const Ok(null),
      Err(:final error) => Err(error),
    };
  }

  Future<Result<ShareLink>> createShareLink(String rideId) async {
    final result =
        await _api.post<Map<String, dynamic>>('/rides/$rideId/share-link');
    return switch (result) {
      Ok(:final value) => Ok(ShareLink.fromJson(value)),
      Err(:final error) => Err(error),
    };
  }

  Future<Result<void>> revokeShareLink(String rideId) async {
    final result = await _api.delete<dynamic>('/rides/$rideId/share-link');
    return switch (result) {
      Ok() => const Ok(null),
      Err(:final error) => Err(error),
    };
  }

  /// Public endpoint — the safety screen needs these numbers whether or not
  /// the rider is signed in.
  Future<Result<PlatformContacts>> platformContacts() async {
    final result = await _api.get<Map<String, dynamic>>('/contacts');
    return switch (result) {
      Ok(:final value) => Ok(PlatformContacts.fromJson(value)),
      Err(:final error) => Err(error),
    };
  }
}

final safetyRepositoryProvider = Provider<SafetyRepository>(
    (ref) => SafetyRepository(ref.watch(apiClientProvider)));
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/features/safety/data/safety_repository_test.dart`
Expected: PASS (9 tests)

- [ ] **Step 5: Commit**

```bash
git add app/lib/features/safety/data/safety_repository.dart app/test/features/safety/data/safety_repository_test.dart
git commit -m "feat: safety repository — SOS, contacts, share link

SOS sends nothing it does not know. A rider in danger with no GPS fix
must still be able to call for help, and sending 0,0 rather than
omitting the position would place them in the Atlantic on the admin
safety dashboard -- worse than no position at all.

A failed SOS surfaces as an error rather than a silent success. Telling
someone help is coming when it is not is the worst outcome this screen
has.

An emergency contact missing a name or number is refused before it can
be stored as a row that looks usable but cannot be called."
```

---

### Task 3: Saved locations

**Files:**
- Create: `app/lib/features/booking/data/saved_locations_repository.dart`
- Test: `app/test/features/booking/data/saved_locations_repository_test.dart`

**Interfaces:**
- Consumes: `ApiClient`, `Result`, `ApiException`.
- Produces: `SavedLocation` (`id`, `label`, `lat`, `lng`); `SavedLocationsRepository` with `list()`, `add({required label, required lat, required lng})`, `rename(String id, String label)`, `remove(String id)`; `savedLocationsRepositoryProvider`.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:hoppin_rider/core/api/api_client.dart';
import 'package:hoppin_rider/core/result.dart';
import 'package:hoppin_rider/features/booking/data/saved_locations_repository.dart';
import 'package:mocktail/mocktail.dart';

class _MockApi extends Mock implements ApiClient {}

void main() {
  late _MockApi api;
  late SavedLocationsRepository repo;

  setUp(() {
    api = _MockApi();
    repo = SavedLocationsRepository(api);
  });

  test('reads the list', () async {
    when(() => api.get<Map<String, dynamic>>(any()))
        .thenAnswer((_) async => const Ok({
              'saved_locations': [
                {'id': 's1', 'label': 'Home', 'lat': 52.58, 'lng': -2.12},
              ],
            }));

    final list = ((await repo.list()) as Ok<List<SavedLocation>>).value;

    expect(list.single.label, 'Home');
    expect(list.single.lat, 52.58);
  });

  test('rename keeps the id — it patches rather than recreating', () async {
    // The endpoint exists precisely so a rename does not change the id.
    // Delete-and-recreate would break anything referencing the old one.
    when(() => api.patch<Map<String, dynamic>>(any(), body: any(named: 'body')))
        .thenAnswer((_) async => const Ok({
              'id': 's1', 'label': 'Work', 'lat': 52.58, 'lng': -2.12,
            }));

    final updated =
        ((await repo.rename('s1', 'Work')) as Ok<SavedLocation>).value;

    expect(updated.id, 's1');
    expect(updated.label, 'Work');
    verify(() => api.patch<Map<String, dynamic>>('/me/saved-locations/s1',
        body: {'label': 'Work'})).called(1);
  });

  test('refuses a blank label before calling', () async {
    final result = await repo.rename('s1', '   ');

    expect((result as Err).error.code, 'VALIDATION_FAILED');
    verifyNever(() => api.patch<Map<String, dynamic>>(any(),
        body: any(named: 'body')));
  });

  test('add refuses a blank label before calling', () async {
    final result = await repo.add(label: '', lat: 1, lng: 2);

    expect((result as Err).error.code, 'VALIDATION_FAILED');
    verifyNever(() => api.post<Map<String, dynamic>>(any(),
        body: any(named: 'body')));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/booking/data/saved_locations_repository_test.dart`
Expected: FAIL — URI does not exist.

- [ ] **Step 3: Write the implementation**

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_exception.dart';
import '../../../core/result.dart';

/// A place the rider saved. Its label is what they typed; search ranks these
/// above map hits.
class SavedLocation {
  final String id;
  final String label;
  final double lat;
  final double lng;

  const SavedLocation({
    required this.id,
    required this.label,
    required this.lat,
    required this.lng,
  });

  factory SavedLocation.fromJson(Map<String, dynamic> json) => SavedLocation(
        id: (json['id'] as String?) ?? '',
        label: (json['label'] as String?) ?? '',
        lat: (json['lat'] as num?)?.toDouble() ?? 0,
        lng: (json['lng'] as num?)?.toDouble() ?? 0,
      );
}

class SavedLocationsRepository {
  final ApiClient _api;
  const SavedLocationsRepository(this._api);

  Future<Result<List<SavedLocation>>> list() async {
    final result =
        await _api.get<Map<String, dynamic>>('/me/saved-locations');
    return switch (result) {
      Ok(:final value) => Ok(((value['saved_locations'] as List?) ?? [])
          .cast<Map<String, dynamic>>()
          .map(SavedLocation.fromJson)
          .toList(growable: false)),
      Err(:final error) => Err(error),
    };
  }

  Future<Result<SavedLocation>> add({
    required String label,
    required double lat,
    required double lng,
  }) async {
    final trimmed = label.trim();
    if (trimmed.isEmpty) {
      return Err(ApiException(
          'VALIDATION_FAILED', 'Give this place a name.', 0));
    }

    final result = await _api
        .post<Map<String, dynamic>>('/me/saved-locations', body: {
      'label': trimmed,
      'lat': lat,
      'lng': lng,
    });

    return switch (result) {
      Ok(:final value) => Ok(SavedLocation.fromJson(value)),
      Err(:final error) => Err(error),
    };
  }

  /// Renames in place. The endpoint exists precisely so the id survives —
  /// delete-and-recreate would break anything holding the old one.
  Future<Result<SavedLocation>> rename(String id, String label) async {
    final trimmed = label.trim();
    if (trimmed.isEmpty) {
      return Err(ApiException(
          'VALIDATION_FAILED', 'Give this place a name.', 0));
    }

    final result = await _api.patch<Map<String, dynamic>>(
        '/me/saved-locations/$id',
        body: {'label': trimmed});

    return switch (result) {
      Ok(:final value) => Ok(SavedLocation.fromJson(value)),
      Err(:final error) => Err(error),
    };
  }

  Future<Result<void>> remove(String id) async {
    final result = await _api.delete<dynamic>('/me/saved-locations/$id');
    return switch (result) {
      Ok() => const Ok(null),
      Err(:final error) => Err(error),
    };
  }
}

final savedLocationsRepositoryProvider = Provider<SavedLocationsRepository>(
    (ref) => SavedLocationsRepository(ref.watch(apiClientProvider)));
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/features/booking/data/saved_locations_repository_test.dart`
Expected: PASS (4 tests)

- [ ] **Step 5: Run the full suite and commit**

```bash
flutter test
git add app/lib/features/booking/data/saved_locations_repository.dart app/test/features/booking/data/saved_locations_repository_test.dart
git commit -m "feat: saved locations repository

Rename patches rather than recreating, because the endpoint exists
precisely so the id survives -- delete-and-recreate would break anything
holding the old one."
```

---

## Self-review

**Spec coverage.** §7.3 chat (Task 1), §7.4 safety including SOS, emergency contacts, share link and public contacts (Task 2), and the saved-locations half of §7.1 route entry (Task 3).

**Not covered, deliberately:** notifications, preferences and support tickets are milestone-2 screens. Cancellation policy belongs with the cancel screen in the live-trip batch.

**Placeholders:** none.

**Type consistency:** each repository is self-contained; the only shared types are `ApiClient`, `Result` and `ApiException` from `core/`, all already on disk. `_orNull` is defined once per file that needs it rather than shared, since the two files are in different features.
