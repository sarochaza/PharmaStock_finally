import 'package:flutter/material.dart';
import '../../data/auth/auth_repository.dart';

class LoginPage extends StatefulWidget {
  final AuthRepository auth;
  const LoginPage({super.key, required this.auth});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false;
  bool _obscure = true;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      await widget.auth.signIn(email: _email.text.trim(), password: _password.text);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('เข้าสู่ระบบไม่สำเร็จ: $e')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('เข้าสู่ระบบ'),
        backgroundColor: cs.primary,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.lock_rounded, color: cs.primary),
                            const SizedBox(width: 10),
                            Text(
                              'เข้าสู่ระบบด้วยบัญชีของคุณ',
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _email,
                          keyboardType: TextInputType.emailAddress,
                          decoration: const InputDecoration(
                            labelText: 'อีเมล',
                            hintText: 'name@example.com',
                          ),
                          validator: (v) {
                            final x = (v ?? '').trim();
                            if (x.isEmpty) return 'กรุณากรอกอีเมล';
                            if (!x.contains('@')) return 'รูปแบบอีเมลไม่ถูกต้อง';
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _password,
                          obscureText: _obscure,
                          decoration: InputDecoration(
                            labelText: 'รหัสผ่าน',
                            suffixIcon: IconButton(
                              onPressed: () => setState(() => _obscure = !_obscure),
                              icon: Icon(_obscure ? Icons.visibility_rounded : Icons.visibility_off_rounded),
                            ),
                          ),
                          validator: (v) {
                            final x = (v ?? '');
                            if (x.isEmpty) return 'กรุณากรอกรหัสผ่าน';
                            if (x.length < 6) return 'รหัสผ่านควรมีอย่างน้อย 6 ตัวอักษร';
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: FilledButton(
                            onPressed: _loading ? null : _submit,
                            child: _loading
                                ? const SizedBox(
                                    width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Text('เข้าสู่ระบบ'),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'ระบบพร้อมรองรับการยืนยันตัวตนอย่างปลอดภัย หากคุณยังไม่มีบัญชี สามารถลงทะเบียนได้ที่หน้า "สมัครสมาชิก"',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.black45),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}