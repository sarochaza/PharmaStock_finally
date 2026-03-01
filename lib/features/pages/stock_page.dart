// lib/pages/stock_page.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../stock/stock_in_page.dart';
import '../stock/stock_out_page.dart';

class StockPage extends StatefulWidget {
  const StockPage({super.key});

  @override
  State<StockPage> createState() => _StockPageState();
}

class _StockPageState extends State<StockPage> with SingleTickerProviderStateMixin {
  late final SupabaseClient sb = Supabase.instance.client;

  late final TabController _tab;

  bool _loading = true;
  String? _err;

  // ===== overview metrics =====
  int _lowStockCount = 0;
  int _outOfStockCount = 0;
  int _expiringSoonLots = 0;
  int _expiredLots = 0;

  // ===== recent activity (history preview) =====
  List<_TxnRow> _recent = [];

  // ===== history =====
  final TextEditingController _historySearchCtl = TextEditingController();
  String _hq = '';

  _TxnTypeFilter _typeFilter = _TxnTypeFilter.all;
  _DateRangeFilter _rangeFilter = _DateRangeFilter.last7days;

  List<_TxnRow> _history = [];
  bool _loadingHistory = false;

  // ===== alerts =====
  bool _loadingAlerts = false;
  List<_LowStockRow> _lowStockRows = [];
  List<_LotAlertRow> _expiringRows = [];
  List<_LotAlertRow> _expiredRows = [];

