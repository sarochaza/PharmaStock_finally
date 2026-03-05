// lib/core/patients/patient_orders_history_page.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../supabase_guard.dart';
import 'patient_model.dart';
import 'patient_repository.dart';
import 'patient_picker.dart';
import 'patient_detail_page.dart';

class PatientOrdersHistoryPage extends StatefulWidget {
  final Patient? initialPatient;

  const PatientOrdersHistoryPage({super.key, this.initialPatient});

  @override
  State<PatientOrdersHistoryPage> createState() => _PatientOrdersHistoryPageState();
}

class _PatientOrdersHistoryPageState extends State<PatientOrdersHistoryPage> {
  SupabaseClient? _sb;

  bool _loading = true;
  String? _error;

  PatientRepository? _repo;

  List<Patient> _patients = [];
  Patient? _selectedPatient;

  final TextEditingController _searchCtl = TextEditingController();
  String _q = '';

  // receipts (พร้อม items)
  List<_ReceiptBundle> _bundles = [];

  @override
  void initState() {
    super.initState();
    _sb = getSupabaseClientOrNull();
    if (_sb == null) {
      _loading = false;
      _error = 'ยังไม่ได้เชื่อมต่อ Supabase';
      return;
    }
    _repo = PatientRepository(_sb!);

    _searchCtl.addListener(() {
      setState(() => _q = _searchCtl.text.trim().toLowerCase());
    });

    _selectedPatient = widget.initialPatient;

    _bootstrap();
  }

  @override
  void dispose() {
    _searchCtl.dispose();
    super.dispose();
  }

