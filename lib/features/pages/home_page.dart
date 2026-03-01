// lib/pages/home/home_page.dart
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase_guard.dart';
import '../auth/auth_gate.dart';
import '../drugs/add_drug_page.dart';
import '../stock/stock_in_page.dart';
import '../stock/stock_out_page.dart';
import 'about_page.dart';
import 'expiry_calendar_page.dart';
import 'profile_page.dart';
import 'security_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  SupabaseClient? _sb;

  bool _loading = true;
  String? _error;

  // ===== Profile header (NEW) =====
  String? _shopName;
  String? _displayName;
  String? _logoUrl; // profiles.logo_url

  // ===== Dashboard numbers =====
  int _drugCount = 0;
  int _lotCount = 0;

  int _expiredCount = 0;
  int _nearExpireCount = 0;
  int _lowStockCount = 0;

  num _onHandBaseTotal = 0;

  // ===== Financial =====
  int _days = 30;
  num _sales = 0;
  num _costEst = 0;
  num _profitEst = 0;

  // ===== Chart / Top =====
  List<_ChartPoint> _salesSeries = [];
  List<_TopDrug> _top5 = [];

  // ===== Manufacturers & Suppliers =====
  List<Map<String, dynamic>> _manufacturers = [];
  List<Map<String, dynamic>> _suppliers = [];

  final TextEditingController _mSearchCtl = TextEditingController();
  final TextEditingController _sSearchCtl = TextEditingController();
  String _mQ = '';
  String _sQ = '';

  // ===== Alert details (NEW) =====
  bool _loadingAlerts = false;
  List<_DrugAlertGroup> _expiredGroups = [];
  List<_DrugAlertGroup> _nearExpireGroups = [];
  List<_DrugAlertGroup> _lowStockGroups = [];

  @override
  void initState() {
    super.initState();
    _sb = getSupabaseClientOrNull();
    if (_sb == null) {
      setState(() {
        _loading = false;
        _error = 'ยังไม่ได้ตั้งค่า Supabase หรือยังไม่ได้ล็อกอิน';
      });
      return;
    }

    _mSearchCtl.addListener(() {
      setState(() => _mQ = _mSearchCtl.text.trim().toLowerCase());
    });
    _sSearchCtl.addListener(() {
      setState(() => _sQ = _sSearchCtl.text.trim().toLowerCase());
    });

    _bootstrap();
  }

  @override
  void dispose() {
    _mSearchCtl.dispose();
    _sSearchCtl.dispose();
    super.dispose();
  }

  String _ownerId() {
    final u = _sb!.auth.currentUser;
    if (u == null) throw Exception('ยังไม่ได้ล็อกอิน');
    return u.id;
  }

  // =========================
  // ✅ NEW: Load profile header (logo/name) from profiles
  // =========================
  Future<void> _loadProfileHeader() async {
    final sb = _sb!;
    final uid = _ownerId();

    try {
      final row = await sb
          .from('profiles')
          .select('shop_name, display_name, logo_url')
          .eq('id', uid)
          .maybeSingle();

      _shopName = (row?['shop_name'] ?? '').toString().trim();
      _displayName = (row?['display_name'] ?? '').toString().trim();
      _logoUrl = (row?['logo_url'] ?? '').toString().trim();

      if ((_shopName ?? '').isEmpty) _shopName = null;
      if ((_displayName ?? '').isEmpty) _displayName = null;
      if ((_logoUrl ?? '').isEmpty) _logoUrl = null;
    } catch (_) {
      _shopName = null;
      _displayName = null;
      _logoUrl = null;
    }
  }

  ImageProvider? _homeLogoProvider() {
    final url = (_logoUrl ?? '').trim();
    if (url.isEmpty) return null;
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.isAbsolute) return null;
    return NetworkImage(url);
  }

  Future<void> _bootstrap() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await Future.wait([
        _loadProfileHeader(), // ✅ NEW
        _loadInventoryStats(),
        _loadFinance(days: _days),
        _loadSalesSeries(days: _days),
        _loadTopSellers(days: _days),
        _loadManufacturers(),
        _loadSuppliers(),

        _loadAlertDetails(), // ✅ NEW: รายละเอียดแจ้งเตือนกดดูยา/ล็อตได้
      ]);
    } catch (e) {
      _error = '$e';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // =========================
  // Inventory / Finance (เดิม)
  // =========================
  Future<void> _loadInventoryStats() async {
    final sb = _sb!;
    final ownerId = _ownerId();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final todayStr = _dateOnly(today);

    final drugsRows = await sb.from('drugs').select('id').eq('owner_id', ownerId);
    _drugCount = (drugsRows as List).length;

    final lotsRows = await sb
        .from('drug_lots')
        .select('id, exp_date, qty_on_hand_base')
        .eq('owner_id', ownerId);

    int lotCount = 0;
    int expired = 0;
    int nearExpire = 0;
    num onHandTotal = 0;

    for (final r in (lotsRows as List)) {
      final qty = (r['qty_on_hand_base'] as num?) ?? 0;
      if (qty <= 0) continue;

      lotCount++;
      onHandTotal += qty;

      final exp = (r['exp_date'] ?? '').toString();
      if (exp.compareTo(todayStr) < 0) {
        expired++;
      } else {
        final diff = _daysBetween(today, _parseDate(exp));
        if (diff >= 0 && diff <= 90) nearExpire++;
      }
    }

    _lotCount = lotCount;
    _expiredCount = expired;
    _nearExpireCount = nearExpire;
    _onHandBaseTotal = onHandTotal;

    try {
      final sumRows = await sb
          .from('v_drug_stock_summary')
          .select('drug_id, stock_status')
          .eq('owner_id', ownerId);

      int low = 0;
      for (final r in (sumRows as List)) {
        final st = (r['stock_status'] ?? '').toString();
        if (st == 'low' || st == 'out') low++;
      }
      _lowStockCount = low;
    } catch (_) {
      _lowStockCount = 0;
    }
  }

  Future<void> _loadFinance({required int days}) async {
    final sb = _sb!;
    final ownerId = _ownerId();
    final from = DateTime.now().subtract(Duration(days: days));
    final fromIso = from.toIso8601String();

    num sales = 0;
    try {
      final outRows = await sb
          .from('stock_out_items')
          .select('line_total, created_at')
          .eq('owner_id', ownerId)
          .gte('created_at', fromIso);

      for (final r in (outRows as List)) {
        final v = r['line_total'];
        if (v is num) sales += v;
      }
    } catch (_) {}

    num costEst = 0;

    final costMap = <String, num>{};
    try {
      final inRows = await sb
          .from('stock_in_items')
          .select('drug_id, lot_no, exp_date, cost_per_base, created_at')
          .eq('owner_id', ownerId)
          .not('cost_per_base', 'is', null)
          .order('created_at', ascending: false);

      for (final r in (inRows as List)) {
        final drugId = (r['drug_id'] ?? '').toString();
        final lotNo = (r['lot_no'] ?? '').toString();
        final exp = (r['exp_date'] ?? '').toString();
        final c = r['cost_per_base'];
        if (drugId.isEmpty || lotNo.isEmpty || exp.isEmpty) continue;
        if (c is! num) continue;

        final k = '$drugId|$lotNo|$exp';
        costMap.putIfAbsent(k, () => c);
      }
    } catch (_) {}

    try {
      final soldRows = await sb
          .from('stock_out_items')
          .select('drug_id, lot_no, exp_date, qty_base, created_at')
          .eq('owner_id', ownerId)
          .gte('created_at', fromIso);

      for (final r in (soldRows as List)) {
        final drugId = (r['drug_id'] ?? '').toString();
        final lotNo = (r['lot_no'] ?? '').toString();
        final exp = (r['exp_date'] ?? '').toString();
        final qty = (r['qty_base'] as num?) ?? 0;
        if (qty <= 0) continue;

        final k = '$drugId|$lotNo|$exp';
        final c = costMap[k];
        if (c != null) costEst += (c * qty);
      }
    } catch (_) {}

    _sales = sales;
    _costEst = costEst;
    _profitEst = _sales - _costEst;
  }

  Future<void> _loadSalesSeries({required int days}) async {
    final sb = _sb!;
    final ownerId = _ownerId();
    final end = DateTime.now();
    final start =
        DateTime(end.year, end.month, end.day).subtract(Duration(days: days - 1));
    final startIso = start.toIso8601String();

    final daySales = <String, num>{};
    for (int i = 0; i < days; i++) {
      final d = start.add(Duration(days: i));
      daySales[_dateOnly(d)] = 0;
    }

    try {
      final rows = await sb
          .from('stock_out_items')
          .select('created_at, line_total')
          .eq('owner_id', ownerId)
          .gte('created_at', startIso);

      for (final r in (rows as List)) {
        final created = (r['created_at'] ?? '').toString();
        if (created.length < 10) continue;
        final dayKey = created.substring(0, 10);
        final lt = r['line_total'];
        if (lt is num && daySales.containsKey(dayKey)) {
          daySales[dayKey] = (daySales[dayKey] ?? 0) + lt;
        }
      }
    } catch (_) {}

    final pts = <_ChartPoint>[];
    final keys = daySales.keys.toList()..sort();
    for (int i = 0; i < keys.length; i++) {
      pts.add(_ChartPoint(
        i.toDouble(),
        (daySales[keys[i]] ?? 0).toDouble(),
        label: keys[i],
      ));
    }

    _salesSeries = pts;
  }

  Future<void> _loadTopSellers({required int days}) async {
    final sb = _sb!;
    final ownerId = _ownerId();
    final from = DateTime.now().subtract(Duration(days: days));
    final fromIso = from.toIso8601String();

    final map = <String, _TopDrugAgg>{};

    try {
      final rows = await sb
          .from('stock_out_items')
          .select(
              'drug_id, qty_base, line_total, created_at, drugs(generic_name, brand_name, base_unit)')
          .eq('owner_id', ownerId)
          .gte('created_at', fromIso);

      for (final r in (rows as List)) {
        final drugId = (r['drug_id'] ?? '').toString();
        if (drugId.isEmpty) continue;

        final qty = (r['qty_base'] as num?) ?? 0;
        final lt = (r['line_total'] as num?) ?? 0;

        final d = (r['drugs'] as Map?) ?? {};
        final g = (d['generic_name'] ?? '-').toString();
        final b = (d['brand_name'] ?? '').toString();
        final unit = (d['base_unit'] ?? '').toString();

        final name = b.trim().isNotEmpty ? '$g ($b)' : g;

        final agg = map.putIfAbsent(
          drugId,
          () => _TopDrugAgg(drugId: drugId, name: name, baseUnit: unit),
        );
        agg.qtyBase += qty;
        agg.sales += lt;
      }
    } catch (_) {}

    final list = map.values.toList()..sort((a, b) => b.sales.compareTo(a.sales));

    _top5 = list.take(5).map((a) {
      return _TopDrug(
        drugId: a.drugId,
        name: a.name,
        baseUnit: a.baseUnit,
        qtyBase: a.qtyBase,
        sales: a.sales,
      );
    }).toList();
  }

  // =========================
  // ✅ NEW: Alert Details (ยาไหน/ล็อตไหน)
  // =========================
  Future<void> _loadAlertDetails() async {
    if (_loadingAlerts) return;
    _loadingAlerts = true;

    final sb = _sb!;
    final ownerId = _ownerId();

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    try {
      // ดึงล็อตที่มีของ + join drugs
      // จำกัด exp_date <= วันนี้ + 365 วัน กัน query หนัก
      final limitEnd = today.add(const Duration(days: 365));

      final rows = await sb
          .from('drug_lots')
          .select('''
            id, drug_id, lot_no, exp_date, qty_on_hand_base,
            drugs(code, generic_name, brand_name, base_unit, expiry_alert_days, reorder_point)
          ''')
          .eq('owner_id', ownerId)
          .gt('qty_on_hand_base', 0)
          .lte('exp_date', _dateOnly(limitEnd))
          .order('exp_date', ascending: true);

      final lots = (rows as List).map((e) {
        final m = Map<String, dynamic>.from(e as Map);
        final d = (m['drugs'] as Map?) ?? {};

        return _LotRow(
          lotId: (m['id'] ?? '').toString(),
          drugId: (m['drug_id'] ?? '').toString(),
          lotNo: (m['lot_no'] ?? '').toString(),
          expDate: _parseDate((m['exp_date'] ?? '').toString()),
          qtyBase: (m['qty_on_hand_base'] as num?) ?? 0,
          code: (d['code'] ?? '').toString(),
          genericName: (d['generic_name'] ?? '-').toString(),
          brandName: (d['brand_name'] ?? '').toString(),
          baseUnit: (d['base_unit'] ?? '').toString(),
          expiryAlertDays: (d['expiry_alert_days'] as num?)?.toInt() ?? 90,
          reorderPoint: (d['reorder_point'] as num?) ?? 0,
        );
      }).where((l) => l.drugId.isNotEmpty).toList();

      final expiredMap = <String, _DrugAlertGroup>{};
      final nearMap = <String, _DrugAlertGroup>{};

      final sumBase = <String, num>{};
      final infoMap = <String, _DrugInfo>{};

      for (final l in lots) {
        sumBase[l.drugId] = (sumBase[l.drugId] ?? 0) + l.qtyBase;

        infoMap.putIfAbsent(
          l.drugId,
          () => _DrugInfo(
            drugId: l.drugId,
            code: l.code,
            name: l.brandName.trim().isNotEmpty
                ? '${l.genericName} (${l.brandName})'
                : l.genericName,
            baseUnit: l.baseUnit,
            reorderPoint: l.reorderPoint,
            expiryAlertDays: l.expiryAlertDays,
          ),
        );

        final exp = DateTime(l.expDate.year, l.expDate.month, l.expDate.day);

        // expired
        if (exp.isBefore(today)) {
          expiredMap.putIfAbsent(
            l.drugId,
            () => _DrugAlertGroup(info: infoMap[l.drugId]!, lots: []),
          );
          expiredMap[l.drugId]!.lots.add(l);
          continue;
        }

        // nearExpire: ใช้ expiry_alert_days ต่อยา
        final warnDays = math.max(0, l.expiryAlertDays);
        final warnEnd = today.add(Duration(days: warnDays));
        if (!exp.isAfter(warnEnd)) {
          nearMap.putIfAbsent(
            l.drugId,
            () => _DrugAlertGroup(info: infoMap[l.drugId]!, lots: []),
          );
          nearMap[l.drugId]!.lots.add(l);
        }
      }

      // low stock: total <= reorder_point (reorder_point > 0)
      final lowGroups = <_DrugAlertGroup>[];
      for (final entry in sumBase.entries) {
        final drugId = entry.key;
        final total = entry.value;
        final info = infoMap[drugId];
        if (info == null) continue;

        final rp = info.reorderPoint;
        if (rp > 0 && total <= rp) {
          final drugLots = lots.where((x) => x.drugId == drugId).toList()
            ..sort((a, b) => a.expDate.compareTo(b.expDate));
          lowGroups.add(_DrugAlertGroup(info: info, lots: drugLots, totalBase: total));
        }
      }

      final expiredGroups = expiredMap.values.toList()
        ..sort((a, b) => a.nextExpDate.compareTo(b.nextExpDate));
      final nearGroups = nearMap.values.toList()
        ..sort((a, b) => a.nextExpDate.compareTo(b.nextExpDate));
      lowGroups.sort((a, b) => (a.totalBase ?? 0).compareTo(b.totalBase ?? 0));

      _expiredGroups = expiredGroups;
      _nearExpireGroups = nearGroups;
      _lowStockGroups = lowGroups;
    } catch (e) {
      debugPrint('loadAlertDetails error: $e');
      _expiredGroups = [];
      _nearExpireGroups = [];
      _lowStockGroups = [];
    } finally {
      _loadingAlerts = false;
    }
  }

  void _openAlertSheet(_AlertType type) {
    List<_DrugAlertGroup> groups;
    String title;
    IconData icon;
    Color tone;

    switch (type) {
      case _AlertType.expired:
        groups = _expiredGroups;
        title = 'ล็อตหมดอายุ';
        icon = Icons.error_outline_rounded;
        tone = Colors.red;
        break;
      case _AlertType.nearExpire:
        groups = _nearExpireGroups;
        title = 'ล็อตใกล้หมดอายุ';
        icon = Icons.schedule_rounded;
        tone = Colors.orange;
        break;
      case _AlertType.lowStock:
        groups = _lowStockGroups;
        title = 'ยาสต็อกต่ำ/หมด';
        icon = Icons.inventory_2_rounded;
        tone = Colors.deepOrange;
        break;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: const Color(0xFFF4F7FB),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;

        Widget headerChip(String text) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: tone.withOpacity(0.12),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: tone.withOpacity(0.22)),
            ),
            child: Text(
              text,
              style: TextStyle(fontWeight: FontWeight.w900, color: tone, fontSize: 12),
            ),
          );
        }

        String fmtDate(DateTime d) => _dateOnly(d);
        int daysTo(DateTime d) {
          final today = DateTime.now();
          final a = DateTime(today.year, today.month, today.day);
          final b = DateTime(d.year, d.month, d.day);
          return b.difference(a).inDays;
        }

        String qty(num v) {
          // โชว์แบบสวย ๆ
          if (v % 1 == 0) return v.toStringAsFixed(0);
          return v.toStringAsFixed(2);
        }

        return SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
              left: 14,
              right: 14,
              top: 8,
              bottom: 14 + MediaQuery.of(ctx).viewInsets.bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // header
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: Colors.black.withOpacity(0.06)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: tone.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(icon, color: tone),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                            const SizedBox(height: 4),
                            Text(
                              '${groups.length} ยา',
                              style: TextStyle(color: Colors.black.withOpacity(0.6), fontWeight: FontWeight.w700),
                            ),
                          ],
                        ),
                      ),
                      headerChip(type == _AlertType.lowStock ? 'REORDER' : 'EXP'),
                      const SizedBox(width: 8),
                      IconButton(
                        tooltip: 'ไปหน้าปฏิทินหมดอายุ',
                        onPressed: () async {
                          Navigator.pop(ctx);
                          await Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const ExpiryCalendarPage()),
                          );
                          if (mounted) _bootstrap();
                        },
                        icon: Icon(Icons.calendar_month_rounded, color: cs.primary),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 12),

                Flexible(
                  child: groups.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 28),
                            child: Text(
                              'ยังไม่มีรายการในหมวดนี้',
                              style: TextStyle(color: Colors.black.withOpacity(0.55), fontWeight: FontWeight.w700),
                            ),
                          ),
                        )
                      : ListView.separated(
                          shrinkWrap: true,
                          itemCount: groups.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (_, i) {
                            final g = groups[i];

                            final rp = g.info.reorderPoint;
                            final total = g.totalBase;

                            // lots in this group
                            final lots = g.lots..sort((a, b) => a.expDate.compareTo(b.expDate));

                            return Container(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(color: Colors.black.withOpacity(0.06)),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.03),
                                    blurRadius: 12,
                                    offset: const Offset(0, 8),
                                  ),
                                ],
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // drug header
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                g.info.name,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(fontWeight: FontWeight.w900),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                [
                                                  if (g.info.code.trim().isNotEmpty) 'รหัส ${g.info.code}',
                                                  if (g.info.baseUnit.trim().isNotEmpty) 'หน่วย ${g.info.baseUnit}',
                                                ].join(' • '),
                                                style: TextStyle(
                                                  color: Colors.black.withOpacity(0.60),
                                                  fontWeight: FontWeight.w700,
                                                  fontSize: 13,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        if (type == _AlertType.lowStock && total != null)
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                            decoration: BoxDecoration(
                                              color: Colors.deepOrange.withOpacity(0.10),
                                              borderRadius: BorderRadius.circular(999),
                                              border: Border.all(color: Colors.deepOrange.withOpacity(0.22)),
                                            ),
                                            child: Text(
                                              'คงเหลือ ${qty(total)}',
                                              style: TextStyle(
                                                fontWeight: FontWeight.w900,
                                                color: Colors.deepOrange.shade700,
                                                fontSize: 12,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),

                                    if (type == _AlertType.lowStock && rp > 0) ...[
                                      const SizedBox(height: 8),
                                      Text(
                                        'จุดสั่งซื้อ (reorder_point): ${qty(rp)} ${g.info.baseUnit}',
                                        style: TextStyle(color: Colors.black.withOpacity(0.55), fontWeight: FontWeight.w700),
                                      ),
                                    ],

                                    const SizedBox(height: 10),

                                    // lots list
                                    Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF4F7FB),
                                        borderRadius: BorderRadius.circular(14),
                                        border: Border.all(color: Colors.black.withOpacity(0.06)),
                                      ),
                                      child: Column(
                                        children: List.generate(lots.length, (j) {
                                          final l = lots[j];
                                          final dLeft = daysTo(l.expDate);
                                          final badgeText = type == _AlertType.lowStock
                                              ? 'ล็อต ${l.lotNo}'
                                              : (dLeft < 0 ? 'หมดอายุ' : 'อีก $dLeft วัน');

                                          final badgeColor = type == _AlertType.expired
                                              ? Colors.red
                                              : (type == _AlertType.nearExpire ? Colors.orange : cs.primary);

                                          return Padding(
                                            padding: EdgeInsets.only(bottom: j == lots.length - 1 ? 0 : 8),
                                            child: Row(
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    'ล็อต: ${l.lotNo} • หมดอายุ: ${fmtDate(l.expDate)}',
                                                    style: const TextStyle(fontWeight: FontWeight.w800, height: 1.2),
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                                  decoration: BoxDecoration(
                                                    color: badgeColor.withOpacity(0.10),
                                                    borderRadius: BorderRadius.circular(999),
                                                    border: Border.all(color: badgeColor.withOpacity(0.22)),
                                                  ),
                                                  child: Text(
                                                    badgeText,
                                                    style: TextStyle(
                                                      fontWeight: FontWeight.w900,
                                                      color: badgeColor,
                                                      fontSize: 12,
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                                  decoration: BoxDecoration(
                                                    color: cs.primary.withOpacity(0.08),
                                                    borderRadius: BorderRadius.circular(999),
                                                    border: Border.all(color: cs.primary.withOpacity(0.18)),
                                                  ),
                                                  child: Text(
                                                    '${qty(l.qtyBase)} ${g.info.baseUnit}',
                                                    style: TextStyle(fontWeight: FontWeight.w900, color: cs.primary, fontSize: 12),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          );
                                        }),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),

                const SizedBox(height: 12),

                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => Navigator.pop(ctx),
                    icon: const Icon(Icons.check_rounded),
                    label: const Text('ปิด'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // =========================
  // Manufacturers & Suppliers (CRUD)
  // =========================
  Future<void> _loadManufacturers() async {
    final sb = _sb!;
    final ownerId = _ownerId();

    final rows = await sb
        .from('manufacturers')
        .select('id, name, code, country, address, phone, fda_number, created_at')
        .eq('owner_id', ownerId)
        .order('name', ascending: true);

    _manufacturers =
        (rows as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<void> _loadSuppliers() async {
    final sb = _sb!;
    final ownerId = _ownerId();

    final rows = await sb
        .from('suppliers')
        .select('''
          id, name, code, phone, address, note,
          is_default, is_active,
          company_name, contact_name, delivery_area,
          line_id, email, company_reg_no, drug_license_no,
          created_at, updated_at
        ''')
        .eq('owner_id', ownerId)
        .order('is_default', ascending: false)
        .order('name', ascending: true);

    _suppliers =
        (rows as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  List<Map<String, dynamic>> get _filteredManufacturers {
    final q = _mQ;
    if (q.isEmpty) return _manufacturers;
    return _manufacturers.where((m) {
      final name = (m['name'] ?? '').toString().toLowerCase();
      final country = (m['country'] ?? '').toString().toLowerCase();
      final phone = (m['phone'] ?? '').toString().toLowerCase();
      final fda = (m['fda_number'] ?? '').toString().toLowerCase();
      final code = (m['code'] ?? '').toString().toLowerCase();
      return name.contains(q) ||
          country.contains(q) ||
          phone.contains(q) ||
          fda.contains(q) ||
          code.contains(q);
    }).toList();
  }

  List<Map<String, dynamic>> get _filteredSuppliers {
    final q = _sQ;
    if (q.isEmpty) return _suppliers;

    return _suppliers.where((s) {
      String v(String k) => (s[k] ?? '').toString().toLowerCase();

      return v('name').contains(q) ||
          v('company_name').contains(q) ||
          v('contact_name').contains(q) ||
          v('phone').contains(q) ||
          v('address').contains(q) ||
          v('delivery_area').contains(q) ||
          v('code').contains(q) ||
          v('line_id').contains(q) ||
          v('email').contains(q) ||
          v('company_reg_no').contains(q) ||
          v('drug_license_no').contains(q) ||
          v('note').contains(q);
    }).toList();
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  InputDecoration _dec(String label, {String? hint, IconData? icon}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: icon == null ? null : Icon(icon),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      filled: true,
      fillColor: Colors.white,
    );
  }

  // ---------- Manufacturer editor (เดิม) ----------
  Future<void> _showManufacturerEditor({Map<String, dynamic>? edit}) async {
    final sb = _sb!;
    final ownerId = _ownerId();
    final isEdit = edit != null;

    final formKey = GlobalKey<FormState>();
    final nameCtl = TextEditingController(text: (edit?['name'] ?? '').toString());
    final codeCtl = TextEditingController(text: (edit?['code'] ?? '').toString());
    final countryCtl =
        TextEditingController(text: (edit?['country'] ?? 'ประเทศไทย').toString());
    final addressCtl =
        TextEditingController(text: (edit?['address'] ?? '').toString());
    final phoneCtl = TextEditingController(text: (edit?['phone'] ?? '').toString());
    final fdaCtl =
        TextEditingController(text: (edit?['fda_number'] ?? '').toString());

    bool saving = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return StatefulBuilder(
          builder: (ctx, setD) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Row(
                children: [
                  Icon(Icons.domain_rounded, color: cs.primary),
                  const SizedBox(width: 8),
                  Text(isEdit ? 'แก้ไขผู้ผลิต' : 'เพิ่มผู้ผลิตใหม่',
                      style: const TextStyle(fontWeight: FontWeight.w900)),
                ],
              ),
              content: SingleChildScrollView(
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextFormField(
                        controller: nameCtl,
                        decoration: _dec('ชื่อบริษัทผู้ผลิต *', icon: Icons.business_rounded),
                        validator: (v) =>
                            (v ?? '').trim().isEmpty ? 'กรุณากรอกชื่อบริษัท' : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: codeCtl,
                        decoration: _dec('รหัสบริษัท (ถ้ามี)', icon: Icons.qr_code_rounded),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: countryCtl,
                        decoration: _dec('ประเทศ', icon: Icons.public_rounded),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: addressCtl,
                        maxLines: 2,
                        decoration: _dec('ที่อยู่บริษัท', icon: Icons.location_on_rounded),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: phoneCtl,
                        decoration: _dec('เบอร์ติดต่อ', icon: Icons.phone_rounded),
                        keyboardType: TextInputType.phone,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: fdaCtl,
                        decoration: _dec('เลขทะเบียน อย.', icon: Icons.verified_rounded),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: saving ? null : () => Navigator.pop(ctx),
                  child: const Text('ยกเลิก', style: TextStyle(color: Colors.grey)),
                ),
                FilledButton(
                  onPressed: saving
                      ? null
                      : () async {
                          if (!(formKey.currentState?.validate() ?? false)) return;
                          setD(() => saving = true);
                          try {
                            final payload = <String, dynamic>{
                              'owner_id': ownerId,
                              'name': nameCtl.text.trim(),
                              'code': codeCtl.text.trim().isEmpty ? null : codeCtl.text.trim(),
                              'country': countryCtl.text.trim().isEmpty ? null : countryCtl.text.trim(),
                              'address': addressCtl.text.trim().isEmpty ? null : addressCtl.text.trim(),
                              'phone': phoneCtl.text.trim().isEmpty ? null : phoneCtl.text.trim(),
                              'fda_number': fdaCtl.text.trim().isEmpty ? null : fdaCtl.text.trim(),
                            };

                            if (isEdit) {
                              await sb.from('manufacturers').update(payload).eq('id', edit!['id']);
                            } else {
                              await sb.from('manufacturers').insert(payload);
                            }

                            await _loadManufacturers();
                            if (mounted) setState(() {});
                            if (ctx.mounted) Navigator.pop(ctx);
                            _toast(isEdit ? 'บันทึกการแก้ไขผู้ผลิตแล้ว ✅' : 'เพิ่มผู้ผลิตแล้ว ✅');
                          } catch (e) {
                            _toast('บันทึกไม่สำเร็จ: $e');
                          } finally {
                            if (ctx.mounted) setD(() => saving = false);
                          }
                        },
                  child: saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('บันทึก'),
                )
              ],
            );
          },
        );
      },
    );
  }

  // =========================
  // Supplier editor (เดิมของคุณ)
  // =========================
  Future<void> _showSupplierEditor({Map<String, dynamic>? edit}) async {
    final sb = _sb!;
    final ownerId = _ownerId();
    final isEdit = edit != null;

    final formKey = GlobalKey<FormState>();

    final nameCtl = TextEditingController(text: (edit?['name'] ?? '').toString());
    final codeCtl = TextEditingController(text: (edit?['code'] ?? '').toString());

    final companyCtl =
        TextEditingController(text: (edit?['company_name'] ?? '').toString());
    final contactCtl =
        TextEditingController(text: (edit?['contact_name'] ?? '').toString());

    final phoneCtl = TextEditingController(text: (edit?['phone'] ?? '').toString());
    final lineCtl = TextEditingController(text: (edit?['line_id'] ?? '').toString());
    final emailCtl = TextEditingController(text: (edit?['email'] ?? '').toString());

    final addressCtl =
        TextEditingController(text: (edit?['address'] ?? '').toString());
    final deliveryCtl =
        TextEditingController(text: (edit?['delivery_area'] ?? '').toString());

    final regCtl =
        TextEditingController(text: (edit?['company_reg_no'] ?? '').toString());
    final licenseCtl =
        TextEditingController(text: (edit?['drug_license_no'] ?? '').toString());

    final noteCtl = TextEditingController(text: (edit?['note'] ?? '').toString());
    bool isDefault = (edit?['is_default'] == true);
    bool isActive = (edit?['is_active'] == null) ? true : (edit?['is_active'] == true);

    bool saving = false;

    Widget section(String title, IconData icon, List<Widget> children) {
      return Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.black.withOpacity(0.08)),
          color: Colors.white,
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(
            children: [
              Icon(icon, size: 18),
              const SizedBox(width: 8),
              Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
            ],
          ),
          const SizedBox(height: 10),
          ...children,
        ]),
      );
    }

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return StatefulBuilder(
          builder: (ctx, setD) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Row(
                children: [
                  Icon(Icons.store_rounded, color: cs.primary),
                  const SizedBox(width: 8),
                  Text(isEdit ? 'แก้ไข Supplier' : 'เพิ่ม Supplier ใหม่',
                      style: const TextStyle(fontWeight: FontWeight.w900)),
                ],
              ),
              content: SizedBox(
                width: 640,
                child: SingleChildScrollView(
                  child: Form(
                    key: formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        section('ข้อมูลหลัก', Icons.badge_rounded, [
                          TextFormField(
                            controller: nameCtl,
                            decoration: _dec('ชื่อ Supplier *', icon: Icons.storefront_rounded),
                            validator: (v) => (v ?? '').trim().isEmpty ? 'กรุณากรอกชื่อ Supplier' : null,
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: codeCtl,
                            decoration: _dec('รหัส Supplier (ถ้ามี)', icon: Icons.qr_code_rounded),
                          ),
                        ]),
                        section('บริษัท & ผู้ติดต่อ', Icons.business_center_rounded, [
                          TextFormField(
                            controller: companyCtl,
                            decoration: _dec('ชื่อบริษัท', icon: Icons.apartment_rounded),
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: contactCtl,
                            decoration: _dec('ชื่อผู้ติดต่อ', icon: Icons.person_rounded),
                          ),
                        ]),
                        section('ช่องทางติดต่อ', Icons.contact_phone_rounded, [
                          TextFormField(
                            controller: phoneCtl,
                            decoration: _dec('เบอร์โทร', icon: Icons.phone_rounded),
                            keyboardType: TextInputType.phone,
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: lineCtl,
                            decoration: _dec('Line ID', icon: Icons.chat_rounded),
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: emailCtl,
                            decoration: _dec('Email', icon: Icons.email_rounded),
                            keyboardType: TextInputType.emailAddress,
                            validator: (v) {
                              final t = (v ?? '').trim();
                              if (t.isEmpty) return null;
                              if (!t.contains('@') || !t.contains('.')) return 'รูปแบบอีเมลไม่ถูกต้อง';
                              return null;
                            },
                          ),
                        ]),
                        section('ที่อยู่ & พื้นที่จัดส่ง', Icons.local_shipping_rounded, [
                          TextFormField(
                            controller: addressCtl,
                            maxLines: 2,
                            decoration: _dec('ที่อยู่', icon: Icons.location_on_rounded),
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: deliveryCtl,
                            decoration: _dec('พื้นที่จัดส่ง', icon: Icons.map_rounded),
                          ),
                        ]),
                        section('เอกสาร/เลขทะเบียน', Icons.verified_rounded, [
                          TextFormField(
                            controller: regCtl,
                            decoration: _dec('เลขทะเบียนบริษัท', icon: Icons.fact_check_rounded),
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: licenseCtl,
                            decoration: _dec('ใบอนุญาตจำหน่ายยา', icon: Icons.health_and_safety_rounded),
                          ),
                        ]),
                        section('การตั้งค่า', Icons.tune_rounded, [
                          TextFormField(
                            controller: noteCtl,
                            maxLines: 2,
                            decoration: _dec('หมายเหตุ', icon: Icons.notes_rounded),
                          ),
                          const SizedBox(height: 12),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            value: isActive,
                            onChanged: (v) => setD(() => isActive = v),
                            title: const Text('เปิดใช้งาน', style: TextStyle(fontWeight: FontWeight.w800)),
                            subtitle: Text(
                              isActive ? 'Supplier นี้จะแสดงใน StockIn' : 'Supplier นี้จะถูกซ่อนจากการเลือก',
                              style: TextStyle(color: Colors.black.withOpacity(0.55)),
                            ),
                          ),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            value: isDefault,
                            onChanged: (v) => setD(() => isDefault = v),
                            title: const Text('ตั้งเป็นค่าเริ่มต้น', style: TextStyle(fontWeight: FontWeight.w800)),
                            subtitle: Text(
                              'เวลาเปิดหน้ารับยาเข้า ระบบจะดึง Supplier แนะนำ',
                              style: TextStyle(color: Colors.black.withOpacity(0.55)),
                            ),
                          ),
                        ]),
                      ],
                    ),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: saving ? null : () => Navigator.pop(ctx),
                  child: const Text('ยกเลิก', style: TextStyle(color: Colors.grey)),
                ),
                FilledButton(
                  onPressed: saving
                      ? null
                      : () async {
                          if (!(formKey.currentState?.validate() ?? false)) return;

                          setD(() => saving = true);
                          try {
                            if (isDefault) {
                              await sb
                                  .from('suppliers')
                                  .update({'is_default': false})
                                  .eq('owner_id', ownerId);
                            }

                            final payload = <String, dynamic>{
                              'owner_id': ownerId,
                              'name': nameCtl.text.trim(),
                              'code': codeCtl.text.trim().isEmpty ? null : codeCtl.text.trim(),
                              'company_name': companyCtl.text.trim().isEmpty ? null : companyCtl.text.trim(),
                              'contact_name': contactCtl.text.trim().isEmpty ? null : contactCtl.text.trim(),
                              'phone': phoneCtl.text.trim().isEmpty ? null : phoneCtl.text.trim(),
                              'line_id': lineCtl.text.trim().isEmpty ? null : lineCtl.text.trim(),
                              'email': emailCtl.text.trim().isEmpty ? null : emailCtl.text.trim(),
                              'address': addressCtl.text.trim().isEmpty ? null : addressCtl.text.trim(),
                              'delivery_area': deliveryCtl.text.trim().isEmpty ? null : deliveryCtl.text.trim(),
                              'company_reg_no': regCtl.text.trim().isEmpty ? null : regCtl.text.trim(),
                              'drug_license_no': licenseCtl.text.trim().isEmpty ? null : licenseCtl.text.trim(),
                              'note': noteCtl.text.trim().isEmpty ? null : noteCtl.text.trim(),
                              'is_default': isDefault,
                              'is_active': isActive,
                            };

                            if (isEdit) {
                              await sb.from('suppliers').update(payload).eq('id', edit!['id']);
                            } else {
                              await sb.from('suppliers').insert(payload);
                            }

                            await _loadSuppliers();
                            if (mounted) setState(() {});
                            if (ctx.mounted) Navigator.pop(ctx);
                            _toast(isEdit ? 'บันทึกการแก้ไข Supplier แล้ว ✅' : 'เพิ่ม Supplier แล้ว ✅');
                          } catch (e) {
                            _toast('บันทึกไม่สำเร็จ: $e');
                          } finally {
                            if (ctx.mounted) setD(() => saving = false);
                          }
                        },
                  child: saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('บันทึก'),
                )
              ],
            );
          },
        );
      },
    );
  }

  // =========================
  // Helpers
  // =========================
  String _dateOnly(DateTime d) {
    final mm = d.month.toString().padLeft(2, '0');
    final dd = d.day.toString().padLeft(2, '0');
    return '${d.year}-$mm-$dd';
  }

  DateTime _parseDate(String ymd) {
    final parts = ymd.split('-');
    if (parts.length != 3) return DateTime.now();
    return DateTime(
      int.tryParse(parts[0]) ?? 2000,
      int.tryParse(parts[1]) ?? 1,
      int.tryParse(parts[2]) ?? 1,
    );
  }

  int _daysBetween(DateTime a, DateTime b) {
    final aa = DateTime(a.year, a.month, a.day);
    final bb = DateTime(b.year, b.month, b.day);
    return bb.difference(aa).inDays;
  }

  String _money(num v) => v.toStringAsFixed(2);
  int _pct(int part, int total) => ((part * 100) / total).round();
  String _safeLine(String? s) => (s ?? '').trim().isEmpty ? '-' : s!.trim();

  // =========================
  // ✅ Drawer (Hamburger)
  // =========================
  Widget _drawerSectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      child: Text(
        text,
        style: TextStyle(
          fontWeight: FontWeight.w900,
          color: Colors.black.withOpacity(0.55),
        ),
      ),
    );
  }

  Future<void> _logout() async {
    try {
      await _sb?.auth.signOut();
    } catch (_) {}

    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AuthGate()),
      (r) => false,
    );
  }

  Widget _buildDrawer(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final user = _sb?.auth.currentUser;

    final logoProvider = _homeLogoProvider();
    final headerTitle =
        (_shopName?.isNotEmpty == true) ? _shopName! : (user?.email ?? 'ผู้ใช้');

    Future<void> go(Widget page) async {
      Navigator.pop(context);
      final res = await Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
      if (res == true && mounted) {
        _bootstrap();
      } else {
        if (mounted) _bootstrap();
      }
    }

    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [cs.primary, cs.primary.withOpacity(0.78)],
                ),
              ),
              child: Row(
                children: [
                  CircleAvatar(
  radius: 24,
  backgroundColor: Colors.white.withOpacity(0.18),
  backgroundImage: logoProvider,
  onBackgroundImageError: logoProvider == null
      ? null
      : (_, __) {
          if (mounted) setState(() => _logoUrl = null);
        },
  child: logoProvider == null
      ? const Icon(Icons.store_rounded, color: Colors.white)
      : null,
),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          headerTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          user?.email ?? 'PharmaStock • Menu',
                          style: TextStyle(color: Colors.white.withOpacity(0.85)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  _drawerSectionTitle('การใช้งานหลัก'),
                  ListTile(
                    leading: const Icon(Icons.add_circle_outline_rounded),
                    title: const Text('เพิ่มยา'),
                    onTap: () async {
                      Navigator.pop(context);
                      final ok = await Navigator.of(context).push<bool>(
                        MaterialPageRoute(builder: (_) => const AddDrugPage()),
                      );
                      if (ok == true && mounted) _bootstrap();
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.call_received_rounded),
                    title: const Text('รับเข้า (Stock In)'),
                    onTap: () async {
                      Navigator.pop(context);
                      await Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const StockInPage()),
                      );
                      if (mounted) _bootstrap();
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.call_made_rounded),
                    title: const Text('จ่ายออก (Stock Out)'),
                    onTap: () async {
                      Navigator.pop(context);
                      await Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const StockOutPage()),
                      );
                      if (mounted) _bootstrap();
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.calendar_month_rounded),
                    title: const Text('ปฏิทินหมดอายุ'),
                    onTap: () => go(const ExpiryCalendarPage()),
                  ),
                  ListTile(
                    leading: const Icon(Icons.refresh_rounded),
                    title: const Text('รีเฟรชข้อมูล'),
                    onTap: () async {
                      Navigator.pop(context);
                      await _bootstrap();
                    },
                  ),

                  const Divider(height: 22),

                  _drawerSectionTitle('โปรไฟล์ & ระบบ'),
                  ListTile(
                    leading: const Icon(Icons.person_rounded),
                    title: const Text('โปรไฟล์'),
                    subtitle: const Text('ชื่อร้าน • ชื่อผู้ใช้ • เบอร์ • โลโก้'),
                    onTap: () => go(const ProfilePage()),
                  ),
                  ListTile(
                    leading: const Icon(Icons.security_rounded),
                    title: const Text('ความปลอดภัย'),
                    subtitle: const Text('เปลี่ยนอีเมล / เปลี่ยนรหัสผ่าน'),
                    onTap: () => go(const SecurityPage()),
                  ),
                  ListTile(
                    leading: const Icon(Icons.info_outline_rounded),
                    title: const Text('เกี่ยวกับแอป'),
                    subtitle: const Text('เวอร์ชัน • ผู้พัฒนา • ช่องทางติดต่อ'),
                    onTap: () => go(const AboutPage()),
                  ),

                  const Divider(height: 22),

                  /*ListTile(
                    leading: const Icon(Icons.logout_rounded, color: Colors.red),
                    title: const Text('ออกจากระบบ', style: TextStyle(color: Colors.red)),
                    onTap: _logout,
                  ),*/
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // =========================
  // UI
  // =========================
  @override
  Widget build(BuildContext context) {
    if (_sb == null) {
      return const SupabaseGuard(
        child: SizedBox.shrink(),
        message: '',
      );
    }

    final cs = Theme.of(context).colorScheme;

    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_error != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Text('เกิดข้อผิดพลาด: $_error'),
          ),
        ),
      );
    }

    final totalLotForStatus =
        (_expiredCount + _nearExpireCount + (_lotCount - _expiredCount - _nearExpireCount))
            .clamp(1, 1 << 30);
    final okLots = (_lotCount - _expiredCount - _nearExpireCount).clamp(0, 1 << 30);

    final user = _sb!.auth.currentUser;

    return Scaffold(
      drawer: _buildDrawer(context),
      backgroundColor: const Color(0xFFF4F7FB),
      body: RefreshIndicator(
        onRefresh: _bootstrap,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ================= HERO =================
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                gradient: LinearGradient(
                  colors: [cs.primary, cs.primary.withOpacity(0.78)],
                ),
                boxShadow: [
                  BoxShadow(
                    color: cs.primary.withOpacity(0.25),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(
                  children: [
                    // ✅ Hamburger button
                    Builder(
                      builder: (ctx) => IconButton(
                        tooltip: 'เมนู',
                        onPressed: () => Scaffold.of(ctx).openDrawer(),
                        icon: const Icon(Icons.menu_rounded, color: Colors.white),
                      ),
                    ),

                    // ✅ (optional) ใช้โลโก้ใน hero ด้วย
                    Builder(builder: (_) {
                      final heroLogo = _homeLogoProvider();
                      return Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.18),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.white.withOpacity(0.20)),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: heroLogo == null
                            ? const Icon(Icons.medication_rounded, color: Colors.white)
                            : Image(
                                image: heroLogo,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) =>
                                    const Icon(Icons.medication_rounded, color: Colors.white),
                              ),
                      );
                    }),

                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text(
                          'PharmaStock Dashboard',
                          style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900),
                        ),
                        Text(
                          user?.email ?? '',
                          style: TextStyle(color: Colors.white.withOpacity(0.85)),
                        ),
                        if ((_displayName ?? '').trim().isNotEmpty || (_shopName ?? '').trim().isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              [
                                if ((_shopName ?? '').trim().isNotEmpty) _shopName!.trim(),
                                if ((_displayName ?? '').trim().isNotEmpty) _displayName!.trim(),
                              ].join(' • '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: Colors.white.withOpacity(0.85), fontWeight: FontWeight.w700),
                            ),
                          ),
                      ]),
                    ),

                    IconButton(
                      tooltip: 'ปฏิทินหมดอายุ',
                      onPressed: () async {
                        await Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const ExpiryCalendarPage()),
                        );
                        if (mounted) _bootstrap();
                      },
                      icon: const Icon(Icons.calendar_month_rounded, color: Colors.white),
                    ),
                    IconButton(
                      tooltip: 'รีเฟรช',
                      onPressed: _bootstrap,
                      icon: const Icon(Icons.refresh_rounded, color: Colors.white),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _quickBtn(context, Icons.add_rounded, 'เพิ่มยา', () async {
                      final ok = await Navigator.of(context).push<bool>(
                        MaterialPageRoute(builder: (_) => const AddDrugPage()),
                      );
                      if (ok == true && mounted) _bootstrap();
                    }),
                    _quickBtn(context, Icons.call_received_rounded, 'รับเข้า', () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const StockInPage()),
                      );
                      if (mounted) _bootstrap();
                    }),
                    _quickBtn(context, Icons.call_made_rounded, 'จ่ายออก', () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const StockOutPage()),
                      );
                      if (mounted) _bootstrap();
                    }),
                  ],
                ),
              ]),
            ),

            const SizedBox(height: 14),

            // ✅ แจ้งเตือนสำคัญ (กดดูรายละเอียดได้)
            if (_expiredCount > 0 || _nearExpireCount > 0 || _lowStockCount > 0)
              _panel(
                title: 'แจ้งเตือนสำคัญ',
                icon: Icons.notifications_active_rounded,
                child: Column(
                  children: [
                    if (_expiredCount > 0)
                      _alertRow(
                        Icons.error_outline_rounded,
                        'ล็อตหมดอายุ $_expiredCount รายการ',
                        Colors.red,
                        onTap: () => _openAlertSheet(_AlertType.expired),
                      ),
                    if (_nearExpireCount > 0)
                      _alertRow(
                        Icons.schedule_rounded,
                        'ล็อตใกล้หมดอายุ $_nearExpireCount รายการ',
                        Colors.orange,
                        onTap: () => _openAlertSheet(_AlertType.nearExpire),
                      ),
                    if (_lowStockCount > 0)
                      _alertRow(
                        Icons.inventory_2_rounded,
                        'ยาสต็อกต่ำ/หมด $_lowStockCount รายการ',
                        Colors.deepOrange,
                        onTap: () => _openAlertSheet(_AlertType.lowStock),
                      ),
                  ],
                ),
              ),

            const SizedBox(height: 12),

            // ================= KPI GRID =================
            LayoutBuilder(
              builder: (context, c) {
                final wide = c.maxWidth >= 760;
                final w = wide ? (c.maxWidth - 12) / 2 : c.maxWidth;
                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    SizedBox(
                      width: w,
                      child: _statCard(
                        title: 'ยาในระบบ',
                        value: '$_drugCount',
                        sub: 'จำนวนรายการยา (master)',
                        icon: Icons.medication_rounded,
                        tone: cs.primary,
                      ),
                    ),
                    SizedBox(
                      width: w,
                      child: _statCard(
                        title: 'ล็อตที่มีของ',
                        value: '$_lotCount',
                        sub: 'นับเฉพาะล็อตคงเหลือ > 0',
                        icon: Icons.inventory_2_rounded,
                        tone: Colors.indigo,
                      ),
                    ),
                    SizedBox(
                      width: w,
                      child: _statCard(
                        title: 'คงเหลือรวม',
                        value: _onHandBaseTotal.toStringAsFixed(0),
                        sub: 'รวมหน่วยฐานทุกล็อต',
                        icon: Icons.widgets_rounded,
                        tone: Colors.teal,
                      ),
                    ),
                    SizedBox(
                      width: w,
                      child: _statCard(
                        title: 'กำไรโดยประมาณ',
                        value: '${_money(_profitEst)} ฿',
                        sub: 'ช่วง $_days วันล่าสุด',
                        icon: Icons.savings_rounded,
                        tone: _profitEst >= 0 ? Colors.green : Colors.red,
                      ),
                    ),
                  ],
                );
              },
            ),

            const SizedBox(height: 12),

            _panel(
              title: 'ภาพรวมล็อต (ปกติ/ใกล้หมด/หมดอายุ)',
              icon: Icons.pie_chart_rounded,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'คงเหลือรวม (หน่วยฐาน): ${_onHandBaseTotal.toStringAsFixed(2)} • ยาที่ต้องดูแล (low/out): $_lowStockCount',
                    style: TextStyle(color: Colors.black.withOpacity(0.55)),
                  ),
                  const SizedBox(height: 12),
                  _statusBar(
                    ok: okLots,
                    near: _nearExpireCount,
                    expired: _expiredCount,
                    total: totalLotForStatus,
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    children: [
                      _legendDot('ปกติ', Colors.green, '${_pct(okLots, totalLotForStatus)}%'),
                      _legendDot('ใกล้หมด', Colors.orange, '${_pct(_nearExpireCount, totalLotForStatus)}%'),
                      _legendDot('หมดอายุ', Colors.red, '${_pct(_expiredCount, totalLotForStatus)}%'),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            _panel(
              title: '📊 กราฟเส้นยอดขาย',
              icon: Icons.show_chart_rounded,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _daysChip(7),
                  const SizedBox(width: 8),
                  _daysChip(30),
                  const SizedBox(width: 8),
                  _daysChip(90),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'ยอดขายรวมช่วง $_days วัน: ${_money(_sales)} ฿',
                    style: TextStyle(color: Colors.black.withOpacity(0.65), fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 180,
                    width: double.infinity,
                    child: _salesSeries.isEmpty
                        ? Center(child: Text('ยังไม่มีข้อมูลยอดขาย', style: TextStyle(color: Colors.black.withOpacity(0.55))))
                        : _LineChart(points: _salesSeries),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            _panel(
              title: '📦 Top 5 ยาขายดี',
              icon: Icons.leaderboard_rounded,
              child: _top5.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text('ยังไม่มีข้อมูลการขายในช่วงนี้', style: TextStyle(color: Colors.black.withOpacity(0.55))),
                    )
                  : Column(
                      children: List.generate(_top5.length, (i) {
                        final t = _top5[i];
                        return _topRow(rank: i + 1, t: t);
                      }),
                    ),
            ),

            const SizedBox(height: 12),

            _panel(
              title: '🏭 บริษัทผู้ผลิต',
              icon: Icons.domain_rounded,
              trailing: FilledButton.icon(
                onPressed: () => _showManufacturerEditor(),
                icon: const Icon(Icons.add_rounded),
                label: const Text('เพิ่ม'),
              ),
              child: Column(
                children: [
                  TextField(
                    controller: _mSearchCtl,
                    decoration: _dec('ค้นหาผู้ผลิต (ชื่อ/ประเทศ/โทร/อย./รหัส)', icon: Icons.search_rounded).copyWith(
                      suffixIcon: _mQ.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.close_rounded),
                              onPressed: () => _mSearchCtl.clear(),
                            ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_filteredManufacturers.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text('ยังไม่มีข้อมูลผู้ผลิต', style: TextStyle(color: Colors.black.withOpacity(0.55))),
                    )
                  else
                    Column(
                      children: List.generate(_filteredManufacturers.length, (i) {
                        final m = _filteredManufacturers[i];
                        return _entityTile(
                          leadingIcon: Icons.domain_rounded,
                          title: (m['name'] ?? '-').toString(),
                          badgeText: ((m['code'] ?? '').toString().trim().isEmpty) ? null : (m['code'] ?? '').toString(),
                          subtitleLines: [
                            'ประเทศ: ${_safeLine((m['country'] ?? '').toString())}',
                            'โทร: ${_safeLine((m['phone'] ?? '').toString())}',
                            'อย.: ${_safeLine((m['fda_number'] ?? '').toString())}',
                            'ที่อยู่: ${_safeLine((m['address'] ?? '').toString())}',
                          ],
                          onTap: () => _showManufacturerEditor(edit: m),
                        );
                      }),
                    ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            _panel(
              title: '🚚 Supplier',
              icon: Icons.store_rounded,
              trailing: FilledButton.icon(
                onPressed: () => _showSupplierEditor(),
                icon: const Icon(Icons.add_rounded),
                label: const Text('เพิ่ม'),
              ),
              child: Column(
                children: [
                  TextField(
                    controller: _sSearchCtl,
                    decoration: _dec('ค้นหา Supplier (ชื่อ/บริษัท/ผู้ติดต่อ/โทร/Line/Email/ใบอนุญาต)', icon: Icons.search_rounded)
                        .copyWith(
                      suffixIcon: _sQ.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.close_rounded),
                              onPressed: () => _sSearchCtl.clear(),
                            ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_filteredSuppliers.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text('ยังไม่มีข้อมูล Supplier', style: TextStyle(color: Colors.black.withOpacity(0.55))),
                    )
                  else
                    Column(
                      children: List.generate(_filteredSuppliers.length, (i) {
                        final s = _filteredSuppliers[i];
                        final isDefault = s['is_default'] == true;
                        final isActive = (s['is_active'] == null) ? true : (s['is_active'] == true);

                        final title = (s['name'] ?? '-').toString();
                        final company = (s['company_name'] ?? '').toString().trim();
                        final contact = (s['contact_name'] ?? '').toString().trim();
                        final phone = (s['phone'] ?? '').toString().trim();
                        final lineId = (s['line_id'] ?? '').toString().trim();
                        final email = (s['email'] ?? '').toString().trim();
                        final delivery = (s['delivery_area'] ?? '').toString().trim();
                        final reg = (s['company_reg_no'] ?? '').toString().trim();
                        final lic = (s['drug_license_no'] ?? '').toString().trim();

                        return _entityTile(
                          leadingIcon: isDefault ? Icons.star_rounded : Icons.storefront_rounded,
                          leadingColor: isDefault ? Colors.amber.shade700 : null,
                          title: title,
                          badgeText: isDefault
                              ? 'DEFAULT'
                              : (((s['code'] ?? '').toString().trim().isEmpty) ? null : (s['code'] ?? '').toString()),
                          badgeTone: isDefault ? Colors.amber : null,
                          subtitleLines: [
                            'สถานะ: ${isActive ? 'เปิดใช้งาน' : 'ปิดใช้งาน'}',
                            if (company.isNotEmpty) 'บริษัท: $company',
                            if (contact.isNotEmpty) 'ผู้ติดต่อ: $contact',
                            if (phone.isNotEmpty) 'โทร: $phone',
                            if (lineId.isNotEmpty) 'Line: $lineId',
                            if (email.isNotEmpty) 'Email: $email',
                            if (delivery.isNotEmpty) 'พื้นที่จัดส่ง: $delivery',
                            if (reg.isNotEmpty) 'ทะเบียนบริษัท: $reg',
                            if (lic.isNotEmpty) 'ใบอนุญาตยา: $lic',
                            if (company.isEmpty &&
                                contact.isEmpty &&
                                phone.isEmpty &&
                                lineId.isEmpty &&
                                email.isEmpty &&
                                delivery.isEmpty &&
                                reg.isEmpty &&
                                lic.isEmpty)
                              'รายละเอียด: -',
                          ],
                          onTap: () => _showSupplierEditor(edit: s),
                        );
                      }),
                    ),
                ],
              ),
            ),

            const SizedBox(height: 18),
          ],
        ),
      ),
    );
  }

  // =========================
  // Widgets
  // =========================
  Widget _panel({
    required String title,
    required IconData icon,
    required Widget child,
    Widget? trailing,
  }) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(
            children: [
              Icon(icon),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                ),
              ),
              if (trailing != null) trailing,
            ],
          ),
          const SizedBox(height: 12),
          child,
        ]),
      ),
    );
  }

  Widget _entityTile({
    required IconData leadingIcon,
    Color? leadingColor,
    required String title,
    String? badgeText,
    Color? badgeTone,
    required List<String> subtitleLines,
    required VoidCallback onTap,
  }) {
    final cs = Theme.of(context).colorScheme;
    final tone = badgeTone ?? cs.primary;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withOpacity(0.08)),
        color: Colors.white,
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: (leadingColor ?? cs.primary).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(leadingIcon, color: leadingColor ?? cs.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                      if (badgeText != null && badgeText.trim().isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(999),
                            color: tone.withOpacity(0.12),
                            border: Border.all(color: tone.withOpacity(0.25)),
                          ),
                          child: Text(
                            badgeText,
                            style: TextStyle(fontWeight: FontWeight.w900, color: tone, fontSize: 12),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  for (final l in subtitleLines.take(6))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text(
                        l,
                        style: TextStyle(color: Colors.black.withOpacity(0.65), fontWeight: FontWeight.w600, height: 1.25),
                      ),
                    ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(Icons.edit_rounded, size: 16, color: cs.primary.withOpacity(0.9)),
                      const SizedBox(width: 6),
                      Text('แตะเพื่อแก้ไข', style: TextStyle(color: cs.primary.withOpacity(0.9), fontWeight: FontWeight.w800)),
                    ],
                  )
                ]),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _quickBtn(BuildContext context, IconData icon, String text, VoidCallback onTap) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.15),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withOpacity(0.22)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: Colors.white),
          const SizedBox(width: 8),
          Text(text, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          const SizedBox(width: 2),
          Icon(Icons.chevron_right_rounded, color: cs.onPrimary.withOpacity(0.9), size: 18),
        ]),
      ),
    );
  }

  // ✅ ทำให้แถวแจ้งเตือน "กดได้"
  Widget _alertRow(IconData icon, String text, Color c, {VoidCallback? onTap}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          child: Row(
            children: [
              Icon(icon, color: c, size: 20),
              const SizedBox(width: 8),
              Expanded(child: Text(text, style: TextStyle(color: c, fontWeight: FontWeight.w800))),
              if (onTap != null) Icon(Icons.chevron_right_rounded, color: c.withOpacity(0.85)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _daysChip(int d) {
    final on = _days == d;
    return ChoiceChip(
      label: Text('$d วัน'),
      selected: on,
      onSelected: (v) async {
        setState(() => _days = d);
        setState(() => _loading = true);

        await Future.wait([
          _loadFinance(days: d),
          _loadSalesSeries(days: d),
          _loadTopSellers(days: d),
        ]);

        if (mounted) setState(() => _loading = false);
      },
    );
  }

  Widget _statCard({
    required String title,
    required String value,
    required String sub,
    required IconData icon,
    required Color tone,
  }) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: tone.withOpacity(0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: tone),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
                const SizedBox(height: 6),
                Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
                const SizedBox(height: 2),
                Text(sub, style: TextStyle(color: Colors.black.withOpacity(0.55))),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusBar({required int ok, required int near, required int expired, required int total}) {
    double wOk = ok / total;
    double wNear = near / total;
    double wExp = expired / total;

    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: Row(
        children: [
          Expanded(flex: (wOk * 1000).round().clamp(1, 1000), child: Container(height: 12, color: Colors.green)),
          Expanded(flex: (wNear * 1000).round().clamp(1, 1000), child: Container(height: 12, color: Colors.orange)),
          Expanded(flex: (wExp * 1000).round().clamp(1, 1000), child: Container(height: 12, color: Colors.red)),
        ],
      ),
    );
  }

  Widget _legendDot(String label, Color c, String pct) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text('$label ($pct)', style: TextStyle(color: Colors.black.withOpacity(0.70), fontWeight: FontWeight.w700)),
      ],
    );
  }

  Widget _topRow({required int rank, required _TopDrug t}) {
    final cs = Theme.of(context).colorScheme;
    final badge = rank == 1
        ? Colors.amber
        : (rank == 2 ? Colors.grey : (rank == 3 ? Colors.brown : cs.primary.withOpacity(0.6)));

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).dividerColor),
        color: Colors.white,
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(color: badge.withOpacity(0.15), borderRadius: BorderRadius.circular(12)),
            alignment: Alignment.center,
            child: Text(
              '$rank',
              style: TextStyle(fontWeight: FontWeight.w900, color: badge),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900)),
              const SizedBox(height: 4),
              Text(
                'ขาย ${t.qtyBase.toStringAsFixed(0)} ${t.baseUnit} • ยอดขาย ${_money(t.sales)} ฿',
                style: TextStyle(color: Colors.black.withOpacity(0.60), fontWeight: FontWeight.w700, fontSize: 13),
              ),
            ]),
          ),
        ],
      ),
    );
  }
}

