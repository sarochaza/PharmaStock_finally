// lib/pages/logs_page.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class LogsPage extends StatefulWidget {
  const LogsPage({super.key});

  @override
  State<LogsPage> createState() => _LogsPageState();
}

class _LogsPageState extends State<LogsPage> {
  late final SupabaseClient sb = Supabase.instance.client;

  bool _loading = true;
  String? _err;

  final TextEditingController _searchCtl = TextEditingController();
  String _q = '';

  _LogFilter _filter = _LogFilter.all;

  // “แสดง 50 รายการ”
  final List<int> _pageSizes = const [20, 50, 100, 200];
  int _pageSize = 50;

  // raw + filtered
  List<_LogRow> _all = [];

  @override
  void initState() {
    super.initState();
    _searchCtl.addListener(() {
      setState(() => _q = _searchCtl.text.trim().toLowerCase());
    });
    _load();
  }

  @override
  void dispose() {
    _searchCtl.dispose();
    super.dispose();
  }

  String _ownerId() {
    final u = sb.auth.currentUser;
    if (u == null) throw Exception('ยังไม่ได้ล็อกอิน');
    return u.id;
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // =========================
  // Load logs (build from existing tables)
  // =========================

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _err = null;
    });

    try {
      final ownerId = _ownerId();

      // preload drugs map (id -> name/code/base_unit)
      final dRows = await sb
          .from('drugs')
          .select('id, generic_name, code, base_unit, created_at, updated_at')
          .eq('owner_id', ownerId);

      final drugMap = <String, _DrugMini>{};
      if (dRows is List) {
        for (final rr in dRows) {
          final r = rr as Map;
          final id = (r['id'] ?? '').toString();
          if (id.isEmpty) continue;
          drugMap[id] = _DrugMini(
            id: id,
            name: (r['generic_name'] ?? '').toString(),
            code: (r['code'] ?? '').toString(),
            baseUnit: (r['base_unit'] ?? '').toString(),
            createdAt: (r['created_at'] ?? '').toString(),
            updatedAt: (r['updated_at'] ?? '').toString(),
          );
        }
      }

      // IN receipts
      final inReceipts = await sb
          .from('stock_in_receipts')
          .select('id, created_at, received_at, supplier_name, delivery_note_no, invoice_no, po_no, note')
          .eq('owner_id', ownerId)
          .order('created_at', ascending: false)
          .limit(500);

      // OUT receipts
      final outReceipts = await sb
          .from('stock_out_receipts')
          .select('id, created_at, sold_at, patient_name, note')
          .eq('owner_id', ownerId)
          .order('created_at', ascending: false)
          .limit(500);

      final logs = <_LogRow>[];

      // Build IN logs (1 receipt = 1 log row) + summary from items
      if (inReceipts is List) {
        for (final rr in inReceipts) {
          final r = rr as Map;

          final rid = (r['id'] ?? '').toString();
          final createdAt = (r['created_at'] ?? '').toString();
          final receivedAt = (r['received_at'] ?? '').toString();

          final at = DateTime.tryParse(receivedAt.isNotEmpty ? receivedAt : createdAt) ?? DateTime.now();

          final supplier = (r['supplier_name'] ?? '').toString();
          final dn = (r['delivery_note_no'] ?? '').toString();
          final inv = (r['invoice_no'] ?? '').toString();
          final po = (r['po_no'] ?? '').toString();
          final note = (r['note'] ?? '').toString();

          // items summary
          final items = await sb
              .from('stock_in_items')
              .select('drug_id, lot_no, exp_date, base_qty, sell_per_base, cost_per_base')
              .eq('owner_id', ownerId)
              .eq('receipt_id', rid);

          int itemCount = 0;
          num sumBaseQty = 0;
          num costTotal = 0;
          num sellTotal = 0;

          String? firstDrugName;
          String? firstDrugCode;
          String? firstLot;
          String? firstExp;
          num? firstSellPerBase;

          if (items is List && items.isNotEmpty) {
            itemCount = items.length;
            for (int i = 0; i < items.length; i++) {
              final it = items[i] as Map;
              final baseQty = (it['base_qty'] is num) ? (it['base_qty'] as num) : 0;
              sumBaseQty += baseQty;

              final cpb = it['cost_per_base'];
              final spb = it['sell_per_base'];
              if (cpb is num) costTotal += baseQty * cpb;
              if (spb is num) sellTotal += baseQty * spb;

              if (i == 0) {
                final drugId = (it['drug_id'] ?? '').toString();
                final dm = drugMap[drugId];
                firstDrugName = dm?.name;
                firstDrugCode = dm?.code;
                firstLot = (it['lot_no'] ?? '').toString();
                firstExp = (it['exp_date'] ?? '').toString();
                firstSellPerBase = (it['sell_per_base'] is num) ? (it['sell_per_base'] as num) : null;
              }
            }
          }

          final head = supplier.trim().isEmpty ? 'รับเข้า' : 'รับเข้า: $supplier';

          final parts = <String>[];
          if (dn.trim().isNotEmpty) parts.add('DN $dn');
          if (inv.trim().isNotEmpty) parts.add('INV $inv');
          if (po.trim().isNotEmpty) parts.add('PO $po');

          final sub = parts.isEmpty ? '' : ' • ${parts.join(' • ')}';

          String detail = '';
          if (firstDrugName != null && firstDrugName!.trim().isNotEmpty) {
            final code = (firstDrugCode ?? '').trim();
            final nameWithCode = code.isEmpty ? firstDrugName! : '${firstDrugName!} ($code)';
            final lotStr = (firstLot ?? '').trim().isEmpty ? '' : ' lot ${firstLot!}';
            final expStr = (firstExp ?? '').trim().isEmpty ? '' : ' • หมดอายุ ${firstExp!.substring(0, 10)}';
            final sellStr = (firstSellPerBase == null)
                ? ''
                : ' • ราคาขายตั้งไว้ ${firstSellPerBase!.toStringAsFixed(2)} บาท/หน่วยฐาน';
            detail = '$nameWithCode$lotStr + ${_fmtNum(sumBaseQty)} หน่วยฐาน • $itemCount รายการ$expStr$sellStr';
          } else {
            detail = 'รวม $itemCount รายการ • รวม ${_fmtNum(sumBaseQty)} หน่วยฐาน';
          }

          logs.add(_LogRow(
            kind: _LogKind.stockIn,
            at: at,
            title: '$head$sub',
            detail: detail,
            note: note.trim().isEmpty ? null : note.trim(),
            rawId: rid,
            badgeUser: 'admin',
            moneyHint: _MoneyHint.inBoth(costTotal: costTotal, sellTotal: sellTotal),
          ));
        }
      }

      // Build OUT logs (1 receipt = 1 log row)
      if (outReceipts is List) {
        for (final rr in outReceipts) {
          final r = rr as Map;

          final rid = (r['id'] ?? '').toString();
          final createdAt = (r['created_at'] ?? '').toString();
          final soldAt = (r['sold_at'] ?? '').toString();
          final at = DateTime.tryParse(soldAt.isNotEmpty ? soldAt : createdAt) ?? DateTime.now();

          final patient = (r['patient_name'] ?? '').toString();
          final note = (r['note'] ?? '').toString();

          final items = await sb
              .from('stock_out_items')
              .select('drug_id, lot_no, exp_date, qty_base, sell_per_base, line_total')
              .eq('owner_id', ownerId)
              .eq('receipt_id', rid);

          int itemCount = 0;
          num total = 0;

          String? firstDrugName;
          String? firstDrugCode;
          String? firstLot;
          String? firstExp;
          num? firstQtyBase;

          if (items is List && items.isNotEmpty) {
            itemCount = items.length;
            for (int i = 0; i < items.length; i++) {
              final it = items[i] as Map;
              final lt = it['line_total'];
              if (lt is num) total += lt;

              if (i == 0) {
                final drugId = (it['drug_id'] ?? '').toString();
                final dm = drugMap[drugId];
                firstDrugName = dm?.name;
                firstDrugCode = dm?.code;
                firstLot = (it['lot_no'] ?? '').toString();
                firstExp = (it['exp_date'] ?? '').toString();
                firstQtyBase = (it['qty_base'] is num) ? (it['qty_base'] as num) : null;
              }
            }
          }

          final head = patient.trim().isEmpty ? 'จ่ายออก' : 'จ่ายออก: $patient';

          String detail = '';
          if (firstDrugName != null && firstDrugName!.trim().isNotEmpty) {
            final code = (firstDrugCode ?? '').trim();
            final nameWithCode = code.isEmpty ? firstDrugName! : '${firstDrugName!} ($code)';
            final lotStr = (firstLot ?? '').trim().isEmpty ? '' : ' lot ${firstLot!}';
            final expStr = (firstExp ?? '').trim().isNotEmpty ? ' • EXP ${firstExp!.substring(0, 10)}' : '';
            final qtyStr = (firstQtyBase == null) ? '' : ' • จ่าย ${firstQtyBase!.toStringAsFixed(0)} หน่วยฐาน';
            detail = '$nameWithCode$lotStr$qtyStr$expStr • $itemCount รายการ • รวม ${total.toStringAsFixed(2)} ฿';
          } else {
            detail = 'รวม $itemCount รายการ • รวม ${total.toStringAsFixed(2)} ฿';
          }

          logs.add(_LogRow(
            kind: _LogKind.stockOut,
            at: at,
            title: head,
            detail: detail,
            note: note.trim().isEmpty ? null : note.trim(),
            rawId: rid,
            badgeUser: 'admin',
            moneyHint: _MoneyHint.outTotal(total: total),
          ));
        }
      }

      // Build drug logs
      for (final dm in drugMap.values) {
        final created = DateTime.tryParse(dm.createdAt);
        final updated = DateTime.tryParse(dm.updatedAt);

        if (created != null) {
          logs.add(_LogRow(
            kind: _LogKind.drugAdd,
            at: created,
            title: 'เพิ่มยา: ${_nameWithCode(dm.name, dm.code)}',
            detail: 'เพิ่มรายการยาใหม่ • หน่วยฐาน ${dm.baseUnit}',
            note: null,
            rawId: dm.id,
            badgeUser: 'admin',
          ));
        }

        if (updated != null && created != null) {
          final diff = updated.difference(created).inSeconds.abs();
          if (diff >= 3) {
            logs.add(_LogRow(
              kind: _LogKind.drugEdit,
              at: updated,
              title: 'แก้ไขยา: ${_nameWithCode(dm.name, dm.code)}',
              detail: 'แก้ไขข้อมูลยา • หน่วยฐาน ${dm.baseUnit}',
              note: null,
              rawId: dm.id,
              badgeUser: 'admin',
            ));
          }
        }
      }

      logs.sort((a, b) => b.at.compareTo(a.at));

      if (!mounted) return;
      setState(() {
        _all = logs;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _err = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // =========================
  // Export / Clear
  // =========================

  Future<void> _exportTxt() async {
    final list = _filtered.take(_pageSize).toList();
    if (list.isEmpty) {
      _toast('ไม่มีข้อมูลให้ส่งออก');
      return;
    }

    final buf = StringBuffer();
    for (final l in list) {
      buf.writeln('${_fmtDateTime(l.at)} • ผู้ใช้: ${l.badgeUser}');
      buf.writeln('${l.title}');
      buf.writeln('${l.detail}');
      if ((l.note ?? '').trim().isNotEmpty) {
        buf.writeln('หมายเหตุ: ${l.note}');
      }
      buf.writeln('---');
    }

    await Clipboard.setData(ClipboardData(text: buf.toString()));
    _toast('คัดลอกข้อความ Log แล้ว (นำไปวางเป็น .txt ได้เลย)');
  }

  void _clearFilters() {
    _searchCtl.clear();
    setState(() {
      _filter = _LogFilter.all;
      _pageSize = 50;
    });
  }

  Future<void> _dangerDeleteAllStockHistory() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('ลบประวัติ Stock ทั้งหมด?'),
        content: const Text(
          'จะลบข้อมูล stock_in/out receipts และ items ทั้งหมดของบัญชีนี้\n'
          'ข้อมูลจะหายถาวร (แนะนำให้สำรองก่อน)',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('ยกเลิก')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('ลบทั้งหมด'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    try {
      final ownerId = _ownerId();

      await sb.from('stock_in_items').delete().eq('owner_id', ownerId);
      await sb.from('stock_in_receipts').delete().eq('owner_id', ownerId);

      await sb.from('stock_out_items').delete().eq('owner_id', ownerId);
      await sb.from('stock_out_receipts').delete().eq('owner_id', ownerId);

      _toast('ลบประวัติ Stock ทั้งหมดแล้ว');
      await _load();
    } catch (e) {
      _toast('ลบไม่สำเร็จ: $e');
    }
  }

  // =========================
  // Filtering
  // =========================

  List<_LogRow> get _filtered {
    final q = _q;
    final f = _filter;

    bool matchKind(_LogRow r) {
      switch (f) {
        case _LogFilter.all:
          return true;
        case _LogFilter.inOnly:
          return r.kind == _LogKind.stockIn;
        case _LogFilter.outOnly:
          return r.kind == _LogKind.stockOut;
        case _LogFilter.drugOnly:
          return r.kind == _LogKind.drugAdd || r.kind == _LogKind.drugEdit;
      }
    }

    bool matchSearch(_LogRow r) {
      if (q.isEmpty) return true;
      final s = [
        r.title,
        r.detail,
        r.note ?? '',
        r.badgeUser,
      ].join(' ').toLowerCase();
      return s.contains(q);
    }

    return _all.where((r) => matchKind(r) && matchSearch(r)).toList();
  }

  // =========================
  // UI (แก้ให้ไม่ overflow)
  // =========================

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_err != null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Phamory • Logs'),
          backgroundColor: cs.primary,
          foregroundColor: Colors.white,
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Text('โหลดไม่สำเร็จ: $_err'),
          ),
        ),
      );
    }

    final list = _filtered;
    final shown = list.take(_pageSize).toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FB),
      appBar: AppBar(
        backgroundColor: cs.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'รีเฟรช',
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'delete_all') await _dangerDeleteAllStockHistory();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'delete_all', child: Text('ลบประวัติ Stock ทั้งหมด')),
            ],
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: LayoutBuilder(
                builder: (context, c) {
                  final isNarrow = c.maxWidth < 720; // จุดตัดมือถือ/จอแคบ
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('ประวัติการทำรายการ', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                      const SizedBox(height: 6),
                      Text(
                        'ค้นหา/กรอง/ล้าง หรือส่งออกเป็น .txt ได้',
                        style: TextStyle(color: Colors.black.withOpacity(0.55)),
                      ),
                      const SizedBox(height: 14),

                      // ✅ แถวค้นหา + page size (responsive)
                      if (isNarrow) ...[
                        TextField(
                          controller: _searchCtl,
                          decoration: InputDecoration(
                            prefixIcon: const Icon(Icons.search_rounded),
                            hintText: 'ค้นหาในประวัติ เช่น รับเข้า / จ่ายออก / ชื่อยา / lot',
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
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
                        DropdownButtonFormField<int>(
                          value: _pageSize,
                          isDense: true,
                          items: _pageSizes
                              .map((v) => DropdownMenuItem<int>(value: v, child: Text('แสดง $v รายการ')))
                              .toList(),
                          onChanged: (v) {
                            if (v == null) return;
                            setState(() => _pageSize = v);
                          },
                          decoration: InputDecoration(
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                            filled: true,
                            fillColor: Colors.white,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                          ),
                        ),
                      ] else ...[
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _searchCtl,
                                decoration: InputDecoration(
                                  prefixIcon: const Icon(Icons.search_rounded),
                                  hintText: 'ค้นหาในประวัติ เช่น รับเข้า / จ่ายออก / ชื่อยา / lot',
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
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
                            ),
                            const SizedBox(width: 12),
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 220),
                              child: DropdownButtonFormField<int>(
                                value: _pageSize,
                                isDense: true,
                                items: _pageSizes
                                    .map((v) => DropdownMenuItem<int>(value: v, child: Text('แสดง $v รายการ')))
                                    .toList(),
                                onChanged: (v) {
                                  if (v == null) return;
                                  setState(() => _pageSize = v);
                                },
                                decoration: InputDecoration(
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                                  filled: true,
                                  fillColor: Colors.white,
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],

                      const SizedBox(height: 12),

                      // ✅ ตัวกรอง + ปุ่ม (เปลี่ยนเป็น Wrap กันล้น)
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          _seg('ทั้งหมด', _filter == _LogFilter.all, () => setState(() => _filter = _LogFilter.all)),
                          _seg('รับเข้า', _filter == _LogFilter.inOnly, () => setState(() => _filter = _LogFilter.inOnly)),
                          _seg('จ่ายออก', _filter == _LogFilter.outOnly, () => setState(() => _filter = _LogFilter.outOnly)),
                          _seg(
                            'แก้ไข/เพิ่มยา',
                            _filter == _LogFilter.drugOnly,
                            () => setState(() => _filter = _LogFilter.drugOnly),
                          ),

                          // ขีดแบ่งเล็ก ๆ เวลาขึ้นบรรทัดใหม่จะยังดูเป็นกลุ่ม
                          SizedBox(width: isNarrow ? 0 : 12),

                          OutlinedButton.icon(
                            onPressed: _exportTxt,
                            icon: const Icon(Icons.upload_file_rounded),
                            label: const Text('ส่งออก .txt'),
                            style: OutlinedButton.styleFrom(
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            ),
                          ),
                          ElevatedButton(
                            onPressed: _clearFilters,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFEF4444),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            ),
                            child: const Text('ล้างทั้งหมด'),
                          ),
                        ],
                      ),

                      const SizedBox(height: 10),

                      Text(
                        'ทั้งหมด ${_all.length} รายการ • ตรงเงื่อนไข ${list.length} รายการ • แสดง ${shown.length} รายการ',
                        style: TextStyle(color: Colors.black.withOpacity(0.55), fontWeight: FontWeight.w700),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),

          const SizedBox(height: 14),

          if (shown.isEmpty)
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  children: [
                    const Icon(Icons.find_in_page_rounded, size: 48),
                    const SizedBox(height: 10),
                    const Text('ไม่พบรายการ', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                    const SizedBox(height: 6),
                    Text(
                      'ลองค้นหาด้วยคำอื่น หรือเปลี่ยนตัวกรอง',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.black.withOpacity(0.6)),
                    ),
                  ],
                ),
              ),
            )
          else
            Column(
              children: [
                for (final r in shown) _LogCard(row: r),
              ],
            ),
        ],
      ),
    );
  }

  Widget _seg(String label, bool active, VoidCallback onTap) {
    final cs = Theme.of(context).colorScheme;
    final bg = active ? cs.primary : Colors.white;
    final fg = active ? Colors.white : cs.primary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: cs.primary.withOpacity(0.22)),
        ),
        child: Text(label, style: TextStyle(fontWeight: FontWeight.w800, color: fg)),
      ),
    );
  }
}