  String _ownerId() {
    final u = _sb!.auth.currentUser;
    if (u == null) throw Exception('ยังไม่ได้ล็อกอิน');
    return u.id;
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _bootstrap() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await _loadPatients();

      // ✅ ถ้ามี initialPatient แต่ไม่ได้อยู่ใน list (เช่นมาจากหน้าอื่น) ให้ normalize ให้เป็น object จาก list ถ้าเจอ
      if (_selectedPatient != null && _patients.isNotEmpty) {
        final hit = _patients.where((p) => p.id == _selectedPatient!.id).toList();
        if (hit.isNotEmpty) _selectedPatient = hit.first;
      }

      await _loadOrders();
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadPatients() async {
    if (_repo == null) return;
    final list = await _repo!.listPatients();
    if (!mounted) return;
    setState(() => _patients = list);
  }

  /// ✅ โหลดประวัติการจ่ายยา
  /// - เลือกคนไข้ได้ 2 แบบ:
  ///   1) ถ้ามี patient.id ใช้ patient_id (เร็วและถูกต้อง)
  ///   2) ถ้าอยากใช้ national_id ก็รองรับ: หา patient.id ก่อนแล้วค่อย filter
Future<void> _loadOrders() async {
  final ownerId = _ownerId();

  // ✅ เริ่มเป็น FilterBuilder ก่อน (ยังไม่ order)
  var q = _sb!
      .from('stock_out_receipts')
      .select(
        'id, patient_id, patient_name, note, sold_at, created_at, '
        'stock_out_items(qty_base, sell_per_base, line_total, lot_no, exp_date, '
        'drug:drugs(id, generic_name, code, base_unit))',
      )
      .eq('owner_id', ownerId);

  // ✅ filter by patient (รองรับทั้ง id และ national_id)
  if (_selectedPatient != null) {
    final pid = (_selectedPatient!.id).trim();

    if (pid.isNotEmpty) {
      q = q.eq('patient_id', pid);
    } else {
      // fallback: ใช้ national_id หา id แล้วค่อย filter
      final nat = (_selectedPatient!.nationalId ?? '').trim();
      if (nat.isNotEmpty) {
        final p = await _sb!
            .from('patients')
            .select('id')
            .eq('owner_id', ownerId)
            .eq('national_id', nat)
            .maybeSingle();

        final foundId = (p?['id'] ?? '').toString();
        if (foundId.isNotEmpty) {
          q = q.eq('patient_id', foundId);
        }
      }
    }
  }

  // ✅ ค่อย order ตอนท้าย แล้วค่อย await
  final rows = await q.order('sold_at', ascending: false);

  final bundles = <_ReceiptBundle>[];
  for (final r in (rows as List)) {
    final receiptId = (r['id'] ?? '').toString();
    if (receiptId.isEmpty) continue;

    final soldAt = (r['sold_at'] ?? r['created_at'] ?? '').toString();
    final patientName = (r['patient_name'] ?? '').toString();
    final note = (r['note'] ?? '').toString().trim();

    final itemsRaw = (r['stock_out_items'] as List?) ?? const [];
    final items = <_ReceiptItem>[];

    for (final it in itemsRaw) {
      if (it is! Map) continue;

      final qtyBase = (it['qty_base'] is num) ? (it['qty_base'] as num) : 0;
      final sellPerBase = (it['sell_per_base'] is num) ? (it['sell_per_base'] as num) : null;
      final lineTotal = (it['line_total'] is num) ? (it['line_total'] as num) : null;
      final lotNo = (it['lot_no'] ?? '').toString();
      final expDate = (it['exp_date'] ?? '').toString();

      final drug = it['drug'] as Map<String, dynamic>?;
      final drugName = (drug?['generic_name'] ?? '').toString();
      final drugCode = (drug?['code'] ?? '').toString();
      final baseUnit = (drug?['base_unit'] ?? '').toString();

      items.add(_ReceiptItem(
        drugName: drugName.isEmpty ? '-' : drugName,
        drugCode: drugCode,
        baseUnit: baseUnit,
        qtyBase: qtyBase,
        sellPerBase: sellPerBase,
        lineTotal: lineTotal,
        lotNo: lotNo,
        expDate: expDate,
      ));
    }

    bundles.add(_ReceiptBundle(
      receiptId: receiptId,
      soldAtIso: soldAt,
      patientName: patientName,
      note: note.isEmpty ? null : note,
      items: items,
    ));
  }

  if (!mounted) return;
  setState(() => _bundles = bundles);
}

  List<_ReceiptBundle> get _filteredBundles {
    if (_q.isEmpty) return _bundles;
    return _bundles.where((b) {
      final p = b.patientName.toLowerCase();
      final n = (b.note ?? '').toLowerCase();
      final hitItem = b.items.any((it) {
        final dn = it.drugName.toLowerCase();
        final dc = it.drugCode.toLowerCase();
        return dn.contains(_q) || dc.contains(_q);
      });
      return p.contains(_q) || n.contains(_q) || hitItem;
    }).toList();
  }

  String _fmtDateTime(String iso) {
    try {
      final d = DateTime.parse(iso).toLocal();
      final y = d.year.toString().padLeft(4, '0');
      final m = d.month.toString().padLeft(2, '0');
      final day = d.day.toString().padLeft(2, '0');
      final hh = d.hour.toString().padLeft(2, '0');
      final mm = d.minute.toString().padLeft(2, '0');
      return '$day/$m/$y $hh:$mm';
    } catch (_) {
      return iso;
    }
  }

  num _bundleTotal(_ReceiptBundle b) {
    num sum = 0;
    for (final it in b.items) {
      if (it.lineTotal != null) {
        sum += it.lineTotal!;
      } else if (it.sellPerBase != null) {
        sum += it.qtyBase * it.sellPerBase!;
      }
    }
    return sum;
  }

  @override
  Widget build(BuildContext context) {
    final list = _filteredBundles;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FB),
      appBar: AppBar(
        title: const Text('ประวัติการจ่ายยา / การสั่งซื้อ'),
        centerTitle: true,
        backgroundColor: const Color(0xFF1976D2),
        foregroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        actions: [
          IconButton(
            tooltip: 'รีเฟรช',
            onPressed: () async {
              await _loadOrders();
              _toast('อัปเดตแล้ว');
            },
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : (_error != null)
              ? Center(
                  child: Text(
                    'เกิดข้อผิดพลาด:\n$_error',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey.shade700),
                  ),
                )
              : Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 980),
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        _buildFilterCard(),
                        const SizedBox(height: 12),
                        if (list.isEmpty) _emptyState() else ...list.map(_receiptCard),
                      ],
                    ),
                  ),
                ),
    );
  }

  Widget _buildFilterCard() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text(
            'ค้นหา & เลือกคนไข้',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 10),

          PatientPicker(
            patients: _patients,
            value: _selectedPatient,
            onChanged: (p) async {
              setState(() => _selectedPatient = p);
              await _loadOrders();
            },
          ),

          const SizedBox(height: 10),

          TextField(
            controller: _searchCtl,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search_rounded),
              hintText: 'ค้นหาจากชื่อคนไข้ / ชื่อยา / รหัสยา / หมายเหตุ',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              filled: true,
              fillColor: Colors.white,
              suffixIcon: _q.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear_rounded),
                      onPressed: () => _searchCtl.clear(),
                    ),
            ),
          ),

          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _pill(
                  _selectedPatient == null ? 'ทั้งหมด' : 'เฉพาะ: ${_selectedPatient!.fullName}',
                  strong: true,
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                height: 46,
                child: OutlinedButton.icon(
                  onPressed: _selectedPatient == null
                      ? null
                      : () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => PatientDetailPage(patientId: _selectedPatient!.id),
                            ),
                          );
                        },
                  icon: const Icon(Icons.person_rounded),
                  label: const Text('ข้อมูลคนไข้'),
                ),
              ),
            ],
          ),
        ]),
      ),
    );
  }

  Widget _emptyState() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          children: [
            Icon(Icons.history_rounded, size: 44, color: Colors.grey.shade400),
            const SizedBox(height: 10),
            Text(
              'ยังไม่มีประวัติการจ่ายยา',
              style: TextStyle(color: Colors.grey.shade700, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              _selectedPatient == null ? 'ลองไปทำรายการจ่ายยา แล้วกลับมาดูได้' : 'คนไข้คนนี้ยังไม่เคยมีรายการจ่ายยา',
              style: TextStyle(color: Colors.grey.shade600),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _receiptCard(_ReceiptBundle b) {
    final total = _bundleTotal(b);

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  b.patientName.isEmpty ? 'ไม่ระบุชื่อคนไข้' : b.patientName,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              _pill('รวม ${total.toStringAsFixed(2)} ฿', strong: true),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'เวลา: ${_fmtDateTime(b.soldAtIso)} • ${b.items.length} รายการ',
            style: TextStyle(color: Colors.grey.shade700),
          ),
          if ((b.note ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.04),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                b.note!,
                style: TextStyle(color: Colors.grey.shade800, height: 1.35),
              ),
            ),
          ],
          const SizedBox(height: 10),

          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            childrenPadding: EdgeInsets.zero,
            title: const Text(
              'ดูรายการยาที่จ่าย',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
            children: [
              const Divider(height: 18),
              ...b.items.map((it) => _itemRow(it)).toList(),
            ],
          ),
        ]),
      ),
    );
  }

  Widget _itemRow(_ReceiptItem it) {
    final total = it.lineTotal ?? ((it.sellPerBase ?? 0) * it.qtyBase);

    final title = it.drugCode.trim().isEmpty ? it.drugName : '${it.drugName} (${it.drugCode})';

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.medication_outlined, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.w900),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                'จำนวน: ${_fmtNum(it.qtyBase)} ${it.baseUnit.isEmpty ? 'หน่วยฐาน' : it.baseUnit}'
                '${it.sellPerBase != null ? ' • ราคา/ฐาน ${it.sellPerBase!.toStringAsFixed(2)}' : ''}',
                style: TextStyle(color: Colors.grey.shade700),
              ),
              if (it.lotNo.trim().isNotEmpty || it.expDate.trim().isNotEmpty)
                Text(
                  'Lot: ${it.lotNo.isEmpty ? '-' : it.lotNo} • EXP: ${it.expDate.isEmpty ? '-' : it.expDate}',
                  style: TextStyle(color: Colors.grey.shade600),
                ),
            ]),
          ),
          const SizedBox(width: 10),
          Text(
            total.toStringAsFixed(2),
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }

  String _fmtNum(num v) => (v % 1 == 0) ? v.toInt().toString() : v.toStringAsFixed(2);

  Widget _pill(String text, {bool strong = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: strong ? const Color(0xFFE6F7EC) : const Color(0xFFEAF2FF),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontWeight: strong ? FontWeight.w800 : FontWeight.w600,
          color: strong ? const Color(0xFF0F7A3B) : const Color(0xFF2158B6),
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

// ===============================
// Models (local-only)
// ===============================

class _ReceiptBundle {
  final String receiptId;
  final String soldAtIso;
  final String patientName;
  final String? note;
  final List<_ReceiptItem> items;

  _ReceiptBundle({
    required this.receiptId,
    required this.soldAtIso,
    required this.patientName,
    required this.note,
    required this.items,
  });
}

class _ReceiptItem {
  final String drugName;
  final String drugCode;
  final String baseUnit;

  final num qtyBase;
  final num? sellPerBase;
  final num? lineTotal;

  final String lotNo;
  final String expDate;

  _ReceiptItem({
    required this.drugName,
    required this.drugCode,
    required this.baseUnit,
    required this.qtyBase,
    required this.sellPerBase,
    required this.lineTotal,
    required this.lotNo,
    required this.expDate,
  });
}