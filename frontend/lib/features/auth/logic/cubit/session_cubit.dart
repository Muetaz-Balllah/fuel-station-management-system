import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:frontend/features/auth/data/models/auth_user.dart';
import 'package:frontend/features/auth/data/repos/auth_repository.dart';

sealed class SessionState {
  const SessionState();
}

class SessionRestoring extends SessionState {
  const SessionRestoring();
}

class SessionAnonymous extends SessionState {
  const SessionAnonymous();
}

class SessionSignedIn extends SessionState {
  const SessionSignedIn(this.user);

  final AuthUser user;
}

class SessionCubit extends Cubit<SessionState> {
  SessionCubit(this._gateway) : super(const SessionRestoring());

  final AuthGateway _gateway;

  Future<void> restore() async {
    emit(const SessionRestoring());
    try {
      final user = await _gateway.restore();
      if (user == null) {
        emit(const SessionAnonymous());
      } else {
        emit(SessionSignedIn(user));
      }
    } catch (_) {
      emit(const SessionAnonymous());
    }
  }

  void signedIn(AuthUser user) {
    emit(SessionSignedIn(user));
  }

  Future<void> signedOut({bool localOnly = false}) async {
    if (!localOnly) {
      await _gateway.logout();
    }
    emit(const SessionAnonymous());
  }
}
