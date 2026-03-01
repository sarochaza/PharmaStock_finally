import 'dart:async';
import 'auth_repository.dart';

class MockAuthRepository implements AuthRepository {
  final _controller = StreamController<AppAuthState>.broadcast();
  bool _signedIn = false;

  MockAuthRepository() {
    _controller.add(const AppAuthState(isSignedIn: false));
  }

  @override
  Stream<AppAuthState> authStateChanges() => _controller.stream;

  @override
  Future<bool> hasSession() async => _signedIn;

  @override
  Future<void> signIn({required String email, required String password}) async {
    await Future.delayed(const Duration(milliseconds: 400));
    _signedIn = true;
    _controller.add(const AppAuthState(isSignedIn: true));
  }

  @override
  Future<void> register({required String email, required String password, String? fullName}) async {
    await Future.delayed(const Duration(milliseconds: 600));
    _signedIn = true;
    _controller.add(const AppAuthState(isSignedIn: true));
  }

  @override
  Future<void> signOut() async {
    _signedIn = false;
    _controller.add(const AppAuthState(isSignedIn: false));
  }
}