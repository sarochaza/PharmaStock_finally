import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase_guard.dart';

class SecurityPage extends StatefulWidget {
  const SecurityPage({super.key});

  @override
  State<SecurityPage> createState() => _SecurityPageState();
}

class _SecurityPageState extends State<SecurityPage> {
  final SupabaseClient _sb = Supabase.instance.client;

  final _emailCtl = TextEditingController();
  final _pwCtl = TextEditingController();
  final _pw2Ctl = TextEditingController();

  bool _savingEmail = false;
  bool _savingPw = false;

  @override
  void initState() {
    super.initState();
    _emailCtl.text = _sb.auth.currentUser?.email ?? '';
  }

  @override
  void dispose() {
    _emailCtl.dispose();
    _pwCtl.dispose();
    _pw2Ctl.dispose();
    super.dispose();
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  InputDecoration _dec(String label, {IconData? icon, String? hint}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: icon == null ? null : Icon(icon),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      filled: true,
      fillColor: Colors.white,
    );
  }

  Future<void> _changeEmail() async {
    final newEmail = _emailCtl.text.trim();
    if (newEmail.isEmpty) {
      _toast('กรุณากรอกอีเมล');
      return;
    }
    if (!newEmail.contains('@') || !newEmail.contains('.')) {
      _toast('รูปแบบอีเมลไม่ถูกต้อง');
      return;
    }
    if (_savingEmail) return;

    setState(() => _savingEmail = true);
    try {
      await _sb.auth.updateUser(UserAttributes(email: newEmail));

      // Supabase ส่วนใหญ่จะส่ง confirm email ไปที่อีเมลใหม่
      _toast('อัปเดตอีเมลแล้ว ✅ (อาจต้องยืนยันผ่านอีเมล)');
    } catch (e) {
      _toast('เปลี่ยนอีเมลไม่สำเร็จ: $e');
    } finally {
      if (mounted) setState(() => _savingEmail = false);
    }
  }

  Future<void> _changePassword() async {
    final p1 = _pwCtl.text;
    final p2 = _pw2Ctl.text;

    if (p1.trim().isEmpty) {
      _toast('กรุณากรอกรหัสผ่านใหม่');
      return;
    }
    if (p1.length < 6) {
      _toast('รหัสผ่านควรอย่างน้อย 6 ตัวอักษร');
      return;
    }
    if (p1 != p2) {
      _toast('รหัสผ่านไม่ตรงกัน');
      return;
    }
    if (_savingPw) return;

    setState(() => _savingPw = true);
    try {
      await _sb.auth.updateUser(UserAttributes(password: p1));
      _pwCtl.clear();
      _pw2Ctl.clear();
      _toast('เปลี่ยนรหัสผ่านเรียบร้อย ✅');
    } catch (e) {
      _toast('เปลี่ยนรหัสผ่านไม่สำเร็จ: $e');
    } finally {
      if (mounted) setState(() => _savingPw = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_sb.auth.currentUser == null) {
      return const SupabaseGuard(
        child: SizedBox.shrink(),
        message: 'หน้า Security ต้องล็อกอินก่อน',
      );
    }

    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FB),
      appBar: AppBar(
        title: const Text('ความปลอดภัย'),
        backgroundColor: cs.primary,
        foregroundColor: Colors.white,
        centerTitle: true,
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('เปลี่ยนอีเมล', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _emailCtl,
                          keyboardType: TextInputType.emailAddress,
                          decoration: _dec('อีเมลใหม่', icon: Icons.email_rounded),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          height: 48,
                          child: FilledButton(
                            onPressed: _savingEmail ? null : _changeEmail,
                            style: FilledButton.styleFrom(
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            ),
                            child: _savingEmail
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                  )
                                : const Text('อัปเดตอีเมล', style: TextStyle(fontWeight: FontWeight.w900)),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'หมายเหตุ: บางครั้งระบบจะส่งลิงก์ยืนยันไปที่อีเมลใหม่ก่อนใช้งานจริง',
                          style: TextStyle(color: Colors.black.withOpacity(0.6)),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('เปลี่ยนรหัสผ่าน', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _pwCtl,
                          obscureText: true,
                          decoration: _dec('รหัสผ่านใหม่', icon: Icons.lock_rounded),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _pw2Ctl,
                          obscureText: true,
                          decoration: _dec('ยืนยันรหัสผ่านใหม่', icon: Icons.lock_outline_rounded),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          height: 48,
                          child: FilledButton(
                            onPressed: _savingPw ? null : _changePassword,
                            style: FilledButton.styleFrom(
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            ),
                            child: _savingPw
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                  )
                                : const Text('อัปเดตรหัสผ่าน', style: TextStyle(fontWeight: FontWeight.w900)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}