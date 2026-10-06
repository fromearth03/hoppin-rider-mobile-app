import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoppin_rider/core/api/api_client.dart';
import 'package:hoppin_rider/core/auth/token_store.dart';
import 'package:hoppin_rider/core/device/device_id.dart';
import 'package:mocktail/mocktail.dart';

class _MockTokens extends Mock implements TokenStore {}

class _MockDevice extends Mock implements DeviceIdProvider {}

/// Streams a fixed list of chunks, split at awkward places, like a real
/// connection delivers server-sent events.
class _StreamAdapter implements HttpClientAdapter {
  _StreamAdapter(this.chunks, {this.status = 200});
  final List<String> chunks;
  final int status;
  String? sentAuth;

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    sentAuth = options.headers['Authorization'] as String?;
    return ResponseBody(
      Stream.fromIterable(
          chunks.map((c) => Uint8List.fromList(utf8.encode(c)))),
      status,
      headers: {
        Headers.contentTypeHeader: ['text/event-stream']
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late _MockTokens tokens;
  late _MockDevice device;

  setUp(() {
    tokens = _MockTokens();
    device = _MockDevice();
    when(() => tokens.read()).thenAnswer((_) async => 'jwt-abc');
    when(() => device.resolve()).thenAnswer((_) async => 'device-1');
  });

  test('yields each data body, skips keep-alive comments, joins split chunks',
      () async {
    final adapter = _StreamAdapter([
      ': connected\n\n',
      'data: {"lat":52.58,"lng":-2.1',
      '2}\n\n: ping\n\ndata: {"lat":52.59,"lng":-2.13}\n\n',
    ]);
    final dio = Dio()..httpClientAdapter = adapter;
    final client = ApiClient(dio, tokens, device, baseUrl: 'https://x.test');

    final events = await client.sse('/rides/r1/driver-location/stream').toList();

    expect(events, ['{"lat":52.58,"lng":-2.12}', '{"lat":52.59,"lng":-2.13}']);
    expect(adapter.sentAuth, 'Bearer jwt-abc');
  });

  test('a refused stream errors so the caller falls back to polling',
      () async {
    final dio = Dio()..httpClientAdapter = _StreamAdapter(['{}'], status: 409);
    final client = ApiClient(dio, tokens, device, baseUrl: 'https://x.test');

    expect(client.sse('/rides/r1/driver-location/stream').toList(),
        throwsA(anything));
  });
}