  // ===== colors =====
  static const Color _inColor = Color(0xFF16A34A); // ✅ Green
  static const Color _outColor = Color(0xFFEF4444); // ✅ Red
  static const Color _brandBlue = Color(0xFF2158B6);

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);

    _historySearchCtl.addListener(() {
      setState(() => _hq = _historySearchCtl.text.trim().toLowerCase());
    });

    _bootstrap();
  }

  @override
  void dispose() {
    _tab.dispose();
    _historySearchCtl.dispose();
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

  Future<void> _bootstrap() async {
    setState(() {
      _loading = true;
      _err = null;
    });
    try {
      await Future.wait([
        _loadOverviewMetrics(),
        _loadRecent(limit: 5),
        _loadHistory(),
        _loadAlerts(),
      ]);
    } catch (e) {
      _err = e.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // =========================
  // OVERVIEW METRICS
  // =========================

  Future<void> _loadOverviewMetrics() async {
    final ownerId = _ownerId();

    final rows = await sb
        .from('v_drug_stock_summary')
        .select('drug_id, on_hand_base, reorder_point')
        .eq('owner_id', ownerId);

    int low = 0;
    int out = 0;
    if (rows is List) {
      for (final r in rows) {
        final onHand = (r['on_hand_base'] is num) ? (r['on_hand_base'] as num) : 0;
        final rp = (r['reorder_point'] is num) ? (r['reorder_point'] as num) : 0;

        if (onHand <= 0) {
          out++;
        } else if (rp > 0 && onHand <= rp) {
          low++;
        }
      }
    }

    final lots = await sb
        .from('drug_lots')
        .select('drug_id, exp_date, qty_on_hand_base')
        .eq('owner_id', ownerId);

    final drugs = await sb
        .from('drugs')
        .select('id, expire_warn_days')
        .eq('owner_id', ownerId);

    final warnMap = <String, int>{};
    if (drugs is List) {
      for (final d in drugs) {
        final id = (d['id'] ?? '').toString();
        if (id.isEmpty) continue;
        final warn = (d['expire_warn_days'] is int)
            ? (d['expire_warn_days'] as int)
            : int.tryParse((d['expire_warn_days'] ?? '').toString()) ?? 90;
        warnMap[id] = warn;
      }
    }

    int expSoon = 0;
    int expired = 0;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    if (lots is List) {
      for (final l in lots) {
        final qty = (l['qty_on_hand_base'] is num) ? (l['qty_on_hand_base'] as num) : 0;
        if (qty <= 0) continue;

        final drugId = (l['drug_id'] ?? '').toString();
        final expStr = (l['exp_date'] ?? '').toString();
        final exp = _parseDateOnly(expStr);
        if (exp == null) continue;

        if (exp.isBefore(today)) {
          expired++;
          continue;
        }

        final warnDays = warnMap[drugId] ?? 90;
        final warnDate = today.add(Duration(days: warnDays));

        if (!exp.isAfter(warnDate)) {
          expSoon++;
        }
      }
    }

    if (!mounted) return;
    setState(() {
      _lowStockCount = low;
      _outOfStockCount = out;
      _expiringSoonLots = expSoon;
      _expiredLots = expired;
    });
  }

  // =========================
  // HISTORY (MERGE IN + OUT)
  // =========================

  DateTime _rangeStart(_DateRangeFilter f) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    switch (f) {
      case _DateRangeFilter.today:
        return today;
      case _DateRangeFilter.last7days:
        return today.subtract(const Duration(days: 7));
      case _DateRangeFilter.thisMonth:
        return DateTime(now.year, now.month, 1);
      case _DateRangeFilter.last30days:
        return today.subtract(const Duration(days: 30));
    }
  }

  Future<void> _loadRecent({int limit = 5}) async {
    final ownerId = _ownerId();

    final inRows = await sb
        .from('stock_in_receipts')
        .select('id, created_at, received_at, supplier_name, delivery_note_no, invoice_no, po_no, note')
        .eq('owner_id', ownerId)
        .order('created_at', ascending: false)
        .limit(20);

    final outRows = await sb
        .from('stock_out_receipts')
        .select('id, created_at, sold_at, patient_name, note')
        .eq('owner_id', ownerId)
        .order('created_at', ascending: false)
        .limit(20);

    final merged = <_TxnRow>[];
    if (inRows is List) {
      for (final r in inRows) {
        merged.add(_TxnRow.fromInReceipt(Map<String, dynamic>.from(r as Map)));
      }
    }
    if (outRows is List) {
      for (final r in outRows) {
        merged.add(_TxnRow.fromOutReceipt(Map<String, dynamic>.from(r as Map)));
      }
    }

    merged.sort((a, b) => b.at.compareTo(a.at));
    final cut = merged.take(limit).toList();

    // เติม summary ให้ Recent ด้วย (เพื่อโชว์ทุน/ขาย/ยอดรวม)
    await _fillTxnSummaries(cut);

    if (!mounted) return;
    setState(() => _recent = cut);
  }

  Future<void> _loadHistory() async {
    setState(() => _loadingHistory = true);

    try {
      final ownerId = _ownerId();
      final start = _rangeStart(_rangeFilter);

      final inRows = await sb
          .from('stock_in_receipts')
          .select('id, created_at, received_at, supplier_name, delivery_note_no, invoice_no, po_no, note')
          .eq('owner_id', ownerId)
          .gte('created_at', start.toIso8601String())
          .order('created_at', ascending: false)
          .limit(200);

      final outRows = await sb
          .from('stock_out_receipts')
          .select('id, created_at, sold_at, patient_name, note')
          .eq('owner_id', ownerId)
          .gte('created_at', start.toIso8601String())
          .order('created_at', ascending: false)
          .limit(200);

      final merged = <_TxnRow>[];
      if (inRows is List) {
        for (final r in inRows) {
          merged.add(_TxnRow.fromInReceipt(Map<String, dynamic>.from(r as Map)));
        }
      }
      if (outRows is List) {
        for (final r in outRows) {
          merged.add(_TxnRow.fromOutReceipt(Map<String, dynamic>.from(r as Map)));
        }
      }

      final filteredByType = merged.where((t) {
        switch (_typeFilter) {
          case _TxnTypeFilter.all:
            return true;
          case _TxnTypeFilter.inOnly:
            return t.type == _TxnType.inTxn;
          case _TxnTypeFilter.outOnly:
            return t.type == _TxnType.outTxn;
        }
      }).toList();

      filteredByType.sort((a, b) => b.at.compareTo(a.at));

      final out = <_TxnRow>[];
      for (final t in filteredByType) {
        out.add(t);
      }

      await _fillTxnSummaries(out);

      if (!mounted) return;
      setState(() => _history = out);
    } catch (e) {
      _toast('โหลดประวัติไม่สำเร็จ: $e');
    } finally {
      if (mounted) setState(() => _loadingHistory = false);
    }
  }

  Future<void> _fillTxnSummaries(List<_TxnRow> txns) async {
    final ownerId = _ownerId();

    // NOTE: simple approach: query each receipt. OK for <=200.
    for (final t in txns) {
      if (t.type == _TxnType.inTxn) {
        final rows = await sb
            .from('stock_in_items')
            .select('id, base_qty, cost_per_base, sell_per_base')
            .eq('owner_id', ownerId)
            .eq('receipt_id', t.id);

        int count = 0;
        num costTotal = 0;
        num sellTotal = 0;

        if (rows is List) {
          count = rows.length;
          for (final rr in rows) {
            final r = rr as Map;
            final baseQty = (r['base_qty'] is num) ? (r['base_qty'] as num) : 0;

            final cpb = r['cost_per_base'];
            if (cpb is num) {
              costTotal += baseQty * cpb;
            }

            final spb = r['sell_per_base'];
            if (spb is num) {
              sellTotal += baseQty * spb;
            }
          }
        }

        t.itemCount = count;
        t.inCostTotal = costTotal;
        t.inSellTotal = sellTotal;
      } else {
        final rows = await sb
            .from('stock_out_items')
            .select('id, line_total')
            .eq('owner_id', ownerId)
            .eq('receipt_id', t.id);

        int count = 0;
        num total = 0;
        if (rows is List) {
          count = rows.length;
          for (final rr in rows) {
            final r = rr as Map;
            final v = r['line_total'];
            if (v is num) total += v;
          }
        }
        t.itemCount = count;
        t.totalAmount = total;
      }
    }
  }

  List<_TxnRow> get _filteredHistoryBySearch {
    final q = _hq;
    if (q.isEmpty) return _history;

    return _history.where((t) {
      final s = [
        t.title,
        t.subtitle ?? '',
        t.note ?? '',
        t.id,
      ].join(' ').toLowerCase();

      return s.contains(q);
    }).toList();
  }

  Future<void> _openTxnDetail(_TxnRow txn) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFFF4F7FB),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => _TxnDetailSheet(
        sb: sb,
        txn: txn,
        ownerId: sb.auth.currentUser?.id ?? '',
      ),
    );
  }

  // =========================
  // ALERTS
  // =========================

  Future<void> _loadAlerts() async {
    setState(() => _loadingAlerts = true);

    try {
      final ownerId = _ownerId();

      final sRows = await sb
          .from('v_drug_stock_summary')
          .select('drug_id, on_hand_base, reorder_point')
          .eq('owner_id', ownerId);

      final dRows = await sb
          .from('drugs')
          .select('id, generic_name, code, base_unit, expire_warn_days')
          .eq('owner_id', ownerId);

      final drugMap = <String, Map<String, dynamic>>{};
      if (dRows is List) {
        for (final d in dRows) {
          final id = (d['id'] ?? '').toString();
          if (id.isEmpty) continue;
          drugMap[id] = Map<String, dynamic>.from(d as Map);
        }
      }

      final lowList = <_LowStockRow>[];
      if (sRows is List) {
        for (final rr in sRows) {
          final r = rr as Map;
          final drugId = (r['drug_id'] ?? '').toString();
          final onHand = (r['on_hand_base'] is num) ? (r['on_hand_base'] as num) : 0;
          final rp = (r['reorder_point'] is num) ? (r['reorder_point'] as num) : 0;

          if (onHand <= 0 || (rp > 0 && onHand <= rp)) {
            final d = drugMap[drugId];
            if (d == null) continue;

            lowList.add(_LowStockRow(
              drugId: drugId,
              name: (d['generic_name'] ?? '').toString(),
              code: (d['code'] ?? '').toString(),
              baseUnit: (d['base_unit'] ?? '').toString(),
              onHandBase: onHand,
              reorderPoint: rp,
              isOut: onHand <= 0,
            ));
          }
        }
      }

      final lots = await sb
          .from('drug_lots')
          .select('drug_id, lot_no, exp_date, qty_on_hand_base')
          .eq('owner_id', ownerId);

      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);

      final expSoon = <_LotAlertRow>[];
      final expired = <_LotAlertRow>[];

      if (lots is List) {
        for (final ll in lots) {
          final l = ll as Map;
          final qty = (l['qty_on_hand_base'] is num) ? (l['qty_on_hand_base'] as num) : 0;
          if (qty <= 0) continue;

          final drugId = (l['drug_id'] ?? '').toString();
          final lotNo = (l['lot_no'] ?? '').toString();
          final expStr = (l['exp_date'] ?? '').toString();

          final exp = _parseDateOnly(expStr);
          if (exp == null) continue;

          final d = drugMap[drugId];
          if (d == null) continue;

          final warnDays = (d['expire_warn_days'] is int)
              ? (d['expire_warn_days'] as int)
              : int.tryParse((d['expire_warn_days'] ?? '').toString()) ?? 90;

          if (exp.isBefore(today)) {
            expired.add(_LotAlertRow(
              drugId: drugId,
              name: (d['generic_name'] ?? '').toString(),
              code: (d['code'] ?? '').toString(),
              baseUnit: (d['base_unit'] ?? '').toString(),
              lotNo: lotNo,
              expDate: expStr,
              qtyBase: qty,
              daysLeft: 0,
              kind: _LotAlertKind.expired,
            ));
          } else {
            final warnDate = today.add(Duration(days: warnDays));
            if (!exp.isAfter(warnDate)) {
              expSoon.add(_LotAlertRow(
                drugId: drugId,
                name: (d['generic_name'] ?? '').toString(),
                code: (d['code'] ?? '').toString(),
                baseUnit: (d['base_unit'] ?? '').toString(),
                lotNo: lotNo,
                expDate: expStr,
                qtyBase: qty,
                daysLeft: exp.difference(today).inDays,
                kind: _LotAlertKind.expiringSoon,
              ));
            }
          }
        }
      }

      expSoon.sort((a, b) => a.daysLeft.compareTo(b.daysLeft));
      expired.sort((a, b) => a.expDate.compareTo(b.expDate));
      lowList.sort((a, b) {
        if (a.isOut != b.isOut) return a.isOut ? -1 : 1;
        return a.onHandBase.compareTo(b.onHandBase);
      });

      if (!mounted) return;
      setState(() {
        _lowStockRows = lowList;
        _expiringRows = expSoon;
        _expiredRows = expired;
      });
    } catch (e) {
      _toast('โหลด Alerts ไม่สำเร็จ: $e');
    } finally {
      if (mounted) setState(() => _loadingAlerts = false);
    }
  }

  // =========================
  // Helpers
  // =========================

  DateTime? _parseDateOnly(String s) {
    if (s.length < 10) return null;
    final x = s.substring(0, 10); // YYYY-MM-DD
    final parts = x.split('-');
    if (parts.length != 3) return null;
    final y = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final d = int.tryParse(parts[2]);
    if (y == null || m == null || d == null) return null;
    return DateTime(y, m, d);
  }

  String _fmtNum(num v) => (v % 1 == 0) ? v.toInt().toString() : v.toStringAsFixed(2);

  // =========================
  // UI
  // =========================

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_err != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Text('โหลดไม่สำเร็จ: $_err'),
          ),
        ),
      );
    }

    return Scaffold(
  backgroundColor: const Color(0xFFF4F7FB),
  appBar: AppBar(
    backgroundColor: Theme.of(context).colorScheme.primary,
    foregroundColor: Colors.white,
    elevation: 0,

    // ✅ ซ่อนหัว AppBar (ไม่ให้มี Phamory ซ้อน)
    toolbarHeight: 0,
    title: null,
    centerTitle: false,

    actions: [
      IconButton(
        tooltip: 'รีเฟรช',
        onPressed: _bootstrap,
        icon: const Icon(Icons.refresh_rounded),
      ),
      const SizedBox(width: 6),
    ],
    bottom: TabBar(
      controller: _tab,
      indicatorColor: Colors.white,
      labelColor: Colors.white,
      unselectedLabelColor: Colors.white70,
      tabs: const [
        Tab(text: 'Overview'),
        Tab(text: 'History'),
        Tab(text: 'Alerts'),
      ],
    ),
  ),
  body: TabBarView(
    controller: _tab,
    children: [
      _buildOverview(Theme.of(context).colorScheme),
      _buildHistory(Theme.of(context).colorScheme),
      _buildAlerts(Theme.of(context).colorScheme),
    ],
  ),
);
  }

  Widget _buildOverview(ColorScheme cs) {
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        Row(
          children: [
            Expanded(
              child: _MetricCard(
                title: 'สต็อกต่ำ',
                value: _lowStockCount.toString(),
                subtitle: 'ต่ำกว่าเตือนขั้นต่ำ',
                icon: Icons.warning_amber_rounded,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _MetricCard(
                title: 'หมดสต็อก',
                value: _outOfStockCount.toString(),
                subtitle: 'คงเหลือ = 0',
                icon: Icons.block_rounded,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _MetricCard(
                title: 'ใกล้หมดอายุ',
                value: _expiringSoonLots.toString(),
                subtitle: 'ล็อตที่ยังมีของ',
                icon: Icons.hourglass_bottom_rounded,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _MetricCard(
                title: 'หมดอายุ',
                value: _expiredLots.toString(),
                subtitle: 'ควรแยกออก/ทำลาย',
                icon: Icons.event_busy_rounded,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // ✅ Stock In (Green)
        _StockActionCard(
          accent: _inColor,
          iconBg: const Color(0xFFEAF7EF),
          icon: Icons.download_rounded,
          title: 'รับยาเข้า (Stock In)',
          subtitle: 'เพิ่มล็อตยา + วันหมดอายุ + จำนวน\nรองรับ Pack → แปลงเป็นหน่วยฐานอัตโนมัติ',
          buttonText: 'เปิด',
         onPressed: () async {
  final changed = await Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => const StockInPage()),
  );

  if (changed == true) {
    await Future.wait([
      _loadOverviewMetrics(),
      _loadRecent(limit: 5),
      _loadHistory(),
      _loadAlerts(),
    ]);
    if (!mounted) return;
    setState(() {});
  }
},
        ),
        const SizedBox(height: 14),

        // ✅ Stock Out (Red)
        _StockActionCard(
          accent: _outColor,
          iconBg: const Color(0xFFFFECEC),
          icon: Icons.outbox_rounded,
          title: 'จ่ายยาออก (Stock Out)',
          subtitle: 'ทำบิลจ่ายยา (หลายรายการ)\nตัดล็อตอัตโนมัติแบบ FEFO + เก็บประวัติใบเสร็จ',
          buttonText: 'เปิด',
          onPressed: () async {
  final changed = await Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => const StockOutPage()),
  );

  if (changed == true) {
    await Future.wait([
      _loadOverviewMetrics(),
      _loadRecent(limit: 5),
      _loadHistory(),
      _loadAlerts(),
    ]);
    if (!mounted) return;
    setState(() {});
  }
},
        ),

        const SizedBox(height: 18),
        _SectionTitle(
          icon: Icons.bolt_rounded,
          title: 'Recent Activity',
          trailing: TextButton(
            onPressed: () => _tab.animateTo(1),
            child: const Text('ดูทั้งหมด'),
          ),
        ),
        const SizedBox(height: 10),

        if (_recent.isEmpty)
          const _EmptyCard(
            icon: Icons.receipt_long_rounded,
            title: 'ยังไม่มีประวัติ',
            subtitle: 'เมื่อมีการรับเข้า/จ่ายออก รายการล่าสุดจะขึ้นที่นี่',
          )
        else
          Column(
            children: [
              for (final t in _recent)
                _TxnTile(
                  txn: t,
                  onTap: () => _openTxnDetail(t),
                ),
            ],
          ),
      ],
    );
  }

  Widget _buildHistory(ColorScheme cs) {
    final list = _filteredHistoryBySearch;

    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('ประวัติรายการ (Stock In/Out)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
                const SizedBox(height: 10),

                TextField(
                  controller: _historySearchCtl,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: _hq.isEmpty
                        ? null
                        : IconButton(
                            onPressed: () => _historySearchCtl.clear(),
                            icon: const Icon(Icons.clear_rounded),
                          ),
                    hintText: 'ค้นหา: supplier / patient / note / id',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                ),

                const SizedBox(height: 12),

                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _Seg(
                      label: 'ทั้งหมด',
                      active: _typeFilter == _TxnTypeFilter.all,
                      onTap: () async {
                        setState(() => _typeFilter = _TxnTypeFilter.all);
                        await _loadHistory();
                      },
                    ),
                    _Seg(
                      label: 'รับเข้า',
                      active: _typeFilter == _TxnTypeFilter.inOnly,
                      onTap: () async {
                        setState(() => _typeFilter = _TxnTypeFilter.inOnly);
                        await _loadHistory();
                      },
                    ),
                    _Seg(
                      label: 'จ่ายออก',
                      active: _typeFilter == _TxnTypeFilter.outOnly,
                      onTap: () async {
                        setState(() => _typeFilter = _TxnTypeFilter.outOnly);
                        await _loadHistory();
                      },
                    ),
                    const SizedBox(width: 6),
                    _Seg(
                      label: 'วันนี้',
                      active: _rangeFilter == _DateRangeFilter.today,
                      onTap: () async {
                        setState(() => _rangeFilter = _DateRangeFilter.today);
                        await _loadHistory();
                      },
                    ),
                    _Seg(
                      label: '7 วัน',
                      active: _rangeFilter == _DateRangeFilter.last7days,
                      onTap: () async {
                        setState(() => _rangeFilter = _DateRangeFilter.last7days);
                        await _loadHistory();
                      },
                    ),
                    _Seg(
                      label: '30 วัน',
                      active: _rangeFilter == _DateRangeFilter.last30days,
                      onTap: () async {
                        setState(() => _rangeFilter = _DateRangeFilter.last30days);
                        await _loadHistory();
                      },
                    ),
                    _Seg(
                      label: 'เดือนนี้',
                      active: _rangeFilter == _DateRangeFilter.thisMonth,
                      onTap: () async {
                        setState(() => _rangeFilter = _DateRangeFilter.thisMonth);
                        await _loadHistory();
                      },
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                Row(
                  children: [
                    _pillInfo('ทั้งหมด: ${_history.length} บิล', cs),
                    const SizedBox(width: 10),
                    _pillInfo('ผลลัพธ์: ${list.length} บิล', cs),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: _loadingHistory ? null : _loadHistory,
                      icon: _loadingHistory
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.refresh_rounded),
                      label: const Text('รีเฟรช'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        if (_loadingHistory)
          const Padding(
            padding: EdgeInsets.only(top: 26),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (list.isEmpty)
          const _EmptyCard(
            icon: Icons.find_in_page_rounded,
            title: 'ไม่พบรายการ',
            subtitle: 'ลองเปลี่ยนช่วงเวลา/ตัวกรอง หรือค้นหาด้วยคำอื่น',
          )
        else
          Column(
            children: [
              for (final t in list)
                _TxnTile(
                  txn: t,
                  onTap: () => _openTxnDetail(t),
                ),
            ],
          ),
      ],
    );
  }

  Widget _buildAlerts(ColorScheme cs) {
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                const Icon(Icons.notifications_active_rounded),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Alerts (ใกล้หมด/หมด/ใกล้หมดอายุ/หมดอายุ)',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
                TextButton.icon(
                  onPressed: _loadingAlerts ? null : _loadAlerts,
                  icon: _loadingAlerts
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.refresh_rounded),
                  label: const Text('รีเฟรช'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        const _SectionTitle(icon: Icons.warning_amber_rounded, title: 'สต็อกต่ำ / หมดสต็อก'),
        const SizedBox(height: 10),
        if (_loadingAlerts)
          const Center(child: Padding(padding: EdgeInsets.all(18), child: CircularProgressIndicator()))
        else if (_lowStockRows.isEmpty)
          const _EmptyCard(icon: Icons.check_circle_outline_rounded, title: 'ไม่มีรายการสต็อกต่ำ', subtitle: 'ตอนนี้สต็อกอยู่ในเกณฑ์ปกติ')
        else
          Column(
            children: _lowStockRows.map((r) {
              final status = r.isOut ? 'หมดสต็อก' : 'สต็อกต่ำ';
              final color = r.isOut ? Colors.red : Colors.orange;

              return Card(
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: color.withOpacity(0.10),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(r.isOut ? Icons.block_rounded : Icons.warning_amber_rounded, color: color),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(
                            r.code.isEmpty ? r.name : '${r.name} (${r.code})',
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'คงเหลือ ${_fmtNum(r.onHandBase)} ${r.baseUnit} • เตือนขั้นต่ำ ${_fmtNum(r.reorderPoint)}',
                            style: TextStyle(color: Colors.grey.shade700),
                          ),
                        ]),
                      ),
                      const SizedBox(width: 8),
                      _tag(status, color),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),

        const SizedBox(height: 18),
        const _SectionTitle(icon: Icons.hourglass_bottom_rounded, title: 'ใกล้หมดอายุ'),
        const SizedBox(height: 10),

        if (_loadingAlerts)
          const SizedBox.shrink()
        else if (_expiringRows.isEmpty)
          const _EmptyCard(icon: Icons.check_circle_outline_rounded, title: 'ไม่มีล็อตใกล้หมดอายุ', subtitle: 'ยังไม่เจอล็อตที่เข้าเงื่อนไขการเตือน')
        else
          Column(
            children: _expiringRows.map((r) {
              final color = Colors.amber.shade800;
              return Card(
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: color.withOpacity(0.10),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(Icons.hourglass_bottom_rounded, color: color),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(
                            r.code.isEmpty ? r.name : '${r.name} (${r.code})',
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Lot ${r.lotNo} • EXP ${r.expDate} • เหลือ ${_fmtNum(r.qtyBase)} ${r.baseUnit}',
                            style: TextStyle(color: Colors.grey.shade700),
                          ),
                        ]),
                      ),
                      const SizedBox(width: 8),
                      _tag('อีก ${r.daysLeft} วัน', color),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),

        const SizedBox(height: 18),
        const _SectionTitle(icon: Icons.event_busy_rounded, title: 'หมดอายุ (ยังมีคงเหลือ)'),
        const SizedBox(height: 10),

        if (_loadingAlerts)
          const SizedBox.shrink()
        else if (_expiredRows.isEmpty)
          const _EmptyCard(icon: Icons.check_circle_outline_rounded, title: 'ไม่มีล็อตหมดอายุคงเหลือ', subtitle: 'ดีมาก')
        else
          Column(
            children: _expiredRows.map((r) {
              const color = Colors.red;
              return Card(
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: color.withOpacity(0.10),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(Icons.event_busy_rounded, color: Colors.red),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(
                            r.code.isEmpty ? r.name : '${r.name} (${r.code})',
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Lot ${r.lotNo} • EXP ${r.expDate} • เหลือ ${_fmtNum(r.qtyBase)} ${r.baseUnit}',
                            style: TextStyle(color: Colors.grey.shade700),
                          ),
                        ]),
                      ),
                      const SizedBox(width: 8),
                      _tag('หมดอายุ', color),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
      ],
    );
  }

  Widget _pillInfo(String text, ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: cs.primary.withOpacity(0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: cs.primary.withOpacity(0.18)),
      ),
      child: Text(text, style: TextStyle(fontWeight: FontWeight.w800, color: cs.primary)),
    );
  }

  Widget _tag(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Text(text, style: TextStyle(fontWeight: FontWeight.w800, color: color)),
    );
  }
}

