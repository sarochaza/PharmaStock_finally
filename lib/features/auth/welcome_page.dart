import 'package:flutter/material.dart';
import '../../data/auth/auth_repository.dart';
import 'login_page.dart';
import 'register_page.dart';

class WelcomePage extends StatelessWidget {
  final AuthRepository auth;
  const WelcomePage({super.key, required this.auth});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              cs.primary.withOpacity(0.18),
              Colors.white,
              Colors.white,
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _LogoCard(),
                    const SizedBox(height: 18),
                    Text(
                      'PharmaStock',
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.2,
                          ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'ระบบบริหารคลังยาแบบมืออาชีพ\nพร้อมรองรับการเชื่อมต่อฐานข้อมูลในอนาคต',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Colors.black54,
                            height: 1.35,
                          ),
                    ),
                    const SizedBox(height: 22),

                    // CTA Buttons
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: FilledButton(
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => LoginPage(auth: auth)),
                        ),
                        child: const Text('เข้าสู่ระบบ'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: OutlinedButton(
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => RegisterPage(auth: auth)),
                        ),
                        child: const Text('สมัครสมาชิก'),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '© ${DateTime.now().year} PharmaStock • Secure & Reliable',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.black38),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LogoCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: 92,
      height: 92,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 18,
            offset: const Offset(0, 10),
          )
        ],
        border: Border.all(color: cs.primary.withOpacity(0.12)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Image.asset(
            'assets/logo.png',
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => Icon(Icons.local_pharmacy_rounded, size: 44, color: cs.primary),
          ),
        ),
      ),
    );
  }
}