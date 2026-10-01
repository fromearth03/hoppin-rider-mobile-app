import 'package:flutter_test/flutter_test.dart';
import 'package:hoppin_rider/core/api/api_client.dart';
import 'package:hoppin_rider/core/api/api_exception.dart';
import 'package:hoppin_rider/core/device/device_checkin.dart';
import 'package:hoppin_rider/core/device/device_id.dart';
import 'package:hoppin_rider/core/result.dart';
import 'package:mocktail/mocktail.dart';

class _Api extends Mock implements ApiClient {}

class _Device extends Mock implements DeviceIdProvider {}

void main() {
  late _Api api;
  late _Device device;
  late int posts;

  setUp(() {
    api = _Api();
    device = _Device();
    posts = 0;
    when(() => device.resolve()).thenAnswer((_) async => 'hw-1');
  });

  void answers(List<Result<Map<String, dynamic>>> seq) {
    when(() => api.post<Map<String, dynamic>>('/me/device', body: any(named: 'body')))
        .thenAnswer((_) async => seq[posts++]);
  }

  // It used to mark itself done BEFORE sending, so one failure meant no
  // check-in for the whole session.
  test('a failed check-in is retried until it lands', () async {
    answers([
      Err(ApiException('NETWORK', 'offline', 0)),
      Err(ApiException('NETWORK', 'offline', 0)),
      const Ok(<String, dynamic>{}),
    ]);
    await DeviceCheckin(api, device, backoff: (_) => Duration.zero).report();
    expect(posts, 3);
  });

  test('once it has landed it is throttled, unless forced', () async {
    answers([for (var i = 0; i < 3; i++) const Ok(<String, dynamic>{})]);
    final c = DeviceCheckin(api, device, backoff: (_) => Duration.zero);
    await c.report();
    await c.report();
    expect(posts, 1);
    await c.report(force: true);
    expect(posts, 2);
  });

  test('a throwing device lookup does not stop later check-ins', () async {
    var calls = 0;
    when(() => device.resolve()).thenAnswer((_) async {
      if (calls++ == 0) throw Exception('boom');
      return 'hw-1';
    });
    answers([const Ok(<String, dynamic>{})]);
    await DeviceCheckin(api, device, backoff: (_) => Duration.zero).report();
    expect(posts, 1);
  });
}
