import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'patient_repository.dart';
import 'patient_model.dart';

class AddEditPatientPage extends StatefulWidget {
  final String? patientId;
  const AddEditPatientPage({super.key, this.patientId});

  @override
  State<AddEditPatientPage> createState() => _AddEditPatientPageState();
}

class _AddEditPatientPageState extends State<AddEditPatientPage> {
  late final PatientRepository repo = PatientRepository(Supabase.instance.client);

  bool _loading = false;
  bool _saving = false;

  final _nationalIdCtl = TextEditingController();
  final _nameCtl = TextEditingController();
  final _phoneCtl = TextEditingController();
  final _addressCtl = TextEditingController();
  final _noteCtl = TextEditingController();

  DateTime? _birthDate;
  String? _bloodGroup;
  
  final _chronicCtl = TextEditingController();
  List<String> _chronicConditions = [];
  
  final _allergyCtl = TextEditingController();
  List<String> _drugAllergies = [];

  final List<String> _bloodGroups = ['A', 'B', 'AB', 'O', 'ไม่ทราบ'];

  @override
  void initState() {
    super.initState();
    if (widget.patientId != null) _loadData();
  }

  @override
  void dispose() {
    _nationalIdCtl.dispose();
    _nameCtl.dispose();
    _phoneCtl.dispose();
    _addressCtl.dispose();
    _noteCtl.dispose();
    _chronicCtl.dispose();
    _allergyCtl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final p = await repo.getPatient(widget.patientId!);
      _nationalIdCtl.text = p.nationalId ?? '';
      _nameCtl.text = p.fullName;
      _birthDate = p.birthDate;
      _phoneCtl.text = p.phone ?? '';
      _addressCtl.text = p.address ?? '';
      _bloodGroup = p.bloodGroup;
      _chronicConditions = List.from(p.chronicConditions);
      _drugAllergies = List.from(p.drugAllergies);
      _noteCtl.text = p.note ?? '';
    } catch (e) {
      _toast('โหลดข้อมูลไม่สำเร็จ: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _pickBirthDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _birthDate ?? DateTime.now(),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
    );
    if (date != null) setState(() => _birthDate = date);
  }

  int? get _calculatedAge {
    if (_birthDate == null) return null;
    final today = DateTime.now();
    int a = today.year - _birthDate!.year;
    if (today.month < _birthDate!.month || (today.month == _birthDate!.month && today.day < _birthDate!.day)) {
      a--;
    }
    return a;
  }