// =========================
// UI Card
// =========================

class _LogCard extends StatelessWidget {
  final _LogRow row;
  const _LogCard({required this.row});

  @override
  Widget build(BuildContext context) {
    final color = row.kindColor;
    final icon = row.kindIcon;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${_fmtDateTime(row.at)} • ผู้ใช้: ${row.badgeUser}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Colors.black.withOpacity(0.55), fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(width: 10),
              _tag(row.kindLabel, color),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(row.title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                  const SizedBox(height: 6),
                  Text(
                    row.detail,
                    style: TextStyle(color: Colors.black.withOpacity(0.65), height: 1.35),
                  ),
                  if ((row.note ?? '').trim().isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      'หมายเหตุ: ${row.note}',
                      style: TextStyle(color: Colors.black.withOpacity(0.55), fontWeight: FontWeight.w700),
                    ),
                  ],
                  if (row.moneyHint != null) ...[
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: row.moneyHint!.chips(color),
                    ),
                  ],
                ]),
              ),
            ],
          ),
        ]),
      ),
    );
  }

  Widget _tag(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.20)),
      ),
      child: Text(text, style: TextStyle(fontWeight: FontWeight.w900, color: color)),
    );
  }
}

// =========================
// Models / Helpers
// =========================

enum _LogFilter { all, inOnly, outOnly, drugOnly }

