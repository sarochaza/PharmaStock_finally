import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'patient_repository.dart';
import 'patient_model.dart';

class PatientDetailPage extends StatefulWidget {
  final String patientId;
  const PatientDetailPage({super.key, required this.patientId});

  @override
  State<PatientDetailPage> createState() => _PatientDetailPageState();
}

class _PatientDetailPageState extends State<PatientDetailPage> {
  late final PatientRepository repo = PatientRepository(Supabase.instance.client);

  bool _loading = true;
  Patient? _p;

  List<Map<String, dynamic>> _receipts = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // ปรับชื่อฟังก์ชันให้ตรงกับ Repository (getPatient)
      final p = await repo.getPatient(widget.patientId);
      final receipts = await repo.listStockOutReceiptsForPatientName(p.fullName);

      setState(() {
        _p = p;
        _receipts = receipts;
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _fmtDateTime(String iso) {
    final d = DateTime.tryParse(iso);
    if (d == null) return iso;
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} '
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FB),
      appBar: AppBar(
        backgroundColor: cs.primary,
        foregroundColor: Colors.white,
        title: const Text('ข้อมูลผู้ป่วย & ประวัติ'),
        actions: [
          IconButton(
            tooltip: 'รีเฟรช',
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : (_error != null)
              ? Center(child: Text('โหลดไม่สำเร็จ: $_error'))
              : (_p == null)
                  ? const Center(child: Text('ไม่พบผู้ป่วย'))
                  : Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 980),
                        child: ListView(
                          padding: const EdgeInsets.all(16),
                          children: [
                            _patientCard(_p!),
                            const SizedBox(height: 12),
                            _historyCard(),
                          ],
                        ),
                      ),
                    ),
    );
  }

  Widget _patientCard(Patient p) {
    final age = p.age;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(p.fullName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              // นำ _pill('รหัส: ${p.patientCode}') ออกแล้ว
              if ((p.nationalId ?? '').trim().isNotEmpty) _pill('บัตร: ${p.nationalId}'),
              if (age != null) _pill('อายุ: $age ปี'),
              if ((p.bloodGroup ?? '').trim().isNotEmpty) _pill('กรุ๊ปเลือด: ${p.bloodGroup}'),
              if ((p.phone ?? '').trim().isNotEmpty) _pill('โทร: ${p.phone}'),
            ],
          ),
          const SizedBox(height: 10),
          if ((p.address ?? '').trim().isNotEmpty)
            Text('ที่อยู่: ${p.address}', style: TextStyle(color: Colors.black.withOpacity(0.65))),
          if (p.drugAllergies.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('แพ้ยา: ${p.drugAllergies.join(', ')}', style: const TextStyle(fontWeight: FontWeight.w700)),
          ],
          if (p.chronicConditions.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('โรคประจำตัว: ${p.chronicConditions.join(', ')}', style: const TextStyle(fontWeight: FontWeight.w700)),
          ],
        ]),
      ),
    );
  }

  Widget _historyCard() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('ประวัติการจ่ายยา (จาก StockOut)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          if (_receipts.isEmpty)
            Text('ยังไม่มีประวัติ', style: TextStyle(color: Colors.black.withOpacity(0.6)))
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _receipts.length,
              separatorBuilder: (_, __) => const Divider(height: 18),
              itemBuilder: (_, i) {
                final r = _receipts[i];
                final id = (r['id'] ?? '').toString();
                final createdAt = (r['created_at'] ?? '').toString();
                final note = (r['note'] ?? '').toString();

                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(_fmtDateTime(createdAt), style: const TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: Text(note.isEmpty ? '—' : note),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () async {
                    try {
                      final items = await repo.listStockOutItemsByReceipt(id);
                      if (!mounted) return;
                      showModalBottomSheet(
                        context: context,
                        isScrollControlled: true,
                        shape: const RoundedRectangleBorder(
                          borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
                        ),
                        builder: (_) => _ReceiptItemsSheet(items: items),
                      );
                    } catch (e) {
                      _toast('โหลดรายการยาในบิลไม่สำเร็จ: $e');
                    }
                  },
                );
              },
            ),
        ]),
      ),
    );
  }

  Widget _pill(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.04),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(text, style: const TextStyle(fontWeight: FontWeight.w700)),
    );
  }
}

class _ReceiptItemsSheet extends StatelessWidget {
  final List<Map<String, dynamic>> items;
  const _ReceiptItemsSheet({required this.items});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 44,
              height: 5,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.15),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            const Text('รายการยาในบิล', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
            const SizedBox(height: 10),
            if (items.isEmpty)
              Text('ไม่มีรายการ', style: TextStyle(color: Colors.black.withOpacity(0.6)))
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const Divider(height: 14),
                  itemBuilder: (_, i) {
                    final it = items[i];
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        'Lot ${it['lot_no'] ?? '-'} • EXP ${it['exp_date'] ?? '-'}',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      subtitle: Text(
                        'qty_base: ${it['qty_base'] ?? '-'} • sell/base: ${it['sell_per_base'] ?? '-'} • total: ${it['line_total'] ?? '-'}',
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}