// =============================
// Bottom Sheet Detail
// =============================

class _TxnDetailSheet extends StatefulWidget {
  final SupabaseClient sb;
  final _TxnRow txn;
  final String ownerId;

  const _TxnDetailSheet({
    required this.sb,
    required this.txn,
    required this.ownerId,
  });

  @override
  State<_TxnDetailSheet> createState() => _TxnDetailSheetState();
}

class _TxnDetailSheetState extends State<_TxnDetailSheet> {
  bool _loading = true;
  String? _err;

  List<Map<String, dynamic>> _items = [];
  Map<String, Map<String, dynamic>> _drugMap = {}; // drug_id -> {name, code, base_unit}

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _fmtNum(num v) => (v % 1 == 0) ? v.toInt().toString() : v.toStringAsFixed(2);

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _err = null;
    });

    try {
      final dRows = await widget.sb
          .from('drugs')
          .select('id, generic_name, code, base_unit')
          .eq('owner_id', widget.ownerId);

      final map = <String, Map<String, dynamic>>{};
      if (dRows is List) {
        for (final d in dRows) {
          final id = (d['id'] ?? '').toString();
          if (id.isEmpty) continue;
          map[id] = Map<String, dynamic>.from(d as Map);
        }
      }

      if (widget.txn.type == _TxnType.inTxn) {
        final rows = await widget.sb
            .from('stock_in_items')
            .select('drug_id, lot_no, exp_date, input_qty, input_unit, to_base, base_qty, cost_per_base, sell_per_base, created_at')
            .eq('owner_id', widget.ownerId)
            .eq('receipt_id', widget.txn.id)
            .order('created_at', ascending: true);

        setState(() {
          _drugMap = map;
          _items = (rows is List) ? rows.map((e) => Map<String, dynamic>.from(e as Map)).toList() : [];
        });
      } else {
        final rows = await widget.sb
            .from('stock_out_items')
            .select('drug_id, lot_no, exp_date, qty_base, sell_per_base, line_total, created_at')
            .eq('owner_id', widget.ownerId)
            .eq('receipt_id', widget.txn.id)
            .order('created_at', ascending: true);

        setState(() {
          _drugMap = map;
          _items = (rows is List) ? rows.map((e) => Map<String, dynamic>.from(e as Map)).toList() : [];
        });
      }
    } catch (e) {
      _err = e.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isIn = widget.txn.type == _TxnType.inTxn;
    final title = isIn ? 'รายละเอียดบิลรับเข้า' : 'รายละเอียดบิลจ่ายออก';
    final accent = isIn ? const Color(0xFF16A34A) : const Color(0xFFEF4444);

    return SafeArea(
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.86,
        minChildSize: 0.55,
        maxChildSize: 0.95,
        builder: (context, sc) {
          return Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              children: [
                Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.18),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(height: 10),

                Row(
                  children: [
                    Icon(isIn ? Icons.download_rounded : Icons.outbox_rounded, color: accent),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('ปิด'),
                    ),
                  ],
                ),
                const SizedBox(height: 6),

                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '${widget.txn.title} • ${widget.txn.subtitle ?? ''}',
                    style: TextStyle(color: Colors.grey.shade700),
                  ),
                ),
                if ((widget.txn.note ?? '').trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'หมายเหตุ: ${widget.txn.note}',
                      style: TextStyle(color: Colors.grey.shade700),
                    ),
                  ),
                ],

                const SizedBox(height: 12),
                Expanded(
                  child: Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                    child: _loading
                        ? const Center(child: CircularProgressIndicator())
                        : (_err != null)
                            ? Center(child: Padding(padding: const EdgeInsets.all(16), child: Text('โหลดไม่สำเร็จ: $_err')))
                            : (_items.isEmpty)
                                ? Center(
                                    child: Padding(
                                      padding: const EdgeInsets.all(16),
                                      child: Text('ไม่มีรายการในบิลนี้', style: TextStyle(color: Colors.grey.shade700)),
                                    ),
                                  )
                                : ListView.separated(
                                    controller: sc,
                                    padding: const EdgeInsets.all(14),
                                    itemCount: _items.length + 1,
                                    separatorBuilder: (_, __) => const Divider(height: 18),
                                    itemBuilder: (_, i) {
                                      if (i == 0) {
                                        final count = _items.length;

                                        if (isIn) {
                                          num costTotal = 0;
                                          num sellTotal = 0;

                                          for (final r in _items) {
                                            final baseQty = (r['base_qty'] is num) ? (r['base_qty'] as num) : 0;
                                            final cpb = r['cost_per_base'];
                                            final spb = r['sell_per_base'];
                                            if (cpb is num) costTotal += baseQty * cpb;
                                            if (spb is num) sellTotal += baseQty * spb;
                                          }

                                          return Wrap(
                                            spacing: 10,
                                            runSpacing: 10,
                                            children: [
                                              _pill('รวม $count รายการ', bg: accent.withOpacity(0.10), fg: accent),
                                              _pill('ทุนรวม ${costTotal.toStringAsFixed(2)} ฿', bg: Colors.black.withOpacity(0.05), fg: Colors.black87),
                                              _pill('ขายรวม ${sellTotal.toStringAsFixed(2)} ฿', bg: const Color(0xFFE6F7EC), fg: const Color(0xFF0F7A3B), strong: true),
                                            ],
                                          );
                                        } else {
                                          num total = 0;
                                          for (final r in _items) {
                                            final v = r['line_total'];
                                            if (v is num) total += v;
                                          }
                                          return Wrap(
                                            spacing: 10,
                                            runSpacing: 10,
                                            children: [
                                              _pill('รวม $count รายการ', bg: accent.withOpacity(0.10), fg: accent),
                                              _pill('รวม ${total.toStringAsFixed(2)} ฿', bg: const Color(0xFFFFECEC), fg: const Color(0xFFEF4444), strong: true),
                                            ],
                                          );
                                        }
                                      }

                                      final r = _items[i - 1];

                                      final drugId = (r['drug_id'] ?? '').toString();
                                      final drug = _drugMap[drugId];
                                      final name = (drug?['generic_name'] ?? 'Unknown').toString();
                                      final code = (drug?['code'] ?? '').toString();
                                      final baseUnit = (drug?['base_unit'] ?? 'หน่วยฐาน').toString();

                                      if (isIn) {
                                        final lot = (r['lot_no'] ?? '').toString();
                                        final exp = (r['exp_date'] ?? '').toString();
                                        final inputQty = (r['input_qty'] is num) ? (r['input_qty'] as num) : 0;
                                        final inputUnit = (r['input_unit'] ?? '').toString();
                                        final baseQty = (r['base_qty'] is num) ? (r['base_qty'] as num) : 0;

                                        final cost = r['cost_per_base'];
                                        final sell = r['sell_per_base'];

                                        return Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(code.isEmpty ? name : '$name ($code)', style: const TextStyle(fontWeight: FontWeight.w900)),
                                            const SizedBox(height: 6),
                                            Wrap(
                                              spacing: 10,
                                              runSpacing: 6,
                                              children: [
                                                _chip('Lot: $lot'),
                                                _chip('EXP: $exp'),
                                                _chip('รับเข้า: ${_fmtNum(inputQty)} $inputUnit'),
                                                _chip('ฐาน: ${_fmtNum(baseQty)} $baseUnit'),
                                              ],
                                            ),
                                            const SizedBox(height: 8),
                                            Row(
                                              children: [
                                                if (cost != null) _sub('ทุน/ฐาน: ${_fmtNum(cost as num)}'),
                                                if (cost != null && sell != null) const SizedBox(width: 12),
                                                if (sell != null) _sub('ขาย/ฐาน: ${_fmtNum(sell as num)}'),
                                              ],
                                            ),
                                          ],
                                        );
                                      } else {
                                        final lot = (r['lot_no'] ?? '').toString();
                                        final exp = (r['exp_date'] ?? '').toString();
                                        final qtyBase = (r['qty_base'] is num) ? (r['qty_base'] as num) : 0;
                                        final sellPerBase = (r['sell_per_base'] is num) ? (r['sell_per_base'] as num) : 0;
                                        final lineTotal = (r['line_total'] is num) ? (r['line_total'] as num) : 0;

                                        return Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(code.isEmpty ? name : '$name ($code)', style: const TextStyle(fontWeight: FontWeight.w900)),
                                            const SizedBox(height: 6),
                                            Wrap(
                                              spacing: 10,
                                              runSpacing: 6,
                                              children: [
                                                _chip('Lot: $lot'),
                                                _chip('EXP: $exp'),
                                                _chip('จ่าย: ${_fmtNum(qtyBase)} $baseUnit'),
                                              ],
                                            ),
                                            const SizedBox(height: 8),
                                            Text(
                                              '${sellPerBase.toStringAsFixed(2)} / ฐาน • รวม ${lineTotal.toStringAsFixed(2)} ฿',
                                              style: TextStyle(color: Colors.grey.shade700, fontWeight: FontWeight.w700),
                                            ),
                                          ],
                                        );
                                      }
                                    },
                                  ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _pill(
    String text, {
    bool strong = false,
    required Color bg,
    required Color fg,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontWeight: strong ? FontWeight.w900 : FontWeight.w700,
          color: fg,
        ),
      ),
    );
  }

  Widget _chip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.04),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.black.withOpacity(0.06)),
      ),
      child: Text(text, style: const TextStyle(fontWeight: FontWeight.w600)),
    );
  }

  Widget _sub(String text) {
    return Text(text, style: TextStyle(color: Colors.black.withOpacity(0.65), fontWeight: FontWeight.w700));
  }
}

