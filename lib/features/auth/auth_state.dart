import 'package:equatable/equatable.dart';

import '../../data/models/user_model.dart';

enum AuthStatus {
  checking,
  unauthenticated,
  authenticating,
  authenticated,
  serverUnavailable,
}

class AuthState extends Equatable {
  const AuthState({this.status = AuthStatus.checking, this.user, this.message});

  final AuthStatus status;
  final UserModel? user;
  final String? message;

  bool get isAuthenticated => status == AuthStatus.authenticated;

  @override
  List<Object?> get props => [status, user, message];
}
