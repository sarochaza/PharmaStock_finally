abstract class AuthRepository {
  Stream<AppAuthState> authStateChanges();

  Future<bool> hasSession();
  Future<void> signIn({required String email, required String password});
  Future<void> register({required String email, required String password, String? fullName});
  Future<void> signOut();
}

/// ✅ ตั้งชื่อใหม่ AppAuthState กันชนกับ AuthState ของ Supabase
class AppAuthState {
  final bool isSignedIn;
  const AppAuthState({required this.isSignedIn});
}