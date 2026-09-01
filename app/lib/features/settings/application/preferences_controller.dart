import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/result.dart';
import '../data/preferences_repository.dart';

/// What the Setting screen's two live toggles are showing right now.
///
/// [isReady] gates them. Until the server has told us the real state, the
/// switches stay disabled: a toggle rendered live over a failed read would let
/// the rider "turn off" something whose actual value the app never learned, and
/// the next PATCH would write a guess back over server truth.
class PreferencesSnapshot {
  final bool pushTripUpdates;
  final bool soundOfferChime;
  final bool isLoading;

  /// True once a read has succeeded. Only then do the switches accept taps.
  final bool isReady;

  /// Verbatim server copy from the last failure, or null.
  final String? error;

  const PreferencesSnapshot({
    this.pushTripUpdates = true,
    this.soundOfferChime = true,
    this.isLoading = false,
    this.isReady = false,
    this.error,
  });

  PreferencesSnapshot copyWith({
    bool? pushTripUpdates,
    bool? soundOfferChime,
    bool? isLoading,
    bool? isReady,
    String? error,
    bool clearError = false,
  }) =>
      PreferencesSnapshot(
        pushTripUpdates: pushTripUpdates ?? this.pushTripUpdates,
        soundOfferChime: soundOfferChime ?? this.soundOfferChime,
        isLoading: isLoading ?? this.isLoading,
        isReady: isReady ?? this.isReady,
        error: clearError ? null : (error ?? this.error),
      );
}

class PreferencesController extends StateNotifier<PreferencesSnapshot> {
  final PreferencesRepository _repo;

  PreferencesController(this._repo) : super(const PreferencesSnapshot());

  /// The app's own defaults for keys the rider has never set.
  ///
  /// `GetMyPreferences` documents that unset keys are absent and the client
  /// applies its own default. Trip updates and the arrival chime are both
  /// useful-by-default, so absent reads as ON — not as a rider who opted out.
  static const _defaultPushTripUpdates = true;
  static const _defaultSoundOfferChime = true;

  Future<void> load() async {
    state = state.copyWith(isLoading: true, clearError: true);
    switch (await _repo.read()) {
      case Ok(:final value):
        state = state.copyWith(
          pushTripUpdates: value.pushTripUpdates ?? _defaultPushTripUpdates,
          soundOfferChime: value.soundOfferChime ?? _defaultSoundOfferChime,
          isLoading: false,
          isReady: true,
        );
      case Err(:final error):
        state = state.copyWith(
          isLoading: false,
          isReady: false,
          error: error.message,
        );
    }
  }

  /// Moves the switch first, then reconciles with the server.
  ///
  /// A switch that sits on its old value for the length of a round trip reads
  /// as a dead control, so the move is optimistic — but a refusal rolls it
  /// back, because a toggle left in the new position would lie about what was
  /// actually saved.
  Future<void> setPushTripUpdates(bool value) async {
    final previous = state.pushTripUpdates;
    state = state.copyWith(pushTripUpdates: value, clearError: true);

    switch (await _repo.update(pushTripUpdates: value)) {
      case Ok(value: final saved):
        state = state.copyWith(
          pushTripUpdates: saved.pushTripUpdates ?? value,
          soundOfferChime: saved.soundOfferChime ?? state.soundOfferChime,
        );
      case Err(:final error):
        state = state.copyWith(
            pushTripUpdates: previous, error: error.message);
    }
  }

  Future<void> setSoundOfferChime(bool value) async {
    final previous = state.soundOfferChime;
    state = state.copyWith(soundOfferChime: value, clearError: true);

    switch (await _repo.update(soundOfferChime: value)) {
      case Ok(value: final saved):
        state = state.copyWith(
          pushTripUpdates: saved.pushTripUpdates ?? state.pushTripUpdates,
          soundOfferChime: saved.soundOfferChime ?? value,
        );
      case Err(:final error):
        state = state.copyWith(
            soundOfferChime: previous, error: error.message);
    }
  }
}

final preferencesControllerProvider =
    StateNotifierProvider<PreferencesController, PreferencesSnapshot>(
  (ref) => PreferencesController(ref.watch(preferencesRepositoryProvider)),
);
