import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoppin_rider/core/theme/theme_mode_provider.dart';

void main() {
  test('defaults to ThemeMode.light -- the design pack is light-only', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(themeModeProvider), ThemeMode.light);
  });

  test('writing to the notifier updates the provider value', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container.read(themeModeProvider.notifier).state = ThemeMode.dark;

    expect(container.read(themeModeProvider), ThemeMode.dark);
  });

  test('each ProviderContainer starts fresh -- no cross-session persistence',
      () {
    final first = ProviderContainer();
    addTearDown(first.dispose);
    first.read(themeModeProvider.notifier).state = ThemeMode.dark;

    final second = ProviderContainer();
    addTearDown(second.dispose);

    // A brand new container (standing in for a fresh app launch) does not
    // see the first container's choice -- there is nothing durable behind
    // this provider, by design.
    expect(second.read(themeModeProvider), ThemeMode.light);
  });
}
