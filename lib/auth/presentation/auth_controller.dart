import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/auth_service.dart';
import '../domain/auth_session.dart';

class AuthController extends Notifier<AuthSession?> {
  @override
  AuthSession? build() => null;

  Future<String?> login(String username, String password) async {
    final r = await ref.read(authServiceProvider).login(username, password);
    if (r.session != null) state = r.session;
    return r.error; // null on success
  }

  void logout() => state = null;
}

final authControllerProvider = NotifierProvider<AuthController, AuthSession?>(
  AuthController.new,
);
