import 'package:equatable/equatable.dart';
import 'package:fintech_wallet/core/result/failure.dart';
import 'package:fintech_wallet/core/result/result.dart';
import 'package:fintech_wallet/features/auth/data/auth_repository.dart';
import 'package:fintech_wallet/features/auth/presentation/session_cubit.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class LoginState extends Equatable {
  const LoginState({this.submitting = false, this.failure});

  final bool submitting;
  final Failure? failure;

  @override
  List<Object?> get props => [submitting, failure];
}

class LoginCubit extends Cubit<LoginState> {
  LoginCubit(this._auth, this._session) : super(const LoginState());

  final AuthRepository _auth;
  final SessionCubit _session;

  Future<void> submit({required String email, required String password}) async {
    if (state.submitting) return;
    emit(const LoginState(submitting: true));
    switch (await _auth.login(email: email, password: password)) {
      case Ok():
        await _session.loggedIn();
        if (!isClosed) emit(const LoginState());
      case Err(:final failure):
        emit(LoginState(failure: failure));
    }
  }
}