enum _LogKind { stockIn, stockOut, drugAdd, drugEdit }

class _LogRow {
  final _LogKind kind;
  final DateTime at;
  final String title;
  final String detail;
  final String? note;
  final String rawId;
  final String badgeUser;
  final _MoneyHint? moneyHint;

  _LogRow({
    required this.kind,
    required this.at,
    required this.title,
    required this.detail,
    required this.rawId,
    required this.badgeUser,
    this.note,
    this.moneyHint,
  });

  String get kindLabel {
    switch (kind) {
      case _LogKind.stockIn:
        return 'รับเข้า';
      case _LogKind.stockOut:
        return 'จ่ายออก';
      case _LogKind.drugAdd:
        return 'เพิ่มยา';
      case _LogKind.drugEdit:
        return 'แก้ไขยา';
    }
  }

  IconData get kindIcon {
    switch (kind) {
      case _LogKind.stockIn:
        return Icons.download_rounded;
      case _LogKind.stockOut:
        return Icons.outbox_rounded;
      case _LogKind.drugAdd:
        return Icons.add_circle_outline_rounded;
      case _LogKind.drugEdit:
        return Icons.edit_rounded;
    }
  }

  Color get kindColor {
    switch (kind) {
      case _LogKind.stockIn:
        return const Color(0xFF16A34A);
      case _LogKind.stockOut:
        return const Color(0xFFEF4444);
      case _LogKind.drugAdd:
        return const Color(0xFF2158B6);
      case _LogKind.drugEdit:
        return const Color(0xFFF59E0B);
    }
  }
}

