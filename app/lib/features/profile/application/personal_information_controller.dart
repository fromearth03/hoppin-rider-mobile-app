import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/result.dart';
import '../../auth/data/profile_repository.dart';
import '../domain/personal_information_state.dart';

/// Loads and edits the rider's own profile for the Personal Information
/// screen.
///
/// Deliberately separate from [AuthController]: that controller owns the
/// sign-up/sign-in lifecycle and the app's routing status, neither of which
/// changes when a rider edits their name or phone number here. Reusing it
/// would couple an unrelated screen to auth state transitions.
class PersonalInformationController
    extends StateNotifier<PersonalInformationState> {
  final ProfileRepository _profiles;

  PersonalInformationController(this._profiles)
      : super(const PersonalInformationState()) {
    load();
  }

  Future<void> load() async {
    state = state.copyWith(status: PersonalInformationStatus.loading);
    final result = await _profiles.get();
    state = switch (result) {
      Ok(:final value) => state.copyWith(
          status: PersonalInformationStatus.ready,
          profile: value,
        ),
      Err(:final error) => state.copyWith(
          status: PersonalInformationStatus.error,
          loadError: error,
        ),
    };
  }

  /// Patches the profile. [phoneNumber] is sent as typed; the server ignores
  /// an empty phone rather than clearing the stored number (it cannot be
  /// cleared once set), and a number already held by another account comes
  /// back as `409 PHONE_TAKEN` for the screen to show explicitly.
  Future<void> save({
    required String fullName,
    String? phoneNumber,
  }) async {
    state = state.copyWith(isSaving: true, clearSaveError: true);

    final result = await _profiles.patch(
      fullName: fullName,
      phoneNumber: phoneNumber,
    );

    state = switch (result) {
      Ok(:final value) => state.copyWith(
          isSaving: false,
          profile: value,
          clearSaveError: true,
        ),
      Err(:final error) => state.copyWith(
          isSaving: false,
          saveError: error,
        ),
    };
  }
}

final personalInformationControllerProvider = StateNotifierProvider<
    PersonalInformationController, PersonalInformationState>(
  (ref) => PersonalInformationController(ref.watch(profileRepositoryProvider)),
);
