class Patient {
  final String id;
  final String ownerId;
  final String? nationalId;
  final String fullName;
  final DateTime? birthDate;
  final String? phone;
  final String? address;
  final String? bloodGroup;
  final List<String> chronicConditions;
  final List<String> drugAllergies;
  final String? note;
  final DateTime createdAt;
  final DateTime updatedAt;

  Patient({
    required this.id,
    required this.ownerId,
    this.nationalId,
    required this.fullName,
    this.birthDate,
    this.phone,
    this.address,
    this.bloodGroup,
    required this.chronicConditions,
    required this.drugAllergies,
    this.note,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Patient.fromJson(Map<String, dynamic> json) {
    return Patient(
      id: json['id']?.toString() ?? '',
      ownerId: json['owner_id']?.toString() ?? '',
      nationalId: json['national_id']?.toString(),
      fullName: json['full_name']?.toString() ?? '',
      birthDate: json['birth_date'] != null ? DateTime.tryParse(json['birth_date'].toString()) : null,
      phone: json['phone']?.toString(),
      address: json['address']?.toString(),
      bloodGroup: json['blood_group']?.toString(),
      chronicConditions: List<String>.from(json['chronic_conditions'] ?? []),
      drugAllergies: List<String>.from(json['drug_allergies'] ?? []),
      note: json['note']?.toString(),
      createdAt: DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now(),
      updatedAt: DateTime.tryParse(json['updated_at'].toString()) ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'owner_id': ownerId,
      'national_id': nationalId,
      'full_name': fullName,
      'birth_date': birthDate?.toIso8601String().split('T').first,
      'phone': phone,
      'address': address,
      'blood_group': bloodGroup,
      'chronic_conditions': chronicConditions,
      'drug_allergies': drugAllergies,
      'note': note,
    };
  }

  int? get age {
    if (birthDate == null) return null;
    final today = DateTime.now();
    int a = today.year - birthDate!.year;
    if (today.month < birthDate!.month || (today.month == birthDate!.month && today.day < birthDate!.day)) {
      a--;
    }
    return a;
  }
}