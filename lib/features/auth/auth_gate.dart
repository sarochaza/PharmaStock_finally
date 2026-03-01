import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/auth/auth_repository.dart';
import '../../data/auth/mock_auth_repository.dart';
import '../../data/auth/supabase_auth_repository.dart';
import '../shell/app_shell.dart';
import 'welcome_page.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late final AuthRepository auth;

  @override
  void initState() {
    super.initState();

    // ✅ ถ้า Supabase initialize แล้ว จะไม่ throw
    // ❌ ถ้ายังไม่ initialize (หรือ .env ยังว่าง) จะ throw -> ใช้ Mock
    try {
      final client = Supabase.instance.client;
      client.auth.currentSession; // touch เพื่อเช็คว่า init แล้วจริง

      auth = SupabaseAuthRepository(client);
    } catch (_) {
      auth = MockAuthRepository();
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AppAuthState>(
      stream: auth.authStateChanges(),
      initialData: const AppAuthState(isSignedIn: false),
      builder: (context, snapshot) {
        final signedIn = snapshot.data?.isSignedIn ?? false;

        if (signedIn) {
          return AppShell(auth: auth);
        }
        return WelcomePage(auth: auth);
      },
    );
  }
}