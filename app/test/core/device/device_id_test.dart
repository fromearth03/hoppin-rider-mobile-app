import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoppin_rider/core/device/device_id.dart';
import 'package:mocktail/mocktail.dart';

class _BrokenStorage extends Mock implements FlutterSecureStorage {}

void main() {
  // A reinstall that restored encrypted data from a backup makes every
  // secure-storage read throw. The id must still resolve, or the device
  // header and the fingerprint check-in silently disappear.
  test('resolve never throws when secure storage is broken', () async {
    final storage = _BrokenStorage();
    when(() => storage.read(key: any(named: 'key'))).thenThrow(Exception('BadPaddingException'));
    when(() => storage.delete(key: any(named: 'key'))).thenThrow(Exception('still broken'));
    when(() => storage.deleteAll()).thenAnswer((_) async {});
    when(() => storage.write(key: any(named: 'key'), value: any(named: 'value')))
        .thenThrow(Exception('cannot write'));

    final p = DeviceIdProvider(storage, DeviceInfoPlugin());
    final id = await p.resolve();
    expect(id, isNotEmpty);
    expect(await p.resolve(), id, reason: 'cached for the rest of the run');
    verify(() => storage.deleteAll()).called(1);
  });
}