// =============================
// Widgets
// =============================

class _SectionTitle extends StatelessWidget {
  final IconData icon;
  final String title;
  final Widget? trailing;
  const _SectionTitle({required this.icon, required this.title, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

class _EmptyCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  const _EmptyCard({required this.icon, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          children: [
            Icon(icon, size: 46),
            const SizedBox(height: 10),
            Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.black54, height: 1.35),
            ),
          ],
        ),
      ),
    );
  }
}

class _Seg extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _Seg({required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
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
          border: Border.all(color: cs.primary.withOpacity(0.25)),
        ),
        child: Text(label, style: TextStyle(fontWeight: FontWeight.w800, color: fg)),
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  final String title;
  final String value;
  final String subtitle;
  final IconData icon;

  const _MetricCard({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: cs.primary.withOpacity(0.10),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: cs.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.black54)),
                  const SizedBox(height: 6),
                  Text(value, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.black45)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StockActionCard extends StatelessWidget {
  final Color accent;
  final Color iconBg;

  final IconData icon;
  final String title;
  final String subtitle;
  final String buttonText;
  final VoidCallback onPressed;

  const _StockActionCard({
    required this.accent,
    required this.iconBg,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.buttonText,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.65),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE6EEF7)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: accent.withOpacity(0.20)),
            ),
            child: Icon(icon, color: accent),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                const SizedBox(height: 6),
                Text(subtitle, style: TextStyle(color: Colors.black.withOpacity(0.6), height: 1.35)),
                const SizedBox(height: 14),
                SizedBox(
                  height: 40,
                  child: ElevatedButton.icon(
                    onPressed: onPressed,
                    icon: const Icon(Icons.arrow_forward_rounded),
                    label: Text(buttonText),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accent,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      elevation: 0,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TxnTile extends StatelessWidget {
  final _TxnRow txn;
  final VoidCallback onTap;

  const _TxnTile({required this.txn, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isIn = txn.type == _TxnType.inTxn;
    final color = isIn ? const Color(0xFF16A34A) : const Color(0xFFEF4444);
    final bg = color.withOpacity(0.10);
    final badge = isIn ? 'IN' : 'OUT';

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(16)),
                child: Icon(isIn ? Icons.download_rounded : Icons.outbox_rounded, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: bg,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: color.withOpacity(0.25)),
                        ),
                        child: Text(badge, style: TextStyle(fontWeight: FontWeight.w900, color: color)),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          txn.title,
                          style: const TextStyle(fontWeight: FontWeight.w900),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    txn.subtitle ?? _TxnRow._shortDateTime(txn.at),
                    style: TextStyle(color: Colors.grey.shade700),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _miniPill('รายการ: ${txn.itemCount ?? '-'}', color),
                      if (isIn) ...[
                        _miniPill('ทุน: ${(txn.inCostTotal ?? 0).toStringAsFixed(2)} ฿', Colors.black87),
                        _miniPill('ขาย: ${(txn.inSellTotal ?? 0).toStringAsFixed(2)} ฿', const Color(0xFF0F7A3B)),
                      ] else ...[
                        _miniPill('รวม: ${(txn.totalAmount ?? 0).toStringAsFixed(2)} ฿', color),
                      ],
                    ],
                  ),
                ]),
              ),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }

  Widget _miniPill(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.15)),
      ),
      child: Text(text, style: TextStyle(fontWeight: FontWeight.w800, color: color)),
    );
  }
}

