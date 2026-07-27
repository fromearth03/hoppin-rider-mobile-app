import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// THE ZERO-PERSISTENCE LOCK — the strongest assertion in Phase 12, because it
/// is UNCONDITIONAL.
///
/// The owner's ruling (2026-07-13) is that **nothing is cached to disk
/// pretending to be saved**. That is not a convention to be policed by code
/// review; it is a property of the dependency tree, and the repo currently
/// carries **zero** persistence packages. So the rule becomes a
/// dependency-absence check: it is TRUE today at zero cost, and this test is
/// what stops the first person who adds `shared_preferences` from quietly
/// making it false.
///
/// **Why it matters, feature by feature:**
/// * **Settings (#71)** — a preference written to disk is invisible to the
///   server and to support. A rider who "turns off email notifications" and
///   still receives them has been lied to by their own device.
/// * **Consent (#74 / #42)** — Art. 7(1) requires consent to be
///   **demonstrable**. A record that lives only on the rider's handset is
///   invisible to us, dies on cache-clear, does not follow them to a new
///   device, and is **not legal evidence of anything**. Caching it would
///   convert a known gap into a false comfort — strictly worse than the gap.
/// * **Personal information (#70)** — a locally-"saved" name that the backend
///   never saw is the exact false-persistence signal this phase exists to kill.
///
/// A local store pretending to be server state is fake-as-live. The honest
/// answer is a disclosed seam, and every one of these features ships with one.
void main() {
  /// Every pubspec in the monorepo, read from the rider package's test dir.
  final pubspecPaths = <String>[
    'pubspec.yaml', // apps/rider
    '../driver/pubspec.yaml',
    '../../packages/hoppin_shared/pubspec.yaml',
    '../../packages/hoppin_ui/pubspec.yaml',
    '../../packages/hoppin_demo/pubspec.yaml',
  ];

  /// Packages that put bytes on the device's disk. Any one of them is a place
  /// a screen could pretend something was saved.
  const bannedPackages = <String>[
    'shared_preferences',
    'hive',
    'sqflite',
    'isar',
    'flutter_secure_storage',
    'path_provider',
    'localstorage',
    'drift',
    'objectbox',
    'get_storage',
  ];

  test('every pubspec this test claims to read ACTUALLY EXISTS', () {
    // Vacuity guard. If a path is wrong, the loop below reads nothing, finds
    // nothing banned, and passes while proving NOTHING — a green test that
    // asserts the empty set is worse than a missing one, because it is trusted.
    for (final path in pubspecPaths) {
      expect(File(path).existsSync(), isTrue,
          reason: 'the zero-persistence lock cannot see "$path". It would then '
              'pass VACUOUSLY over a package that might carry a persistence '
              'dependency. Fix the path before trusting a green.');
    }
  });

  test(
      'no package in the monorepo carries an on-disk persistence dependency — a '
      'device-local "save" is invisible to support, dies on cache-clear, and '
      '(for consent) is not legal evidence', () {
    final offenders = <String>[];

    for (final path in pubspecPaths) {
      final lines = File(path).readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        // Only DECLARATIONS count — a package name inside a comment is prose,
        // not a dependency. (An honesty check must be able to tell a lie from a
        // comment ABOUT a lie; here we can, because a dependency has syntax.)
        final trimmed = line.trimLeft();
        if (trimmed.startsWith('#')) continue;

        for (final banned in bannedPackages) {
          if (RegExp('^\\s+$banned\\s*:').hasMatch(line)) {
            offenders.add('$path:${i + 1} → ${line.trim()}');
          }
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'ON-DISK PERSISTENCE HAS BEEN ADDED. Phase 12 forbids it (owner '
          'ruling, 2026-07-13). A screen that writes a preference, a profile '
          'edit or a consent choice to the device pretends the backend saw it — '
          'and the backend did not. For consent that is not merely misleading, '
          'it is legally worthless: Art. 7(1) requires consent to be '
          'DEMONSTRABLE, and we cannot demonstrate what only the handset '
          'knows. If a feature genuinely needs to persist, it needs an '
          'ENDPOINT, and the honest interim is a disclosed seam:\n  '
          '${offenders.join('\n  ')}',
    );
  });

  test('no rider lib/ source reaches for browser storage directly', () {
    // The back door: no package needed. `window.localStorage` (or the modern
    // `package:web` equivalent) would let a screen fake persistence on our only
    // shipping platform with zero pubspec footprint — invisible to the check
    // above.
    final offenders = <String>[];
    final sources = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'));

    final storageRe = RegExp(
      r'localStorage|sessionStorage|window\.localStorage|dart:html|'
      r'IndexedDB|indexedDB',
    );

    for (final file in sources) {
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final trimmed = lines[i].trimLeft();
        // Skip doc comments and line comments — prose about the rule is not a
        // violation of it. (Lane A tripped its own honesty grep this way; the
        // instrument should distinguish where it structurally can.)
        if (trimmed.startsWith('//')) continue;
        if (storageRe.hasMatch(lines[i])) {
          offenders.add('${file.path}:${i + 1} → ${lines[i].trim()}');
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'BROWSER STORAGE ACCESSED DIRECTLY. This is the zero-dependency back '
          'door around the pubspec lock, and on web — our only shipping '
          'platform — it works. Same rule, same reason: a value only the '
          'handset knows was never saved:\n  ${offenders.join('\n  ')}',
    );
  });
}
