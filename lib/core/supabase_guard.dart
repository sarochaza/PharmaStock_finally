import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// คืนค่า client ถ้า init แล้ว, ถ้ายังไม่ init คืน null (กันจอขาว)
SupabaseClient? getSupabaseClientOrNull() {
  try {
    final c = Supabase.instance.client;

    // ถ้ายังไม่มี session → คืน null (ให้หน้าแสดงข้อความแทน)
    final session = c.auth.currentSession;
    if (session == null) return null;

    return c;
  } catch (_) {
    return null;
  }
}

/// ใช้ครอบหน้าใด ๆ ที่ต้องใช้ Supabase
class SupabaseGuard extends StatelessWidget {
  final Widget child;
  final String? message;
  const SupabaseGuard({
    super.key,
    required this.child,
    this.message,
  });

  @override
  Widget build(BuildContext context) {
    final client = getSupabaseClientOrNull();
    if (client != null) return child;

    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: cs.primary,
        foregroundColor: Colors.white,
        title: const Text('PharmaStock'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.cloud_off_rounded, size: 46, color: cs.primary),
                    const SizedBox(height: 10),
                    Text(
                      'ยังไม่ได้ตั้งค่า Supabase (.env)',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      message ??
                          'หน้านี้ต้องใช้ฐานข้อมูล\nกรุณาใส่ SUPABASE_URL และ SUPABASE_ANON_KEY ในไฟล์ .env แล้วรันใหม่',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.black54, height: 1.35),
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      height: 44,
                      child: FilledButton.icon(
                        onPressed: () => Navigator.maybePop(context),
                        icon: const Icon(Icons.arrow_back_rounded),
                        label: const Text('กลับ'),
                      ),
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