  void _addTag(TextEditingController ctl, List<String> list) {
    final val = ctl.text.trim();
    if (val.isNotEmpty) {
      final parts = val.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty);
      setState(() {
        for (var p in parts) {
          if (!list.contains(p)) list.add(p);
        }
        ctl.clear();
      });
    }
  }

  Future<void> _save() async {
    final name = _nameCtl.text.trim();
    if (name.isEmpty) return _toast('กรุณากรอกชื่อ - สกุล');

    setState(() => _saving = true);
    try {
      final data = {
        'national_id': _nationalIdCtl.text.trim().isEmpty ? null : _nationalIdCtl.text.trim(),
        'full_name': name,
        'birth_date': _birthDate?.toIso8601String().split('T').first,
        'phone': _phoneCtl.text.trim().isEmpty ? null : _phoneCtl.text.trim(),
        'address': _addressCtl.text.trim().isEmpty ? null : _addressCtl.text.trim(),
        'blood_group': _bloodGroup,
        'chronic_conditions': _chronicConditions,
        'drug_allergies': _drugAllergies,
        'note': _noteCtl.text.trim().isEmpty ? null : _noteCtl.text.trim(),
      };

      Patient result;
      if (widget.patientId == null) {
        result = await repo.createPatient(data);
        _toast('เพิ่มผู้ป่วยสำเร็จ');
      } else {
        result = await repo.updatePatient(widget.patientId!, data);
        _toast('อัปเดตผู้ป่วยสำเร็จ');
      }
      if (mounted) Navigator.of(context).pop(result);
    } catch (e) {
      _toast('บันทึกไม่สำเร็จ: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FB),
      appBar: AppBar(
        title: Text(widget.patientId == null ? 'เพิ่มผู้ป่วย' : 'แก้ไขผู้ป่วย'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 800),
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('ข้อมูลผู้ป่วย', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 16),
                            
                            TextField(
                              controller: _nationalIdCtl,
                              decoration: _inputDecor('เลขบัตรประชาชน', Icons.credit_card),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _nameCtl,
                              decoration: _inputDecor('ชื่อ - สกุล', Icons.person),
                            ),
                            const SizedBox(height: 12),
                            
                            InkWell(
                              onTap: _pickBirthDate,
                              child: InputDecorator(
                                decoration: _inputDecor('วันเดือนปีเกิด', Icons.cake),
                                child: Text(_birthDate == null 
                                  ? 'เลือกวันเกิด' 
                                  : '${_birthDate!.day}/${_birthDate!.month}/${_birthDate!.year}'),
                              ),
                            ),
                            const SizedBox(height: 12),
                            
                            InputDecorator(
                              decoration: _inputDecor('อายุ (คำนวณจากวันเกิด)', Icons.calculate),
                              child: Text(_calculatedAge?.toString() ?? '-'),
                            ),
                            const SizedBox(height: 12),

                            DropdownButtonFormField<String>(
                              value: _bloodGroup,
                              decoration: _inputDecor('กรุ๊ปเลือด', Icons.bloodtype),
                              items: _bloodGroups.map((b) => DropdownMenuItem(value: b, child: Text(b))).toList(),
                              onChanged: (v) => setState(() => _bloodGroup = v),
                            ),
                            const SizedBox(height: 12),

                            TextField(
                              controller: _phoneCtl,
                              decoration: _inputDecor('เบอร์โทรศัพท์', Icons.phone),
                            ),
                            const SizedBox(height: 12),

                            TextField(
                              controller: _addressCtl,
                              maxLines: 2,
                              decoration: _inputDecor('ที่อยู่', Icons.home),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    
                    // โรคประจำตัว
                    Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('โรคประจำตัว (พิมพ์แล้วกดเพิ่ม / คั่นด้วย , ได้)', style: TextStyle(fontWeight: FontWeight.bold)),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: _chronicCtl,
                                    decoration: _inputDecor('เช่น เบาหวาน, ความดัน', null),
                                    onSubmitted: (_) => _addTag(_chronicCtl, _chronicConditions),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                OutlinedButton.icon(
                                  onPressed: () => _addTag(_chronicCtl, _chronicConditions),
                                  icon: const Icon(Icons.add),
                                  label: const Text('เพิ่ม'),
                                )
                              ],
                            ),
                            if (_chronicConditions.isNotEmpty) ...[
                              const SizedBox(height: 12),
                              Wrap(
                                spacing: 8,
                                children: _chronicConditions.map((c) => Chip(
                                  label: Text(c),
                                  onDeleted: () => setState(() => _chronicConditions.remove(c)),
                                )).toList(),
                              )
                            ]
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // แพ้ยา
                    Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('ประวัติการแพ้ยา', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: _allergyCtl,
                                    decoration: _inputDecor('เช่น Penicillin, Amoxicillin', null),
                                    onSubmitted: (_) => _addTag(_allergyCtl, _drugAllergies),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                OutlinedButton.icon(
                                  onPressed: () => _addTag(_allergyCtl, _drugAllergies),
                                  icon: const Icon(Icons.add),
                                  label: const Text('เพิ่ม'),
                                )
                              ],
                            ),
                            if (_drugAllergies.isNotEmpty) ...[
                              const SizedBox(height: 12),
                              Wrap(
                                spacing: 8,
                                children: _drugAllergies.map((a) => Chip(
                                  backgroundColor: Colors.red.shade50,
                                  label: Text(a, style: const TextStyle(color: Colors.red)),
                                  onDeleted: () => setState(() => _drugAllergies.remove(a)),
                                )).toList(),
                              )
                            ]
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    SizedBox(
                      height: 56,
                      child: ElevatedButton(
                        onPressed: _saving ? null : _save,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Theme.of(context).colorScheme.primary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        child: _saving 
                          ? const CircularProgressIndicator(color: Colors.white) 
                          : const Text('บันทึกข้อมูล', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
    );
  }

  InputDecoration _inputDecor(String label, IconData? icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: icon != null ? Icon(icon) : null,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      filled: true,
      fillColor: Colors.white,
    );
  }
}