// =============================
// Models
// =============================

enum _TxnType { inTxn, outTxn }

enum _TxnTypeFilter { all, inOnly, outOnly }

enum _DateRangeFilter { today, last7days, last30days, thisMonth }

class _TxnRow {
  final _TxnType type;
  final String id;
  final DateTime at;

  final String title;
  final String? subtitle;
  final String? note;

  int? itemCount;

  // OUT summary
  num? totalAmount;

  // IN summary ✅ เอาทั้งสอง: ทุนรวม + ขายรวม
  num? inCostTotal;
  num? inSellTotal;

  _TxnRow({
    required this.type,
    required this.id,
    required this.at,
    required this.title,
    this.subtitle,
    this.note,
  });

  factory _TxnRow.fromInReceipt(Map<String, dynamic> r) {
    final id = (r['id'] ?? '').toString();
    final createdAt = (r['created_at'] ?? '').toString();
    final receivedAt = (r['received_at'] ?? '').toString();
    final supplier = (r['supplier_name'] ?? '').toString();
    final note = (r['note'] ?? '').toString();

    final at = DateTime.tryParse(receivedAt.isNotEmpty ? receivedAt : createdAt) ?? DateTime.now();
    final title = supplier.trim().isEmpty ? 'รับยาเข้า' : 'รับยาเข้า • $supplier';

    final dn = (r['delivery_note_no'] ?? '').toString();
    final inv = (r['invoice_no'] ?? '').toString();
    final po = (r['po_no'] ?? '').toString();

    final parts = <String>[];
    if (dn.trim().isNotEmpty) parts.add('DN $dn');
    if (inv.trim().isNotEmpty) parts.add('INV $inv');
    if (po.trim().isNotEmpty) parts.add('PO $po');

    final subtitle = parts.isEmpty ? _shortDateTime(at) : '${_shortDateTime(at)} • ${parts.join(' • ')}';

    return _TxnRow(
      type: _TxnType.inTxn,
      id: id,
      at: at,
      title: title,
      subtitle: subtitle,
      note: note.trim().isEmpty ? null : note,
    );
  }

