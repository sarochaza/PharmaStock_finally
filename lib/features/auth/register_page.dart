import 'package:flutter/material.dart';
import '../../data/auth/auth_repository.dart';

class RegisterPage extends StatefulWidget {
  final AuthRepository auth;
  const RegisterPage({super.key, required this.auth});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _formKey = GlobalKey<FormState>();
  final _fullName = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();

  bool _loading = false;
  bool _obscure1 = true;
  bool _obscure2 = true;

  @override
  void dispose() {
    _fullName.dispose();
    _email.dispose();
    _password.dispose();
    _confirmPassword.dispose();
    super.dispose();
  }

  // ===== Password Validator =====
  String? _validatePassword(String value) {
    if (value.isEmpty) return 'กรุณากรอกรหัสผ่าน';
    if (value.length < 8) return 'รหัสผ่านต้องมีอย่างน้อย 8 ตัวอักษร';
    if (!RegExp(r'[A-Z]').hasMatch(value)) return 'ต้องมีตัวพิมพ์ใหญ่ (A-Z)';
    if (!RegExp(r'[a-z]').hasMatch(value)) return 'ต้องมีตัวพิมพ์เล็ก (a-z)';
    if (!RegExp(r'[0-9]').hasMatch(value)) return 'ต้องมีตัวเลข (0-9)';
    if (!RegExp(r'[!@#\$%^&*(),.?":{}|<>]').hasMatch(value)) {
      return 'ต้องมีอักขระพิเศษ เช่น !@#\$%^&*';
    }
    return null;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _loading = true);

    try {
      await widget.auth.register(
        email: _email.text.trim(),
        password: _password.text,
        fullName: _fullName.text.trim(),
      );

      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('สมัครสมาชิกไม่สำเร็จ: $e')),
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
        title: const Text('สมัครสมาชิก'),
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
                            Icon(Icons.person_add_alt_1_rounded, color: cs.primary),
                            const SizedBox(width: 10),
                            Text(
                              'สร้างบัญชีใหม่',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                          ],
                        ),

                        const SizedBox(height: 16),

                        TextFormField(
                          controller: _fullName,
                          decoration: const InputDecoration(
                            labelText: 'ชื่อ-นามสกุล (ไม่บังคับ)',
                          ),
                        ),

                        const SizedBox(height: 12),

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
                            if (!RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(x)) {
                              return 'รูปแบบอีเมลไม่ถูกต้อง';
                            }
                            return null;
                          },
                        ),

                        const SizedBox(height: 12),

                        // ===== Password =====
                        TextFormField(
                          controller: _password,
                          obscureText: _obscure1,
                          decoration: InputDecoration(
                            labelText: 'รหัสผ่าน',
                            helperText: 'รหัสผ่านต้องมีอย่างน้อย 8 ตัว และประกอบด้วยตัวใหญ่ ตัวเล็ก ตัวเลข และสัญลักษณ์',
                            suffixIcon: IconButton(
                              onPressed: () =>
                                  setState(() => _obscure1 = !_obscure1),
                              icon: Icon(_obscure1
                                  ? Icons.visibility
                                  : Icons.visibility_off),
                            ),
                          ),
                          validator: (v) => _validatePassword(v ?? ''),
                        ),

                        const SizedBox(height: 12),

                        // ===== Confirm Password =====
                        TextFormField(
                          controller: _confirmPassword,
                          obscureText: _obscure2,
                          decoration: InputDecoration(
                            labelText: 'ยืนยันรหัสผ่าน',
                            suffixIcon: IconButton(
                              onPressed: () =>
                                  setState(() => _obscure2 = !_obscure2),
                              icon: Icon(_obscure2
                                  ? Icons.visibility
                                  : Icons.visibility_off),
                            ),
                          ),
                          validator: (v) {
                            if ((v ?? '').isEmpty) {
                              return 'กรุณายืนยันรหัสผ่าน';
                            }
                            if (v != _password.text) {
                              return 'รหัสผ่านไม่ตรงกัน';
                            }
                            return null;
                          },
                        ),

                        const SizedBox(height: 18),

                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: FilledButton(
                            onPressed: _loading ? null : _submit,
                            child: _loading
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child:
                                        CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Text('สร้างบัญชี'),
                          ),
                        ),

                        const SizedBox(height: 10),

                        Text(
                          'พร้อมให้คุณเริ่มต้นบริหารจัดการได้ทันทีหลังจากสร้างบัญชีสำเร็จ',
                          textAlign: TextAlign.center,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: Colors.black45),
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