// =========================
// Chart
// =========================
class _ChartPoint {
  final double x;
  final double y;
  final String label;
  const _ChartPoint(this.x, this.y, {required this.label});
}

class _LineChart extends StatelessWidget {
  final List<_ChartPoint> points;
  const _LineChart({required this.points});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _LineChartPainter(points: points, color: Theme.of(context).colorScheme.primary),
      child: const SizedBox.expand(),
    );
  }
}

class _LineChartPainter extends CustomPainter {
  final List<_ChartPoint> points;
  final Color color;
  _LineChartPainter({required this.points, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;

    const padding = 14.0;
    final w = size.width;
    final h = size.height;

    final plotRect = Rect.fromLTWH(padding, padding, w - padding * 2, h - padding * 2);

    final minX = points.first.x;
    final maxX = points.last.x;

    double minY = points.map((p) => p.y).reduce(math.min);
    double maxY = points.map((p) => p.y).reduce(math.max);
    if (minY == maxY) maxY = minY + 1;

    final gridPaint = Paint()
      ..color = Colors.black.withOpacity(0.06)
      ..strokeWidth = 1;

    for (int i = 0; i <= 4; i++) {
      final yy = plotRect.top + (plotRect.height * i / 4);
      canvas.drawLine(Offset(plotRect.left, yy), Offset(plotRect.right, yy), gridPaint);
    }

    final borderPaint = Paint()
      ..color = Colors.black.withOpacity(0.08)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawRRect(RRect.fromRectAndRadius(plotRect, const Radius.circular(12)), borderPaint);

    Offset mapPoint(_ChartPoint p) {
      final dx = (p.x - minX) / (maxX - minX == 0 ? 1 : (maxX - minX));
      final dy = (p.y - minY) / (maxY - minY);
      final x = plotRect.left + dx * plotRect.width;
      final y = plotRect.bottom - dy * plotRect.height;
      return Offset(x, y);
    }

    final path = Path();
    final mapped = points.map(mapPoint).toList();
    path.moveTo(mapped.first.dx, mapped.first.dy);
    for (int i = 1; i < mapped.length; i++) {
      path.lineTo(mapped[i].dx, mapped[i].dy);
    }

    final area = Path.from(path)
      ..lineTo(mapped.last.dx, plotRect.bottom)
      ..lineTo(mapped.first.dx, plotRect.bottom)
      ..close();

    canvas.drawPath(area, Paint()..color = color.withOpacity(0.10));

    final linePaint = Paint()
      ..color = color.withOpacity(0.90)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    canvas.drawPath(path, linePaint);

    final dotPaint = Paint()..color = color;
    for (final pt in mapped) {
      canvas.drawCircle(pt, 3.4, dotPaint);
      canvas.drawCircle(pt, 6.2, Paint()..color = color.withOpacity(0.08));
    }
  }

  @override
  bool shouldRepaint(covariant _LineChartPainter oldDelegate) {
    return oldDelegate.points != points || oldDelegate.color != color;
  }
}

// =========================
// Alert Models (NEW)
// =========================
enum _AlertType { expired, nearExpire, lowStock }

class _DrugInfo {
  final String drugId;
  final String code;
  final String name;
  final String baseUnit;
  final num reorderPoint;
  final int expiryAlertDays;

