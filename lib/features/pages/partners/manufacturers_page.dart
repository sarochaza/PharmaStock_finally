// lib/pages/partners/manufacturers_page.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase_guard.dart';

class ManufacturersPage extends StatefulWidget {
  const ManufacturersPage({super.key});

  @override
  State<ManufacturersPage> createState() => _ManufacturersPageState();
}

class _ManufacturersPageState extends State<ManufacturersPage> {
  SupabaseClient? _sb;

  bool _loading = true;
  bool _saving = false;
  String? _error;

  List<Map<String, dynamic>> _items = [];

  final TextEditingController _searchCtl = TextEditingController();
  String _q = '';

  @override
  void initState() {
    super.initState();
    _sb = getSupabaseClientOrNull();

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
    final u = _sb!.auth.currentUser;
    if (u == null) throw Exception('ยังไม่ได้ล็อกอิน');
    return u.id;
  }

  Future<void> _load() async {
    if (_sb == null) {
      setState(() {
        _loading = false;
        _error = 'ยังไม่ได้ตั้งค่า Supabase หรือยังไม่ได้ล็อกอิน';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final ownerId = _ownerId();
      final rows = await _sb!
          .from('manufacturers')
          .select('id, name, code, country, address, phone, fda_number, created_at')
          .eq('owner_id', ownerId)
          .order('name', ascending: true);

      _items = (rows as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    } catch (e) {
      _error = '$e';
      _items = [];
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> get _filtered {
    final q = _q;
    if (q.isEmpty) return _items;

    return _items.where((m) {
      String v(String k) => (m[k] ?? '').toString().toLowerCase();
      return v('name').contains(q) ||
          v('country').contains(q) ||
          v('phone').contains(q) ||
          v('fda_number').contains(q) ||
          v('code').contains(q) ||
          v('address').contains(q);
    }).toList();
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  InputDecoration _dec(String label, {IconData? icon, Widget? suffixIcon}) {
    return InputDecoration(
      labelText: label,
      prefixIcon: icon == null ? null : Icon(icon),
      suffixIcon: suffixIcon,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    );
  }

  String _safe(String? s) => (s ?? '').trim().isEmpty ? '-' : s!.trim();

  Future<void> _showEditor({Map<String, dynamic>? edit}) async {
    final sb = _sb!;
    final ownerId = _ownerId();
    final isEdit = edit != null;

    final formKey = GlobalKey<FormState>();
    final nameCtl = TextEditingController(text: (edit?['name'] ?? '').toString());
    final codeCtl = TextEditingController(text: (edit?['code'] ?? '').toString());
    final countryCtl =
        TextEditingController(text: (edit?['country'] ?? 'ประเทศไทย').toString());
    final addressCtl = TextEditingController(text: (edit?['address'] ?? '').toString());
    final phoneCtl = TextEditingController(text: (edit?['phone'] ?? '').toString());
    final fdaCtl = TextEditingController(text: (edit?['fda_number'] ?? '').toString());

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        bool savingLocal = false;

        return StatefulBuilder(
          builder: (ctx, setD) {
            Future<void> doSave() async {
              if (!(formKey.currentState?.validate() ?? false)) return;
              setD(() => savingLocal = true);

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

                if (mounted) Navigator.pop(ctx, true);
              } catch (e) {
                _toast('บันทึกไม่สำเร็จ: $e');
              } finally {
                if (ctx.mounted) setD(() => savingLocal = false);
              }
            }

            Widget fieldGap() => const SizedBox(height: 12);

            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              title: Row(
                children: [
                  Icon(Icons.domain_rounded, color: cs.primary),
                  const SizedBox(width: 10),
                  Text(isEdit ? 'แก้ไขผู้ผลิต' : 'เพิ่มผู้ผลิต',
                      style: const TextStyle(fontWeight: FontWeight.w900)),
                ],
              ),
              content: SizedBox(
                width: 560,
                child: SingleChildScrollView(
                  child: Form(
                    key: formKey,
                    child: Column(
                      children: [
                        TextFormField(
                          controller: nameCtl,
                          decoration: _dec('ชื่อบริษัทผู้ผลิต *', icon: Icons.business_rounded),
                          validator: (v) =>
                              (v ?? '').trim().isEmpty ? 'กรุณากรอกชื่อบริษัท' : null,
                        ),
                        fieldGap(),
                        TextFormField(
                          controller: codeCtl,
                          decoration: _dec('รหัสบริษัท (ถ้ามี)', icon: Icons.qr_code_rounded),
                        ),
                        fieldGap(),
                        TextFormField(
                          controller: countryCtl,
                          decoration: _dec('ประเทศ', icon: Icons.public_rounded),
                        ),
                        fieldGap(),
                        TextFormField(
                          controller: phoneCtl,
                          decoration: _dec('โทร', icon: Icons.phone_rounded),
                          keyboardType: TextInputType.phone,
                        ),
                        fieldGap(),
                        TextFormField(
                          controller: fdaCtl,
                          decoration: _dec('เลขทะเบียน อย.', icon: Icons.verified_rounded),
                        ),
                        fieldGap(),
                        TextFormField(
                          controller: addressCtl,
                          maxLines: 2,
                          decoration: _dec('ที่อยู่', icon: Icons.location_on_rounded),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: savingLocal ? null : () => Navigator.pop(ctx),
                  child: const Text('ยกเลิก', style: TextStyle(color: Colors.grey)),
                ),
                FilledButton(
                  onPressed: savingLocal ? null : doSave,
                  child: savingLocal
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('บันทึก'),
                ),
              ],
            );
          },
        );
      },
    ).then((ok) async {
      if (ok == true) {
        await _load();
        _toast(isEdit ? 'บันทึกการแก้ไขแล้ว ✅' : 'เพิ่มผู้ผลิตแล้ว ✅');
      }
    });
  }

  // ✅ UI Card style: อ่านง่าย เหมาะกับติดต่อ
  Widget _card(Map<String, dynamic> m) {
    final cs = Theme.of(context).colorScheme;

    final name = (m['name'] ?? '-').toString();
    final country = _safe((m['country'] ?? '').toString());
    final phone = _safe((m['phone'] ?? '').toString());
    final fda = _safe((m['fda_number'] ?? '').toString());
    final address = _safe((m['address'] ?? '').toString());
    final code = (m['code'] ?? '').toString().trim();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.black.withOpacity(0.07)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 14,
            offset: const Offset(0, 10),
          )
        ],
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: () => _showEditor(edit: m),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // leading icon
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: cs.primary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(Icons.domain_rounded, color: cs.primary, size: 26),
              ),
              const SizedBox(width: 12),

              // details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // title row
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                          ),
                        ),
                        if (code.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: cs.primary.withOpacity(0.10),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(color: cs.primary.withOpacity(0.18)),
                            ),
                            child: Text(
                              code,
                              style: TextStyle(fontWeight: FontWeight.w900, color: cs.primary, fontSize: 12),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    _infoRow(Icons.public_rounded, 'ประเทศ', country),
                    _infoRow(Icons.phone_rounded, 'โทร', phone),
                    _infoRow(Icons.verified_rounded, 'อย.', fda),
                    _infoRow(Icons.location_on_rounded, 'ที่อยู่', address, maxLines: 2),

                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Icon(Icons.edit_rounded, size: 18, color: cs.primary),
                        const SizedBox(width: 6),
                        Text(
                          'แตะเพื่อแก้ไข',
                          style: TextStyle(fontWeight: FontWeight.w900, color: cs.primary),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value, {int maxLines = 1}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: Colors.black.withOpacity(0.45)),
          const SizedBox(width: 8),
          Text('$label: ', style: TextStyle(fontWeight: FontWeight.w800, color: Colors.black.withOpacity(0.65))),
          Expanded(
            child: Text(
              value,
              maxLines: maxLines,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontWeight: FontWeight.w700, color: Colors.black.withOpacity(0.75)),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_sb == null) {
      return const SupabaseGuard(child: SizedBox.shrink(), message: '');
    }

    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FB),
     appBar: AppBar(
  backgroundColor: const Color.fromARGB(255, 25, 118, 210), // ✅ สีเขียว
  foregroundColor: Colors.white,           // ✅ ไอคอน + ตัวหนังสือสีขาว
  elevation: 0,
  centerTitle: true,
  title: const Text(
    'บริษัทผู้ผลิต',
    style: TextStyle(
      fontWeight: FontWeight.w900,
      color: Colors.white,
    ),
  ),
  actions: [
    IconButton(
      tooltip: 'รีเฟรช',
      onPressed: _load,
      icon: const Icon(Icons.refresh_rounded),
    ),
  ],
),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _saving ? null : () => _showEditor(),
        icon: const Icon(Icons.add_rounded),
        label: const Text('เพิ่ม', style: TextStyle(fontWeight: FontWeight.w900)),
        backgroundColor: cs.primary,
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Padding(padding: const EdgeInsets.all(16), child: Text('เกิดข้อผิดพลาด: $_error')))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      // header row like your screenshot
                      Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: cs.primary.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Icon(Icons.domain_rounded, color: cs.primary),
                          ),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text('บริษัทผู้ผลิต',
                                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      TextField(
                        controller: _searchCtl,
                        decoration: _dec(
                          'ค้นหาผู้ผลิต (ชื่อ/ประเทศ/โทร/อย./รหัส)',
                          icon: Icons.search_rounded,
                          suffixIcon: _q.isEmpty
                              ? null
                              : IconButton(
                                  icon: const Icon(Icons.close_rounded),
                                  onPressed: () => _searchCtl.clear(),
                                ),
                        ),
                      ),

                      const SizedBox(height: 14),

                      if (_filtered.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          child: Text('ยังไม่มีข้อมูลผู้ผลิต',
                              style: TextStyle(color: Colors.black.withOpacity(0.55), fontWeight: FontWeight.w700)),
                        )
                      else
                        ..._filtered.map(_card),
                      const SizedBox(height: 80),
                    ],
                  ),
                ),
    );
  }
}