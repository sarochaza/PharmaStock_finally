import 'package:flutter/material.dart';
import 'patient_model.dart';

class PatientPicker extends StatelessWidget {
  final List<Patient> patients;
  final Patient? value;
  final ValueChanged<Patient?> onChanged;
  final String hintText;

  const PatientPicker({
    super.key,
    required this.patients,
    required this.value,
    required this.onChanged,
    this.hintText = 'ค้นหาผู้ป่วย (ชื่อ / บัตร / โทร)', // เอาคำว่า รหัส ออก
  });

  @override
  Widget build(BuildContext context) {
    return Autocomplete<Patient>(
      initialValue: TextEditingValue(text: value?.fullName ?? ''),
      displayStringForOption: (p) =>
          '${p.fullName}${p.nationalId == null || p.nationalId!.isEmpty ? '' : ' • ${p.nationalId}'}', // เอา patientCode ออก
      optionsBuilder: (t) {
        final q = t.text.trim().toLowerCase();
        if (q.isEmpty) return patients.take(20);
        return patients.where((p) {
          final s = [
            p.fullName,
            // ลบ p.patientCode ออกจากตรงนี้
            p.nationalId ?? '',
            p.phone ?? '',
          ].join(' ').toLowerCase();
          return s.contains(q);
        }).take(20);
      },
      onSelected: (p) => onChanged(p),
      fieldViewBuilder: (context, textCtl, focusNode, onFieldSubmitted) {
        return TextField(
          controller: textCtl,
          focusNode: focusNode,
          decoration: InputDecoration(
            labelText: 'ผู้ป่วย',
            hintText: hintText,
            prefixIcon: const Icon(Icons.person_search_rounded),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
            filled: true,
            fillColor: Colors.white,
          ),
          onChanged: (v) {
            if (v.trim().isEmpty) onChanged(null);
          },
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 6,
            borderRadius: BorderRadius.circular(12),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 320, maxWidth: 720),
              child: ListView.builder(
                padding: const EdgeInsets.all(8),
                itemCount: options.length,
                itemBuilder: (_, i) {
                  final p = options.elementAt(i);
                  return ListTile(
                    dense: true,
                    leading: CircleAvatar(
                      child: Text(p.fullName.isEmpty ? '?' : p.fullName[0]),
                    ),
                    title: Text(p.fullName), // ลบการแสดง patientCode ออก
                    subtitle: Text([
                      if (p.nationalId != null && p.nationalId!.isNotEmpty) 'บัตร: ${p.nationalId}',
                      if (p.phone != null && p.phone!.isNotEmpty) 'โทร: ${p.phone}',
                      if (p.age != null) 'อายุ: ${p.age}',
                    ].join('   ')),
                    onTap: () => onSelected(p),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}