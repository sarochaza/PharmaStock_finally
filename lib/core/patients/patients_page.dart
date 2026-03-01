import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'patient_repository.dart';
import 'patient_model.dart';
import 'add_edit_patient_page.dart';
import 'patient_detail_page.dart';

class PatientsPage extends StatefulWidget {
  const PatientsPage({super.key});

  @override
  State<PatientsPage> createState() => _PatientsPageState();
}

class _PatientsPageState extends State<PatientsPage> {
  late final PatientRepository repo = PatientRepository(Supabase.instance.client);

  bool _loading = true;
  List<Patient> _patients = [];
  final _searchCtl = TextEditingController();
  String _q = '';

  @override
  void initState() {
    super.initState();
    _searchCtl.addListener(() => setState(() => _q = _searchCtl.text.trim()));
    _load();
  }

  @override
  void dispose() {
    _searchCtl.dispose();
    super.dispose();
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await repo.listPatients();
      setState(() => _patients = list);
    } catch (e) {
      _toast('โหลดผู้ป่วยไม่สำเร็จ: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Patient> get _filtered {
    if (_q.isEmpty) return _patients;
    final qq = _q.toLowerCase();
    return _patients.where((p) {
      return p.fullName.toLowerCase().contains(qq) ||
          (p.nationalId ?? '').toLowerCase().contains(qq) ||
          (p.phone ?? '').toLowerCase().contains(qq);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FB),
      appBar: AppBar(
        backgroundColor: cs.primary,
        foregroundColor: Colors.white,
        title: const Text('ผู้ป่วย'),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded)),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final saved = await Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const AddEditPatientPage()),
          );
          if (saved != null) _load();
        },
        icon: const Icon(Icons.add_rounded),
        label: const Text('เพิ่มผู้ป่วย'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 980),
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    TextField(
                      controller: _searchCtl,
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.search_rounded),
                        hintText: 'ค้นหา (ชื่อ / บัตรประชาชน / เบอร์โทร)',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                        filled: true,
                        fillColor: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (_filtered.isEmpty)
                      Center(child: Text('ไม่พบผู้ป่วย', style: TextStyle(color: Colors.black.withOpacity(0.6))))
                    else
                      ..._filtered.map((p) => _PatientTile(
                            p: p,
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => PatientDetailPage(patientId: p.id)),
                            ),
                            onEdit: () async {
                              final saved = await Navigator.of(context).push(
                                MaterialPageRoute(builder: (_) => AddEditPatientPage(patientId: p.id)),
                              );
                              if (saved != null) _load();
                            },
                          )),
                    const SizedBox(height: 90),
                  ],
                ),
              ),
            ),
    );
  }
}

class _PatientTile extends StatelessWidget {
  final Patient p;
  final VoidCallback onTap;
  final VoidCallback onEdit;

  const _PatientTile({required this.p, required this.onTap, required this.onEdit});

  @override
  Widget build(BuildContext context) {
    final sub = <String>[];
    if ((p.nationalId ?? '').trim().isNotEmpty) sub.add('บัตร: ${p.nationalId}');
    if ((p.phone ?? '').trim().isNotEmpty) sub.add('โทร: ${p.phone}');
    if (p.age != null) sub.add('อายุ: ${p.age}');

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(child: Text(p.fullName.isEmpty ? '?' : p.fullName.characters.first)),
        title: Text(p.fullName, style: const TextStyle(fontWeight: FontWeight.w900)),
        subtitle: Text(sub.isEmpty ? 'ไม่มีข้อมูลเพิ่มเติม' : sub.join(' • ')),
        trailing: IconButton(
          tooltip: 'แก้ไข',
          onPressed: onEdit,
          icon: const Icon(Icons.edit_rounded),
        ),
      ),
    );
  }
}