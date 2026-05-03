/// A lightweight Result type for explicit error propagation.
sealed class Result<T> {
  const Result();
}

final class Ok<T> extends Result<T> {
  final T value;
  const Ok(this.value);
}

final class Err<T> extends Result<T> {
  final String code;
  final String message;
  const Err(this.code, this.message);
}

extension ResultExtension<T> on Result<T> {
  bool get isOk => this is Ok<T>;
  bool get isErr => this is Err<T>;

  /// Unwraps the success value. Throws if Err.
  T get unwrap => (this as Ok<T>).value;

  String get errorCode => (this as Err<T>).code;
  String get errorMessage => (this as Err<T>).message;
}