  const _DrugInfo({
    required this.drugId,
    required this.code,
    required this.name,
    required this.baseUnit,
    required this.reorderPoint,
    required this.expiryAlertDays,
  });
}

class _LotRow {
  final String lotId;
  final String drugId;
  final String lotNo;
  final DateTime expDate;
  final num qtyBase;

  final String code;
  final String genericName;
  final String brandName;
  final String baseUnit;
  final int expiryAlertDays;
  final num reorderPoint;

  const _LotRow({
    required this.lotId,
    required this.drugId,
    required this.lotNo,
    required this.expDate,
    required this.qtyBase,
    required this.code,
    required this.genericName,
    required this.brandName,
    required this.baseUnit,
    required this.expiryAlertDays,
    required this.reorderPoint,
  });
}

class _DrugAlertGroup {
  final _DrugInfo info;
  final List<_LotRow> lots;
  final num? totalBase;

  _DrugAlertGroup({required this.info, required this.lots, this.totalBase});

  DateTime get nextExpDate {
    if (lots.isEmpty) return DateTime(2100);
    lots.sort((a, b) => a.expDate.compareTo(b.expDate));
    return lots.first.expDate;
  }
}

// =========================
// Top Models (เดิม)
// =========================
class _TopDrugAgg {
  final String drugId;
  final String name;
  final String baseUnit;
  num qtyBase = 0;
  num sales = 0;
  _TopDrugAgg({required this.drugId, required this.name, required this.baseUnit});
}

class _TopDrug {
  final String drugId;
  final String name;
  final String baseUnit;
  final num qtyBase;
  final num sales;
  _TopDrug({
    required this.drugId,
    required this.name,
    required this.baseUnit,
    required this.qtyBase,
    required this.sales,
  });
}