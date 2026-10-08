import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoppin_rider/core/api/api_client.dart';
import 'package:hoppin_rider/core/auth/token_store.dart';
import 'package:hoppin_rider/core/device/device_id.dart';
import 'package:mocktail/mocktail.dart';

class _Tokens extends Mock implements TokenStore {}
class _Device extends Mock implements DeviceIdProvider {}
class _Adapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? body,
      Future<void>? cancel) async {
    requests.add(options);
    return ResponseBody.fromBytes([1, 2], 200);
  }
  @override
  void close({bool force = false}) {}
}

void main() {
  test('image credentials stay on the exact API origin and redirects are disabled', () async {
    final tokens = _Tokens();
    final device = _Device();
    when(() => tokens.read()).thenAnswer((_) async => 'test-token');
    when(() => device.resolve()).thenAnswer((_) async => 'test-device');
    final adapter = _Adapter();
    final dio = Dio()..httpClientAdapter = adapter;
    final api = ApiClient(dio, tokens, device, baseUrl: 'https://api.test/api/v1');
    for (final url in ['https://api.test/image', 'https://other.test/image',
        'http://api.test/image', 'https://api.test:8443/image']) {
      await api.getBytes(url);
    }
    expect(adapter.requests.first.headers['Authorization'], 'Bearer test-token');
    for (final request in adapter.requests.skip(1)) {
      expect(request.headers.keys.map((k) => k.toLowerCase()),
          isNot(contains('authorization')));
      expect(request.headers.keys.map((k) => k.toLowerCase()),
          isNot(contains('x-hoppin-device-id')));
    }
    expect(adapter.requests.every((r) => !r.followRedirects), isTrue);
  });
}
