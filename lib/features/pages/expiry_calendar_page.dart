import 'dart:collection';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../core/supabase_guard.dart';

class ExpiryCalendarPage extends StatefulWidget {
  const ExpiryCalendarPage({super.key});

  @override
  State<ExpiryCalendarPage> createState() => _ExpiryCalendarPageState();
}

class _ExpiryCalendarPageState extends State<ExpiryCalendarPage> {
  SupabaseClient? _sb;

  bool _loadingMonth = true;
  bool _loadingDay = false;
  String? _error;

  CalendarFormat _format = CalendarFormat.month;
  DateTime _focusedDay = DateTime.now();
  DateTime _selectedDay = DateTime.now();

  // Search
  final TextEditingController _searchCtl = TextEditingController();
  String _q = '';

  // markers for month: key=dateOnly => summary
  final Map<DateTime, _DaySummary> _monthSummary = {};

  // selected day rows
  List<_ExpiryRow> _rows = [];

  @override
  void initState() {
    super.initState();
    _sb = Supabase.instance.client;

    final u = _sb?.auth.currentUser;
    if (_sb == null || u == null) {
      setState(() {
        _loadingMonth = false;
        _error = 'ยังไม่ได้ล็อกอิน หรือยังไม่ได้ตั้งค่า Supabase';
      });
      return;
    }

    _searchCtl.addListener(() {
      setState(() => _q = _searchCtl.text.trim().toLowerCase());
    });

    _focusedDay = _dateOnly(DateTime.now());
    _selectedDay = _dateOnly(DateTime.now());

    _loadMonth(_focusedDay);
    _loadForDay(_selectedDay);
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

  DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  String _dateOnlyStr(DateTime d) {
    final mm = d.month.toString().padLeft(2, '0');
    final dd = d.day.toString().padLeft(2, '0');
    return '${d.year}-$mm-$dd';
  }

  DateTime _parseDate(String ymd) {
    // รองรับ "YYYY-MM-DD" เป็นหลัก
    final p = ymd.split('-');
    if (p.length != 3) return DateTime.now();
    return DateTime(
      int.tryParse(p[0]) ?? DateTime.now().year,
      int.tryParse(p[1]) ?? DateTime.now().month,
      int.tryParse(p[2]) ?? DateTime.now().day,
    );
  }

  int _daysBetween(DateTime a, DateTime b) {
    final aa = _dateOnly(a);
    final bb = _dateOnly(b);
    return bb.difference(aa).inDays;
  }

  num _pickQty(dynamic row) {
    // ✅ กันกรณี qty_on_hand_base ไม่ถูกอัปเดต แต่ qty_on_hand ถูกอัปเดต
    final base = row is Map ? row['qty_on_hand_base'] : null;
    final raw = row is Map ? row['qty_on_hand'] : null;
    return (base as num?) ?? (raw as num?) ?? 0;
  }

  // =========================
  // LOAD MONTH SUMMARY (markers)
  // =========================
  Future<void> _loadMonth(DateTime focused) async {
    if (_sb == null) return;

    setState(() {
      _loadingMonth = true;
      _error = null;
    });

    try {
      final sb = _sb!;
      final ownerId = _ownerId();

      final first = DateTime(focused.year, focused.month, 1);
      final last = DateTime(focused.year, focused.month + 1, 0);
      final startStr = _dateOnlyStr(first);
      final endStr = _dateOnlyStr(last);

      // ✅ ดึง lots ในเดือนนั้น + join drugs เพื่อได้ expire_warn_days
      // ✅ เพิ่ม qty_on_hand เพื่อ fallback
      final rows = await sb
          .from('drug_lots')
          .select('exp_date, qty_on_hand_base, qty_on_hand, drugs(expire_warn_days)')
          .eq('owner_id', ownerId)
          .gte('exp_date', startStr)
          .lte('exp_date', endStr);

      final map = <DateTime, _DaySummary>{};
      final now = _dateOnly(DateTime.now());

      for (final r in (rows as List)) {
        final qty = _pickQty(r);
        if (qty <= 0) continue;

        final expStr = (r['exp_date'] ?? '').toString();
        if (expStr.isEmpty) continue;

        final exp = _dateOnly(_parseDate(expStr));
        final drugs = (r['drugs'] as Map?) ?? {};
        final warnDays = (drugs['expire_warn_days'] as int?) ?? 90;

        final diff = _daysBetween(now, exp);
        final status = (diff < 0)
            ? _ExpiryStatus.expired
            : (diff <= warnDays ? _ExpiryStatus.near : _ExpiryStatus.ok);

        map.putIfAbsent(exp, () => _DaySummary());
        map[exp]!.add(status);
      }

      if (!mounted) return;
      setState(() {
        _monthSummary
          ..clear()
          ..addAll(map);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loadingMonth = false);
    }
  }

  // =========================
  // LOAD SELECTED DAY DETAILS
  // =========================
  Future<void> _loadForDay(DateTime day) async {
    if (_sb == null) return;

    setState(() {
      _loadingDay = true;
      _error = null;
    });

    try {
      final sb = _sb!;
      final ownerId = _ownerId();

      final dayStr = _dateOnlyStr(day);

      // ✅ เพิ่ม qty_on_hand เพื่อ fallback
      final lots = await sb
          .from('drug_lots')
          .select(
              'drug_id, lot_no, exp_date, qty_on_hand_base, qty_on_hand, drugs (generic_name, code, base_unit, expire_warn_days)')
          .eq('owner_id', ownerId)
          .eq('exp_date', dayStr)
          .order('lot_no', ascending: true);

      final now = _dateOnly(DateTime.now());
      final out = <_ExpiryRow>[];

      for (final r in (lots as List)) {
        final qty = _pickQty(r);
        if (qty <= 0) continue;

        final d = (r['drugs'] as Map?) ?? {};
        final name = (d['generic_name'] ?? '').toString();
        final code = (d['code'] ?? '').toString();
        final baseUnit = (d['base_unit'] ?? '').toString();
        final warn = (d['expire_warn_days'] as int?) ?? 90;

        final exp = _parseDate(dayStr);
        final diff = _daysBetween(now, _dateOnly(exp));
        final status = (diff < 0) ? _ExpiryStatus.expired : (diff <= warn ? _ExpiryStatus.near : _ExpiryStatus.ok);

        out.add(_ExpiryRow(
          drugName: name,
          drugCode: code,
          baseUnit: baseUnit,
          lotNo: (r['lot_no'] ?? '').toString(),
          expDate: dayStr,
          qtyBase: qty,
          warnDays: warn,
          daysLeft: diff,
          status: status,
        ));
      }

      if (!mounted) return;
      setState(() => _rows = out);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loadingDay = false);
    }
  }

  List<_ExpiryRow> get _filteredRows {
    if (_q.isEmpty) return _rows;
    return _rows.where((x) {
      final a = x.drugName.toLowerCase();
      final b = x.drugCode.toLowerCase();
      final c = x.lotNo.toLowerCase();
      return a.contains(_q) || b.contains(_q) || c.contains(_q);
    }).toList();
  }

  List<_ExpiryRow> _eventsForDay(DateTime day) {
    // ใช้ summary เป็นตัวตัดสินว่า "มี event" (ไม่ต้องคืนรายการเต็ม)
    final s = _monthSummary[_dateOnly(day)];
    if (s == null || s.total == 0) return const [];
    // คืน list dummy เพื่อให้ TableCalendar แสดง marker
    return List.generate(s.total.clamp(1, 4), (_) => const _ExpiryRow.empty());
  }

  @override
  Widget build(BuildContext context) {
    final u = _sb?.auth.currentUser;
    if (_sb == null || u == null) {
      return const SupabaseGuard(
        child: SizedBox.shrink(),
        message: 'ปฏิทินหมดอายุต้องล็อกอินก่อน',
      );
    }

    final dark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: dark ? const Color(0xFF0B1220) : const Color.fromARGB(124, 0, 0, 0),
      appBar: AppBar(
        title: const Text('Expiry Calendar'),
        actions: [
          IconButton(
            tooltip: 'รีเฟรชเดือนนี้',
            onPressed: () async {
              await _loadMonth(_focusedDay);
              await _loadForDay(_selectedDay);
            },
            icon: const Icon(Icons.refresh_rounded),
          )
        ],
      ),
      body: (_error != null)
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text('เกิดข้อผิดพลาด: $_error'),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Calendar card
                Card(
                  elevation: 0,
                  color: dark ? const Color(0xFF0F172A) : Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_loadingMonth)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Row(
                              children: const [
                                SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                                SizedBox(width: 10),
                                Text('กำลังโหลดปฏิทิน...'),
                              ],
                            ),
                          ),

                        TableCalendar<_ExpiryRow>(
                          firstDay: DateTime.now().subtract(const Duration(days: 365 * 5)),
                          lastDay: DateTime.now().add(const Duration(days: 365 * 10)),
                          focusedDay: _focusedDay,
                          calendarFormat: _format,
                          startingDayOfWeek: StartingDayOfWeek.sunday,
                          availableCalendarFormats: const {
                            CalendarFormat.month: 'เดือน',
                            CalendarFormat.week: 'สัปดาห์',
                          },

                          selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
                          eventLoader: _eventsForDay,

                          onDaySelected: (selected, focused) async {
                            setState(() {
                              _selectedDay = _dateOnly(selected);
                              _focusedDay = _dateOnly(focused);
                            });
                            await _loadForDay(_selectedDay);
                          },

                          onPageChanged: (focused) async {
                            setState(() => _focusedDay = _dateOnly(focused));
                            await _loadMonth(_focusedDay);
                            // ไม่บังคับโหลดวัน (เดี๋ยวหนัก) แต่ถ้าคุณอยากให้ชัวร์ว่าเลือกวันเดิมในเดือนใหม่:
                            // await _loadForDay(_selectedDay);
                          },

                          onFormatChanged: (f) {
                            setState(() => _format = f);
                          },

                          headerStyle: HeaderStyle(
                            titleCentered: false,
                            formatButtonVisible: true,
                            leftChevronIcon:
                                Icon(Icons.chevron_left_rounded, color: dark ? Colors.white : Colors.black),
                            rightChevronIcon:
                                Icon(Icons.chevron_right_rounded, color: dark ? Colors.white : Colors.black),
                            titleTextStyle: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 18,
                              color: dark ? Colors.white : Colors.black,
                            ),
                            formatButtonTextStyle: const TextStyle(fontWeight: FontWeight.w900),
                            formatButtonDecoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(999),
                              color: dark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.05),
                            ),
                          ),

                          daysOfWeekStyle: DaysOfWeekStyle(
                            weekdayStyle: TextStyle(
                              color: dark ? Colors.white70 : Colors.black87,
                              fontWeight: FontWeight.w800,
                            ),
                            weekendStyle: TextStyle(
                              color: dark ? Colors.white70 : Colors.black87,
                              fontWeight: FontWeight.w800,
                            ),
                          ),

                          calendarStyle: CalendarStyle(
                            isTodayHighlighted: true,
                            todayDecoration: BoxDecoration(
                              color: Colors.blue.withOpacity(0.25),
                              shape: BoxShape.circle,
                            ),
                            selectedDecoration: const BoxDecoration(
                              color: Color(0xFF3B82F6),
                              shape: BoxShape.circle,
                            ),
                            defaultTextStyle: TextStyle(color: dark ? Colors.white : Colors.black),
                            weekendTextStyle: TextStyle(color: dark ? Colors.white : Colors.black),
                            outsideTextStyle: TextStyle(color: dark ? Colors.white24 : Colors.black26),
                            markerDecoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.transparent,
                            ),
                            markersMaxCount: 4,
                          ),

                          calendarBuilders: CalendarBuilders(
                            markerBuilder: (context, day, events) {
                              final s = _monthSummary[_dateOnly(day)];
                              if (s == null || s.total == 0) return const SizedBox.shrink();

                              // ✅ จุดแดงต้องขึ้นเมื่อมี expired > 0
                              // แสดง dot 1-3 สีตาม status
                              final dots = <Color>[];
                              if (s.expired > 0) dots.add(Colors.red);
                              if (s.near > 0) dots.add(Colors.orange);
                              if (s.ok > 0) dots.add(Colors.green);

                              return Positioned(
                                bottom: 6,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: dots
                                      .take(3)
                                      .map((c) => Container(
                                            width: 6,
                                            height: 6,
                                            margin: const EdgeInsets.symmetric(horizontal: 1.5),
                                            decoration: BoxDecoration(color: c, shape: BoxShape.circle),
                                          ))
                                      .toList(),
                                ),
                              );
                            },
                          ),
                        ),

                        const SizedBox(height: 10),

                        Wrap(
                          spacing: 10,
                          runSpacing: 8,
                          children: [
                            _legend('หมดอายุ', Colors.red),
                            _legend('ใกล้หมด', Colors.orange),
                            _legend('ปกติ', Colors.green),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                // Search + Selected day header
                Card(
                  elevation: 0,
                  color: dark ? const Color(0xFF0F172A) : Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.event_available_rounded),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'รายการล็อต EXP: ${_dateOnlyStr(_selectedDay)}',
                                style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 16,
                                  color: dark ? Colors.white : Colors.black,
                                ),
                              ),
                            ),
                            if (_loadingDay)
                              const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                          ],
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _searchCtl,
                          decoration: InputDecoration(
                            prefixIcon: const Icon(Icons.search_rounded),
                            hintText: 'ค้นหา (ชื่อยา / รหัส / lot)',
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                            filled: true,
                            fillColor: dark ? Colors.white.withOpacity(0.06) : const Color(0xFFF7F9FC),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                // List
                ..._buildRowsList(dark),
              ],
            ),
    );
  }

  List<Widget> _buildRowsList(bool dark) {
    final list = _filteredRows;

    if (list.isEmpty) {
      return [
        Center(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Text(
              'ไม่มีล็อตที่ยังมีคงเหลือในวันนี้',
              style: TextStyle(color: dark ? Colors.white70 : Colors.grey.shade700),
            ),
          ),
        ),
      ];
    }

    return list.map((r) => _expiryTile(r, dark)).toList();
  }

  Widget _legend(String label, Color c) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
      ],
    );
  }

  Widget _expiryTile(_ExpiryRow r, bool dark) {
    Color tone;
    String badge;

    switch (r.status) {
      case _ExpiryStatus.expired:
        tone = Colors.red;
        badge = 'หมดอายุ';
        break;
      case _ExpiryStatus.near:
        tone = Colors.orange;
        badge = 'ใกล้หมด';
        break;
      case _ExpiryStatus.ok:
        tone = Colors.green;
        badge = 'ปกติ';
        break;
    }

    final title = '${r.drugName}${r.drugCode.isEmpty ? '' : ' (${r.drugCode})'}';

    return Card(
      elevation: 0,
      color: dark ? const Color(0xFF0F172A) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 10,
              height: 56,
              decoration: BoxDecoration(color: tone, borderRadius: BorderRadius.circular(999)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: TextStyle(fontWeight: FontWeight.w900, color: dark ? Colors.white : Colors.black),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: tone.withOpacity(0.14),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: tone.withOpacity(0.25)),
                      ),
                      child: Text(badge, style: TextStyle(fontWeight: FontWeight.w900, color: tone)),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 10,
                  runSpacing: 6,
                  children: [
                    _pill('Lot: ${r.lotNo}', dark),
                    _pill('คงเหลือ: ${r.qtyBase.toStringAsFixed(2)} ${r.baseUnit.isEmpty ? 'ฐาน' : r.baseUnit}', dark),
                    _pill(r.daysLeft < 0 ? 'เลยมา ${r.daysLeft.abs()} วัน' : 'เหลือ ${r.daysLeft} วัน', dark),
                    _pill('เตือน ${r.warnDays} วัน', dark),
                  ],
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pill(String text, bool dark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: dark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.04),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: dark ? Colors.white.withOpacity(0.10) : Colors.black.withOpacity(0.06)),
      ),
      child: Text(
        text,
        style: TextStyle(fontWeight: FontWeight.w700, color: dark ? Colors.white70 : Colors.black87),
      ),
    );
  }
}

// =========================
// Models
// =========================

enum _ExpiryStatus { ok, near, expired }

class _DaySummary {
  int ok = 0;
  int near = 0;
  int expired = 0;

  int get total => ok + near + expired;

  void add(_ExpiryStatus s) {
    switch (s) {
      case _ExpiryStatus.ok:
        ok++;
        break;
      case _ExpiryStatus.near:
        near++;
        break;
      case _ExpiryStatus.expired:
        expired++;
        break;
    }
  }
}

class _ExpiryRow {
  final String drugName;
  final String drugCode;
  final String baseUnit;

  final String lotNo;
  final String expDate;
  final num qtyBase;

  final int warnDays;
  final int daysLeft;
  final _ExpiryStatus status;

  const _ExpiryRow({
    required this.drugName,
    required this.drugCode,
    required this.baseUnit,
    required this.lotNo,
    required this.expDate,
    required this.qtyBase,
    required this.warnDays,
    required this.daysLeft,
    required this.status,
  });

  const _ExpiryRow.empty()
      : drugName = '',
        drugCode = '',
        baseUnit = '',
        lotNo = '',
        expDate = '',
        qtyBase = 0,
        warnDays = 0,
        daysLeft = 0,
        status = _ExpiryStatus.ok;
}