class _DrugMini {
  final String id;
  final String name;
  final String code;
  final String baseUnit;
  final String createdAt;
  final String updatedAt;

  _DrugMini({
    required this.id,
    required this.name,
    required this.code,
    required this.baseUnit,
    required this.createdAt,
    required this.updatedAt,
  });
}

class _MoneyHint {
  final num? costTotal;
  final num? sellTotal;
  final num? outTotal;

  _MoneyHint._({this.costTotal, this.sellTotal, this.outTotal});

  factory _MoneyHint.inBoth({required num costTotal, required num sellTotal}) {
    return _MoneyHint._(costTotal: costTotal, sellTotal: sellTotal);
  }

  factory _MoneyHint.outTotal({required num total}) {
    return _MoneyHint._(outTotal: total);
  }

  List<Widget> chips(Color accent) {
    final out = <Widget>[];

    Widget chip(String text, Color fg, Color bg) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: fg.withOpacity(0.15)),
        ),
        child: Text(text, style: TextStyle(fontWeight: FontWeight.w900, color: fg)),
      );
    }

    if (costTotal != null && sellTotal != null) {
      out.add(chip('ทุนรวม ${costTotal!.toStringAsFixed(2)} ฿', Colors.black87, Colors.black.withOpacity(0.05)));
      out.add(chip('ขายรวม ${sellTotal!.toStringAsFixed(2)} ฿', const Color(0xFF0F7A3B), const Color(0xFFE6F7EC)));
    }

    if (outTotal != null) {
      out.add(chip('รวม ${outTotal!.toStringAsFixed(2)} ฿', accent, accent.withOpacity(0.10)));
    }

    return out;
  }
}

String _nameWithCode(String name, String code) {
  final c = code.trim();
  if (c.isEmpty) return name;
  return '$name ($c)';
}

String _fmtNum(num v) => (v % 1 == 0) ? v.toInt().toString() : v.toStringAsFixed(2);

String _fmtDateTime(DateTime d) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${d.day}/${d.month}/${d.year + 543} ${two(d.hour)}:${two(d.minute)}:${two(d.second)}';
}