  factory _TxnRow.fromOutReceipt(Map<String, dynamic> r) {
    final id = (r['id'] ?? '').toString();
    final createdAt = (r['created_at'] ?? '').toString();
    final soldAt = (r['sold_at'] ?? '').toString();
    final patient = (r['patient_name'] ?? '').toString();
    final note = (r['note'] ?? '').toString();

    final at = DateTime.tryParse(soldAt.isNotEmpty ? soldAt : createdAt) ?? DateTime.now();
    final title = patient.trim().isEmpty ? 'จ่ายยาออก' : 'จ่ายยาออก • $patient';
    final subtitle = _shortDateTime(at);

    return _TxnRow(
      type: _TxnType.outTxn,
      id: id,
      at: at,
      title: title,
      subtitle: subtitle,
      note: note.trim().isEmpty ? null : note,
    );
  }

  static String _shortDateTime(DateTime d) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
  }
}

class _LowStockRow {
  final String drugId;
  final String name;
  final String code;
  final String baseUnit;
  final num onHandBase;
  final num reorderPoint;
  final bool isOut;

  _LowStockRow({
    required this.drugId,
    required this.name,
    required this.code,
    required this.baseUnit,
    required this.onHandBase,
    required this.reorderPoint,
    required this.isOut,
  });
}

enum _LotAlertKind { expiringSoon, expired }

class _LotAlertRow {
  final String drugId;
  final String name;
  final String code;
  final String baseUnit;
  final String lotNo;
  final String expDate;
  final num qtyBase;
  final int daysLeft;
  final _LotAlertKind kind;

  _LotAlertRow({
    required this.drugId,
    required this.name,
    required this.code,
    required this.baseUnit,
    required this.lotNo,
    required this.expDate,
    required this.qtyBase,
    required this.daysLeft,
    required this.kind,
  });
}