import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoppin_rider/core/api/api_client.dart';
import 'package:hoppin_rider/core/auth/token_store.dart';
import 'package:hoppin_rider/core/device/device_id.dart';
import 'package:hoppin_rider/core/result.dart';
import 'package:mocktail/mocktail.dart';

class _MockTokens extends Mock implements TokenStore {}

class _MockDevice extends Mock implements DeviceIdProvider {}

/// Answers every request immediately, so the only thing a test can be waiting
/// on is the client's own pre-request work.
class _InstantAdapter implements HttpClientAdapter {
  String? sentAuth;
  Object body = const {'ok': true};
  int status = 200;

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    sentAuth = options.headers['Authorization'] as String?;
    return ResponseBody.fromString(jsonEncode(body), status,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType]
        });
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late Dio dio;
  late _InstantAdapter adapter;
  late _MockTokens tokens;
  late _MockDevice device;

  setUp(() {
    dio = Dio();
    adapter = _InstantAdapter();
    dio.httpClientAdapter = adapter;
    tokens = _MockTokens();
    device = _MockDevice();
    when(() => device.resolve()).thenAnswer((_) async => 'device-1');
  });

  test('a token read that never settles does not hang the request', () async {
    // The bug this covers: the header work runs in a Dio interceptor, and Dio's
    // connectTimeout does not start until the connection is attempted — so
    // anything awaited there sits outside every timeout the client has. A
    // stalled token refresh blocked the request BEFORE it was sent, and the
    // screen waiting on it never left its skeleton.
    when(() => tokens.read()).thenAnswer((_) => Completer<String?>().future);

    final client = ApiClient(dio, tokens, device, baseUrl: 'https://x.test');

    final result = await client
        .get<Map<String, dynamic>>('/anything')
        .timeout(const Duration(seconds: 20));

    expect(result, isA<Ok<Map<String, dynamic>>>());
    // Sent WITHOUT the header rather than not sent at all: a 401 is recoverable,
    // a request that never leaves is not.
    expect(adapter.sentAuth, isNull);
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('a working token is still attached', () async {
    when(() => tokens.read()).thenAnswer((_) async => 'jwt-abc');

    final client = ApiClient(dio, tokens, device, baseUrl: 'https://x.test');
    await client.get<Map<String, dynamic>>('/anything');

    expect(adapter.sentAuth, 'Bearer jwt-abc');
  });

  test('a second client over the same Dio replaces its interceptor', () async {
    // Two ApiClients used to leave BOTH interceptors in the chain, each reading
    // the token again on every request.
    when(() => tokens.read()).thenAnswer((_) async => 'jwt-abc');

    ApiClient(dio, tokens, device, baseUrl: 'https://x.test');
    final second = ApiClient(dio, tokens, device, baseUrl: 'https://x.test');
    await second.get<Map<String, dynamic>>('/anything');

    verify(() => tokens.read()).called(1);
  });
  test('a response of the wrong shape is an error, not a crash', () async {
    // The bug this covers: `response.data as T` threw a TypeError from inside
    // an async body, so it escaped as an UNHANDLED error — the caller's future
    // never completed and the screen awaiting it sat on its skeleton forever.
    // /me/saved-locations returns a bare array; the repository asked for a Map.
    when(() => tokens.read()).thenAnswer((_) async => 'jwt-abc');
    adapter.body = [
      {'id': '1', 'label': 'Home'}
    ];

    final client = ApiClient(dio, tokens, device, baseUrl: 'https://x.test');
    final result = await client.get<Map<String, dynamic>>('/anything');

    expect(result, isA<Err<Map<String, dynamic>>>());
    expect((result as Err).error.code, 'UNEXPECTED_RESPONSE');
  });

  test('a matching shape still comes back as Ok', () async {
    when(() => tokens.read()).thenAnswer((_) async => 'jwt-abc');
    adapter.body = [
      {'id': '1', 'label': 'Home'}
    ];

    final client = ApiClient(dio, tokens, device, baseUrl: 'https://x.test');
    final result = await client.get<List<dynamic>>('/anything');

    expect(result, isA<Ok<List<dynamic>>>());
    expect((result as Ok).value, hasLength(1));
  });

}
