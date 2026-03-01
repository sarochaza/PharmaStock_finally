import 'package:flutter/material.dart';

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    // ✅ ถ้าคุณอยากดึง version จริงทีหลัง ค่อยเพิ่ม package_info_plus ได้
    const appName = 'Phamory';
    const version = '1.1';
    const developer = 'Phamory Team';
    const contact = 'sarochax123@gmail.com';

    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FB),
      appBar: AppBar(
        title: const Text('เกี่ยวกับแอป'),
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
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 28,
                          backgroundColor: cs.primary.withOpacity(0.12),
                          child: Icon(Icons.medication_rounded, color: cs.primary, size: 30),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(appName, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
                              const SizedBox(height: 4),
                              Text('Version $version', style: TextStyle(color: Colors.black.withOpacity(0.6))),
                            ],
                          ),
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
                        const Text('รายละเอียด', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                        const SizedBox(height: 10),
                        Text('ผู้พัฒนา: $developer', style: const TextStyle(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 6),
                        Text('ช่องทางติดต่อ: $contact', style: const TextStyle(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 12),
                        Text(
                          'Phamory คือระบบจัดการคลังยา: รับเข้า • จ่ายออก • เตือนหมดอายุ • รายงาน',
                          style: TextStyle(color: Colors.black.withOpacity(0.65), height: 1.4),
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