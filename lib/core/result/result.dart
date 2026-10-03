import 'package:fintech_wallet/core/result/failure.dart';

/// Outcome of an operation that can fail in an expected way.
///
/// Repositories return `Result` instead of throwing, so callers are forced by
/// the type system to handle failures. See `docs/adr/0005-result-type.md`.
sealed class Result<T> {
  const Result();

  R when<R>({required R Function(T value) success, required R Function(Failure failure) failure}) => switch (this) {
    Ok(:final value) => success(value),
    Err(failure: final f) => failure(f),
  };

  T? get valueOrNull => switch (this) {
    Ok(:final value) => value,
    Err() => null,
  };

  Failure? get failureOrNull => switch (this) {
    Ok() => null,
    Err(:final failure) => failure,
  };

  bool get isSuccess => this is Ok<T>;
}

final class Ok<T> extends Result<T> {
  const Ok(this.value);
  final T value;
}

final class Err<T> extends Result<T> {
  const Err(this.failure);
  final Failure failure;
}
