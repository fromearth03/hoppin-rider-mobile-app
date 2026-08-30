import 'package:intl/intl.dart';

/// Money, always as whole pence.
///
/// The API sends integer `*_pence` and this type keeps it that way to the point
/// of render. A double would introduce rounding the backend does not have —
/// £12.38 is 1238, never 12.379999999999999.
///
/// Nullable money stays null. A fare that has not been charged yet is `null`,
/// never `Pence.zero`, because "free" and "not yet known" are different things
/// and only one of them should print as "£0.00".
class Pence implements Comparable<Pence> {
  final int value;

  const Pence(this.value);
  static const zero = Pence(0);

  /// Parses an API integer. Null in, null out — see the class note.
  static Pence? fromJson(Object? raw) => switch (raw) {
        int v => Pence(v),
        // Some historical rows arrive as a JSON number that decoded to double.
        double v => Pence(v.round()),
        _ => null,
      };

  bool get isNegative => value < 0;
  Pence get abs => Pence(value.abs());

  Pence operator +(Pence other) => Pence(value + other.value);
  Pence operator -(Pence other) => Pence(value - other.value);

  @override
  int compareTo(Pence other) => value.compareTo(other.value);

  /// "£12.38". Currency defaults to GBP; the API always sends the code
  /// alongside the amount, so pass it rather than assuming.
  String format({String currency = 'GBP', bool showSign = false}) {
    final f = NumberFormat.simpleCurrency(locale: 'en_GB', name: currency);
    final formatted = f.format(value.abs() / 100);
    if (!showSign) return value < 0 ? '-$formatted' : formatted;
    return value < 0 ? '-$formatted' : '+$formatted';
  }

  @override
  bool operator ==(Object other) => other is Pence && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'Pence($value)';
}
