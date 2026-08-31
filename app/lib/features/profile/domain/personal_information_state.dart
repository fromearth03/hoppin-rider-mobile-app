import '../../../core/api/api_exception.dart';
import '../../auth/data/profile_repository.dart';

enum PersonalInformationStatus { loading, ready, error }

/// State for the Personal Information screen.
///
/// [loadError] and [saveError] are kept separate rather than sharing one
/// field: a failed save must not blank the screen back to the error state
/// (the rider's edits and the loaded profile are still good), while a failed
/// load has nothing to show at all.
class PersonalInformationState {
  final PersonalInformationStatus status;
  final RiderProfile? profile;
  final ApiException? loadError;
  final ApiException? saveError;
  final bool isSaving;

  const PersonalInformationState({
    this.status = PersonalInformationStatus.loading,
    this.profile,
    this.loadError,
    this.saveError,
    this.isSaving = false,
  });

  PersonalInformationState copyWith({
    PersonalInformationStatus? status,
    RiderProfile? profile,
    ApiException? loadError,
    ApiException? saveError,
    bool clearSaveError = false,
    bool? isSaving,
  }) =>
      PersonalInformationState(
        status: status ?? this.status,
        profile: profile ?? this.profile,
        loadError: loadError ?? this.loadError,
        saveError: clearSaveError ? null : (saveError ?? this.saveError),
        isSaving: isSaving ?? this.isSaving,
      );
}
