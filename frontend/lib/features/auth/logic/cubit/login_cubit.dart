import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:frontend/core/networking/api_exception.dart';
import 'package:frontend/features/auth/data/repos/auth_repository.dart';
import 'package:frontend/features/auth/logic/cubit/session_cubit.dart';

class LoginState {
  const LoginState({this.submitting = false, this.errorMessage});

  final bool submitting;
  final String? errorMessage;
}

class LoginCubit extends Cubit<LoginState> {
  LoginCubit(this._gateway, this._session) : super(const LoginState());

  final AuthGateway _gateway;
  final SessionCubit _session;

  Future<void> submit({
    required String username,
    required String password,
    required bool rememberMe,
  }) async {
    final trimmed = username.trim();
    if (trimmed.isEmpty) {
      emit(const LoginState(errorMessage: 'أدخل اسم المستخدم'));
      return;
    }
    if (password.isEmpty) {
      emit(const LoginState(errorMessage: 'أدخل كلمة المرور'));
      return;
    }
    emit(const LoginState(submitting: true));
    try {
      final user = await _gateway.login(
        username: trimmed,
        password: password,
        rememberMe: rememberMe,
      );
      _session.signedIn(user);
      emit(const LoginState());
    } on ApiException catch (error) {
      emit(LoginState(errorMessage: error.message));
    } catch (_) {
      emit(const LoginState(errorMessage: 'حدث خطأ غير متوقع. حاول مرة أخرى.'));
    }
  }
}
