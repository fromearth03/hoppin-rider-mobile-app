import 'api/api_exception.dart';

/// The outcome of anything that talks to the network.
///
/// Failure is a value, not a thrown exception, so a caller cannot forget to
/// handle it — the compiler makes them look inside.
sealed class Result<T> {
  const Result();

  bool get isOk => this is Ok<T>;

  /// The value, or null on failure. Use when the failure is genuinely
  /// uninteresting; prefer a switch otherwise.
  T? get valueOrNull => switch (this) {
        Ok<T>(:final value) => value,
        Err<T>() => null,
      };

  ApiException? get errorOrNull => switch (this) {
        Ok<T>() => null,
        Err<T>(:final error) => error,
      };
}

class Ok<T> extends Result<T> {
  final T value;
  const Ok(this.value);
}

class Err<T> extends Result<T> {
  final ApiException error;
  const Err(this.error);
}
