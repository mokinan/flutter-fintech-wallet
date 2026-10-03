import 'package:equatable/equatable.dart';

/// Expected failure modes, mapped to user-facing messages in the UI layer.
sealed class Failure extends Equatable {
  const Failure([this.detail]);

  /// Developer-facing detail for logs; never shown to users.
  final String? detail;

  @override
  List<Object?> get props => [runtimeType, detail];
}

/// No connection, timeout, or the server could not be reached.
final class NetworkFailure extends Failure {
  const NetworkFailure([super.detail]);
}

/// Credentials were rejected or the session can no longer be refreshed.
final class AuthFailure extends Failure {
  const AuthFailure([super.detail]);
}

/// The server rejected the request as invalid.
final class ValidationFailure extends Failure {
  const ValidationFailure([super.detail]);
}

/// The account balance is too low for the requested operation.
final class InsufficientFundsFailure extends Failure {
  const InsufficientFundsFailure([super.detail]);
}

/// The server responded with an unexpected error.
final class ServerFailure extends Failure {
  const ServerFailure([super.detail]);
}

/// A local storage operation failed.
final class StorageFailure extends Failure {
  const StorageFailure([super.detail]);
}
