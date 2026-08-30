/// Date-of-birth rules for the sign-up form.
///
/// The server accepts any valid past date and only refuses at BOOKING with
/// `403 ACCOUNT_NOT_ELIGIBLE` ("riders must be 13 or older"). Checking here
/// means someone too young is told at the form rather than after creating an
/// account and adding a card. The server gate remains the authority; this is
/// a courtesy, not a substitute.
///
/// Format, past-date and year floor mirror `profile_handler.go:70-82`.
class DobValidator {
  DobValidator._();

  static const minimumAge = 13;
  static const _minimumYear = 1900;

  /// Returns null when valid, or a message to show under the field.
  static String? validate(DateTime? dob, {DateTime? now}) {
    if (dob == null) return 'Enter your date of birth';

    final today = now ?? DateTime.now();
    if (dob.isAfter(today)) return 'Date of birth must be in the past';
    if (dob.year < _minimumYear) return 'Enter a valid date of birth';

    if (_ageOn(dob, today) < minimumAge) {
      return 'You must be at least $minimumAge to use Hoppin';
    }
    return null;
  }

  /// Whole years elapsed. Subtracting years and then correcting is what makes
  /// a birthday later this year count as not-yet-reached, and it handles a
  /// 29 February birth date without special-casing it.
  static int _ageOn(DateTime dob, DateTime today) {
    var age = today.year - dob.year;
    final hadBirthday = today.month > dob.month ||
        (today.month == dob.month && today.day >= dob.day);
    if (!hadBirthday) age--;
    return age;
  }

  /// `YYYY-MM-DD`, the only format `PATCH /me/profile` accepts.
  static String format(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}
