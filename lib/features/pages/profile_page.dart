import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase_guard.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  SupabaseClient? _sb;

  bool _loading = true;
  bool _saving = false;
  bool _uploading = false;
  String? _error;

  final _formKey = GlobalKey<FormState>();

  final _shopNameCtl = TextEditingController();
  final _displayNameCtl = TextEditingController();
  final _phoneCtl = TextEditingController();

  // store url/path
  final _logoUrlCtl = TextEditingController();
  String? _logoPath; // ✅ new: keep storage path to delete/update

  Uint8List? _pickedBytes;

  static const String _bucket = 'profile-logos';

  @override
  void initState() {
    super.initState();
    _sb = Supabase.instance.client;
    _bootstrap();
  }

  @override
  void dispose() {
    _shopNameCtl.dispose();
    _displayNameCtl.dispose();
    _phoneCtl.dispose();
    _logoUrlCtl.dispose();
    super.dispose();
  }

  String _uid() {
    final u = _sb!.auth.currentUser;
    if (u == null) throw Exception('ยังไม่ได้ล็อกอิน');
    return u.id;
  }

  Future<void> _bootstrap() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await _loadProfile();
    } catch (e) {
      _error = '$e';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadProfile() async {
    final sb = _sb!;
    final uid = _uid();

    Map<String, dynamic>? row;
    try {
      row = await sb
          .from('profiles')
          .select('id, shop_name, display_name, phone, logo_url, logo_path')
          .eq('id', uid)
          .maybeSingle();
    } catch (_) {
      row = null;
    }

    _shopNameCtl.text = (row?['shop_name'] ?? '').toString();
    _displayNameCtl.text = (row?['display_name'] ?? '').toString();
    _phoneCtl.text = (row?['phone'] ?? '').toString();
    _logoUrlCtl.text = (row?['logo_url'] ?? '').toString();
    _logoPath = (row?['logo_path'] ?? '').toString().trim().isEmpty ? null : row?['logo_path']?.toString();
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

  String? _req(String? v, String msg) => (v ?? '').trim().isEmpty ? msg : null;

  ImageProvider? _logoProvider() {
    final url = _logoUrlCtl.text.trim();
    if (url.isEmpty) return null;
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.isAbsolute) return null;
    return NetworkImage(url);
  }

  // =========================
  // Upload logo to Supabase Storage
  // =========================
  Future<void> _pickAndUploadLogo() async {
    if (_uploading) return;

    try {
      final sb = _sb!;
      final uid = _uid();

      final picker = ImagePicker();
      final XFile? file = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 1200,
      );
      if (file == null) return;

      setState(() {
        _uploading = true;
        _pickedBytes = null;
      });

      final bytes = await file.readAsBytes();
      setState(() => _pickedBytes = bytes);

      // guess ext
      final name = file.name.toLowerCase();
      String ext = 'jpg';
      if (name.endsWith('.png')) ext = 'png';
      if (name.endsWith('.webp')) ext = 'webp';
      if (name.endsWith('.jpeg')) ext = 'jpg';
      if (name.endsWith('.jpg')) ext = 'jpg';

      final ts = DateTime.now().millisecondsSinceEpoch;
      final path = '$uid/logo_$ts.$ext';

      // ✅ upload
      await sb.storage.from(_bucket).uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(
              upsert: true,
              contentType: _contentType(ext),
            ),
          );

      final publicUrl = sb.storage.from(_bucket).getPublicUrl(path);

      // ✅ keep both url + path
      _logoUrlCtl.text = publicUrl;
      _logoPath = path;

      // auto save after upload
      await _saveProfile(alsoPop: false);

      if (!mounted) return;
      _toast('อัปโหลดโลโก้สำเร็จ ✅');
      setState(() {});
    } catch (e) {
      _toast('อัปโหลดไม่สำเร็จ: $e');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  String _contentType(String ext) {
    switch (ext) {
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'jpg':
      default:
        return 'image/jpeg';
    }
  }

  Future<void> _removeLogo() async {
    final sb = _sb!;
    final oldPath = _logoPath;

    try {
      // ✅ delete file in storage (if we have the path)
      if (oldPath != null && oldPath.trim().isNotEmpty) {
        await sb.storage.from(_bucket).remove([oldPath]);
      }
    } catch (_) {
      // ไม่ให้ล้มทั้ง flow ถ้าลบไม่สำเร็จ
    }

    _logoUrlCtl.clear();
    _logoPath = null;
    _pickedBytes = null;

    await _saveProfile(alsoPop: false);
    if (mounted) setState(() {});
    _toast('ลบโลโก้ออกแล้ว ✅');
  }

  // =========================
  // Save profile (upsert)
  // =========================
  Future<void> _saveProfile({required bool alsoPop}) async {
    final sb = _sb!;
    final uid = _uid();

    final payload = <String, dynamic>{
      'id': uid,
      'shop_name': _shopNameCtl.text.trim().isEmpty ? null : _shopNameCtl.text.trim(),
      'display_name': _displayNameCtl.text.trim().isEmpty ? null : _displayNameCtl.text.trim(),
      'phone': _phoneCtl.text.trim().isEmpty ? null : _phoneCtl.text.trim(),
      'logo_url': _logoUrlCtl.text.trim().isEmpty ? null : _logoUrlCtl.text.trim(),
      'logo_path': (_logoPath ?? '').trim().isEmpty ? null : _logoPath,
      'updated_at': DateTime.now().toIso8601String(),
    };

    await sb.from('profiles').upsert(payload);

    if (!mounted) return;
    if (alsoPop) Navigator.of(context).pop(true);
  }

  Future<void> _save() async {
    final ok = _formKey.currentState?.validate() ?? false;
    if (!ok) return;
    if (_saving) return;

    setState(() => _saving = true);
    try {
      await _saveProfile(alsoPop: true);
      if (mounted) _toast('บันทึกโปรไฟล์เรียบร้อย ✅');
    } catch (e) {
      _toast('บันทึกไม่สำเร็จ: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sb = _sb;
    if (sb == null) {
      return const SupabaseGuard(
        child: SizedBox.shrink(),
        message: 'หน้า Profile ต้องใช้ฐานข้อมูล\nกรุณาตั้งค่าและล็อกอินก่อน',
      );
    }

    final cs = Theme.of(context).colorScheme;
    final user = sb.auth.currentUser;

    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('โปรไฟล์'),
          backgroundColor: cs.primary,
          foregroundColor: Colors.white,
        ),
        body: Center(child: Text('เกิดข้อผิดพลาด: $_error')),
      );
    }

    final logoProvider = _logoProvider();

    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FB),
      appBar: AppBar(
        title: const Text('โปรไฟล์'),
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
                          radius: 30,
                          backgroundColor: cs.primary.withOpacity(0.12),
                          backgroundImage: logoProvider,
                          child: logoProvider == null
                              ? Icon(Icons.store_rounded, color: cs.primary, size: 30)
                              : null,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _shopNameCtl.text.trim().isEmpty ? 'ชื่อร้าน (ยังไม่ได้ตั้ง)' : _shopNameCtl.text.trim(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                user?.email ?? '',
                                style: TextStyle(color: Colors.black.withOpacity(0.6), fontWeight: FontWeight.w600),
                              ),
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
                    child: Form(
                      key: _formKey,
                      child: Column(
                        children: [
                          TextFormField(
                            controller: _shopNameCtl,
                            decoration: _dec('ชื่อร้าน *', icon: Icons.storefront_rounded),
                            validator: (v) => _req(v, 'กรุณากรอกชื่อร้าน'),
                            onChanged: (_) => setState(() {}),
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _displayNameCtl,
                            decoration: _dec('ชื่อผู้ใช้ (แสดงผล)', icon: Icons.person_rounded),
                            onChanged: (_) => setState(() {}),
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _phoneCtl,
                            decoration: _dec('เบอร์โทร', icon: Icons.phone_rounded),
                            keyboardType: TextInputType.phone,
                          ),
                          const SizedBox(height: 12),

                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: Colors.black.withOpacity(0.08)),
                              color: Colors.white,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('โลโก้ร้าน', style: TextStyle(fontWeight: FontWeight.w900)),
                                const SizedBox(height: 10),
                                Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 22,
                                      backgroundColor: cs.primary.withOpacity(0.10),
                                      backgroundImage: _pickedBytes != null
                                          ? MemoryImage(_pickedBytes!)
                                          : logoProvider,
                                      child: (_pickedBytes == null && logoProvider == null)
                                          ? Icon(Icons.image_outlined, color: cs.primary)
                                          : null,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        (_pickedBytes != null || logoProvider != null)
                                            ? 'พร้อมใช้งาน ✅'
                                            : 'ยังไม่มีโลโก้',
                                        style: TextStyle(color: Colors.black.withOpacity(0.65), fontWeight: FontWeight.w700),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    Expanded(
                                      child: OutlinedButton.icon(
                                        onPressed: _uploading ? null : _pickAndUploadLogo,
                                        icon: _uploading
                                            ? const SizedBox(
                                                width: 18,
                                                height: 18,
                                                child: CircularProgressIndicator(strokeWidth: 2),
                                              )
                                            : const Icon(Icons.upload_rounded),
                                        label: Text(_uploading ? 'กำลังอัปโหลด...' : 'เลือก & อัปโหลด'),
                                        style: OutlinedButton.styleFrom(
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                          padding: const EdgeInsets.symmetric(vertical: 12),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    if (_logoUrlCtl.text.trim().isNotEmpty || _pickedBytes != null)
                                      Expanded(
                                        child: OutlinedButton.icon(
                                          onPressed: _uploading ? null : _removeLogo,
                                          icon: const Icon(Icons.delete_outline_rounded),
                                          label: const Text('ลบโลโก้'),
                                          style: OutlinedButton.styleFrom(
                                            foregroundColor: Colors.red,
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                            padding: const EdgeInsets.symmetric(vertical: 12),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  _logoUrlCtl.text.trim().isEmpty ? 'URL: -' : 'URL: ${_logoUrlCtl.text.trim()}',
                                  style: TextStyle(color: Colors.black.withOpacity(0.55), fontSize: 12),
                                ),
                                Text(
                                  (_logoPath ?? '').trim().isEmpty ? 'PATH: -' : 'PATH: ${_logoPath!}',
                                  style: TextStyle(color: Colors.black.withOpacity(0.55), fontSize: 12),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            height: 52,
                            child: FilledButton(
                              onPressed: (_saving || _uploading) ? null : _save,
                              style: FilledButton.styleFrom(
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              ),
                              child: _saving
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                    )
                                  : const Text('บันทึกโปรไฟล์', style: TextStyle(fontWeight: FontWeight.w900)),
                            ),
                          ),
                        ],
                      ),
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