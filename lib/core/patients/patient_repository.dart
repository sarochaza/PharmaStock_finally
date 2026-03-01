import 'package:supabase_flutter/supabase_flutter.dart';
import 'patient_model.dart';

class PatientRepository {
  final SupabaseClient _client;

  PatientRepository(this._client);

  String get _ownerId {
    final user = _client.auth.currentUser;
    if (user == null) throw Exception('ยังไม่ได้ล็อกอิน');
    return user.id;
  }

  Future<List<Patient>> listPatients() async {
    final rows = await _client
        .from('patients')
        .select()
        .eq('owner_id', _ownerId)
        .order('full_name', ascending: true);
    
    return (rows as List).map((e) => Patient.fromJson(e)).toList();
  }

  Future<Patient> getPatient(String id) async {
    final row = await _client
        .from('patients')
        .select()
        .eq('id', id)
        .eq('owner_id', _ownerId)
        .single();
    
    return Patient.fromJson(row);
  }

  Future<Patient> createPatient(Map<String, dynamic> data) async {
    data['owner_id'] = _ownerId;
    final row = await _client.from('patients').insert(data).select().single();
    return Patient.fromJson(row);
  }

  Future<Patient> updatePatient(String id, Map<String, dynamic> data) async {
    final row = await _client
        .from('patients')
        .update(data)
        .eq('id', id)
        .eq('owner_id', _ownerId)
        .select()
        .single();
    return Patient.fromJson(row);
  }

  
  // --- ก๊อปปี้ 2 ฟังก์ชันนี้ไปวางใน PatientRepository ---

  Future<List<Map<String, dynamic>>> listStockOutReceiptsForPatientName(String patientName) async {
    final rows = await Supabase.instance.client
        .from('stock_out_receipts') // เช็คชื่อตารางใน Supabase ของคุณด้วยนะครับว่าชื่อนี้ไหม
        .select()
        .eq('patient_name', patientName)
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<List<Map<String, dynamic>>> listStockOutItemsByReceipt(String receiptId) async {
    final rows = await Supabase.instance.client
        .from('stock_out_items') // เช็คชื่อตารางใน Supabase ของคุณด้วยนะครับว่าชื่อนี้ไหม
        .select()
        .eq('receipt_id', receiptId);
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<void> deletePatient(String id) async {
    await _client.from('patients').delete().eq('id', id).eq('owner_id', _ownerId);
  }
}