import 'package:supabase_flutter/supabase_flutter.dart';
import 'auth_repository.dart';

class SupabaseAuthRepository implements AuthRepository {
  final SupabaseClient client;
  SupabaseAuthRepository(this.client);

  @override
  Stream<AppAuthState> authStateChanges() {
    return client.auth.onAuthStateChange.map((event) {
      final session = event.session;
      return AppAuthState(isSignedIn: session != null);
    });
  }

  @override
  Future<bool> hasSession() async => client.auth.currentSession != null;

  @override
  Future<void> signIn({required String email, required String password}) async {
    final res = await client.auth.signInWithPassword(email: email, password: password);
    if (res.session == null) throw Exception('Login failed');
  }

  @override
  Future<void> register({
    required String email,
    required String password,
    String? fullName,
  }) async {
    final res = await client.auth.signUp(
      email: email,
      password: password,
      data: {
        if (fullName != null && fullName.trim().isNotEmpty) 'full_name': fullName.trim(),
      },
    );
    if (res.user == null) throw Exception('Register failed');
  }

  @override
  Future<void> signOut() async {
    await client.auth.signOut();
  }
}