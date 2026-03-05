// lib/pages/partners/suppliers_page.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase_guard.dart';

class SuppliersPage extends StatefulWidget {
  const SuppliersPage({super.key});

  @override
  State<SuppliersPage> createState() => _SuppliersPageState();
}

class _SuppliersPageState extends State<SuppliersPage> {
  SupabaseClient? _sb;

  bool _loading = true;
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

    return _items.where((s) {
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

  // ✅ เปิด editor: ใช้ dialog แบบเดียวกับที่คุณมี (ยกมาปรับให้อ่านง่าย)
  Future<void> _showEditor({Map<String, dynamic>? edit}) async {
    final sb = _sb!;
    final ownerId = _ownerId();
    final isEdit = edit != null;

    final formKey = GlobalKey<FormState>();

    final nameCtl = TextEditingController(text: (edit?['name'] ?? '').toString());
    final codeCtl = TextEditingController(text: (edit?['code'] ?? '').toString());

    final companyCtl = TextEditingController(text: (edit?['company_name'] ?? '').toString());
    final contactCtl = TextEditingController(text: (edit?['contact_name'] ?? '').toString());

    final phoneCtl = TextEditingController(text: (edit?['phone'] ?? '').toString());
    final lineCtl = TextEditingController(text: (edit?['line_id'] ?? '').toString());
    final emailCtl = TextEditingController(text: (edit?['email'] ?? '').toString());

    final addressCtl = TextEditingController(text: (edit?['address'] ?? '').toString());
    final deliveryCtl = TextEditingController(text: (edit?['delivery_area'] ?? '').toString());

    final regCtl = TextEditingController(text: (edit?['company_reg_no'] ?? '').toString());
    final licenseCtl = TextEditingController(text: (edit?['drug_license_no'] ?? '').toString());

    final noteCtl = TextEditingController(text: (edit?['note'] ?? '').toString());

    bool isDefault = (edit?['is_default'] == true);
    bool isActive = (edit?['is_active'] == null) ? true : (edit?['is_active'] == true);

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
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
                  Icon(icon, size: 18, color: cs.primary),
                  const SizedBox(width: 8),
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
                ],
              ),
              const SizedBox(height: 10),
              ...children,
            ]),
          );
        }

        Future<void> doSave(StateSetter setD) async {
          if (!(formKey.currentState?.validate() ?? false)) return;

          setD(() => saving = true);
          try {
            if (isDefault) {
              await sb.from('suppliers').update({'is_default': false}).eq('owner_id', ownerId);
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

            if (ctx.mounted) Navigator.pop(ctx, true);
          } catch (e) {
            _toast('บันทึกไม่สำเร็จ: $e');
          } finally {
            if (ctx.mounted) setD(() => saving = false);
          }
        }

        return StatefulBuilder(
          builder: (ctx, setD) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              title: Row(
                children: [
                  Icon(Icons.store_rounded, color: cs.primary),
                  const SizedBox(width: 10),
                  Text(isEdit ? 'แก้ไข Supplier' : 'เพิ่ม Supplier',
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
                  onPressed: saving ? null : () => doSave(setD),
                  child: saving
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
        _toast(isEdit ? 'บันทึกการแก้ไขแล้ว ✅' : 'เพิ่ม Supplier แล้ว ✅');
      }
    });
  }

  Widget _card(Map<String, dynamic> s) {
    final cs = Theme.of(context).colorScheme;

    final isDefault = s['is_default'] == true;
    final isActive = (s['is_active'] == null) ? true : (s['is_active'] == true);

    final name = (s['name'] ?? '-').toString();
    final code = (s['code'] ?? '').toString().trim();

    final company = (s['company_name'] ?? '').toString().trim();
    final contact = (s['contact_name'] ?? '').toString().trim();
    final phone = (s['phone'] ?? '').toString().trim();
    final lineId = (s['line_id'] ?? '').toString().trim();
    final email = (s['email'] ?? '').toString().trim();
    final address = (s['address'] ?? '').toString().trim();
    final delivery = (s['delivery_area'] ?? '').toString().trim();

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
        onTap: () => _showEditor(edit: s),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: (isDefault ? Colors.amber : cs.primary).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(
                  isDefault ? Icons.star_rounded : Icons.storefront_rounded,
                  color: isDefault ? Colors.amber.shade800 : cs.primary,
                  size: 26,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
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
                        if (isDefault)
                          _badge('DEFAULT', Colors.amber.shade800)
                        else if (code.isNotEmpty)
                          _badge(code, cs.primary),
                      ],
                    ),
                    const SizedBox(height: 8),

                    _infoRow(Icons.toggle_on_rounded, 'สถานะ', isActive ? 'เปิดใช้งาน' : 'ปิดใช้งาน'),
                    if (company.isNotEmpty) _infoRow(Icons.apartment_rounded, 'บริษัท', company),
                    if (contact.isNotEmpty) _infoRow(Icons.person_rounded, 'ผู้ติดต่อ', contact),
                    _infoRow(Icons.phone_rounded, 'โทร', _safe(phone)),
                    if (lineId.isNotEmpty) _infoRow(Icons.chat_rounded, 'Line', lineId),
                    if (email.isNotEmpty) _infoRow(Icons.email_rounded, 'Email', email),
                    if (delivery.isNotEmpty) _infoRow(Icons.local_shipping_rounded, 'จัดส่ง', delivery),
                    if (address.isNotEmpty) _infoRow(Icons.location_on_rounded, 'ที่อยู่', address, maxLines: 2),

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

  Widget _badge(String text, Color tone) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: tone.withOpacity(0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: tone.withOpacity(0.20)),
      ),
      child: Text(text, style: TextStyle(fontWeight: FontWeight.w900, color: tone, fontSize: 12)),
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
  backgroundColor: const Color.fromARGB(255, 25, 118, 210), // เขียวเข้มสวย
  foregroundColor: Colors.white,           // ไอคอน + ตัวหนังสือสีขาว
  elevation: 0,
  centerTitle: true,
  title: const Text(
    'Supplier',
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
        onPressed: () => _showEditor(),
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
                      Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: cs.primary.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Icon(Icons.store_rounded, color: cs.primary),
                          ),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text('Supplier',
                                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      TextField(
                        controller: _searchCtl,
                        decoration: _dec(
                          'ค้นหา Supplier (ชื่อ/บริษัท/ผู้ติดต่อ/โทร/Line/Email)',
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
                          child: Text('ยังไม่มีข้อมูล Supplier',
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