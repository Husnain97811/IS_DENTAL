class MedicineItem {
  const MedicineItem({
    required this.medicine,
    this.dosage = '',
    this.frequency = '',
    this.duration = '',
    this.instructions = '',
  });
  final String medicine, dosage, frequency, duration, instructions;

  MedicineItem copyWith({
    String? medicine,
    String? dosage,
    String? frequency,
    String? duration,
    String? instructions,
  }) => MedicineItem(
    medicine: medicine ?? this.medicine,
    dosage: dosage ?? this.dosage,
    frequency: frequency ?? this.frequency,
    duration: duration ?? this.duration,
    instructions: instructions ?? this.instructions,
  );

  Map<String, dynamic> toJson() => {
    'medicine': medicine,
    'dosage': dosage,
    'frequency': frequency,
    'duration': duration,
    'instructions': instructions,
  };
  factory MedicineItem.fromJson(Map<String, dynamic> j) => MedicineItem(
    medicine: j['medicine'] ?? '',
    dosage: j['dosage'] ?? '',
    frequency: j['frequency'] ?? '',
    duration: j['duration'] ?? '',
    instructions: j['instructions'] ?? '',
  );
}

class CareLine {
  const CareLine({this.urdu = '', this.english = ''});
  final String urdu, english;
  bool get isEmpty => urdu.trim().isEmpty && english.trim().isEmpty;

  Map<String, dynamic> toJson() => {'urdu': urdu, 'english': english};
  factory CareLine.fromJson(Map<String, dynamic> j) =>
      CareLine(urdu: j['urdu'] ?? '', english: j['english'] ?? '');
}

class Prescription {
  const Prescription({
    required this.id,
    required this.uuid,
    required this.rxNo,
    required this.patientId,
    required this.patientUuid,
    this.appointmentId,
    this.appointmentLabel = '',
    this.doctorName = '',
    this.advice = '',
    required this.issuedAt,
    this.items = const [],
    this.care = const [],
  });

  final int id;
  final String uuid, rxNo, patientUuid;
  final int patientId;
  final int? appointmentId;
  final String appointmentLabel, doctorName, advice;
  final DateTime issuedAt;
  final List<MedicineItem> items;
  final List<CareLine> care;

  String get summary => items.isEmpty
      ? 'No medicines'
      : items.map((e) => e.medicine).take(3).join(', ') +
            (items.length > 3 ? ' +${items.length - 3}' : '');
}

class Medicine {
  const Medicine({
    required this.id,
    required this.uuid,
    required this.name,
    this.form = '',
    this.defaultDosage = '',
    this.defaultFrequency = '',
    this.category = '',
  });
  final int id;
  final String uuid, name, form, defaultDosage, defaultFrequency, category;
}

class PrecautionSet {
  const PrecautionSet({
    required this.id,
    required this.uuid,
    required this.name,
    this.lines = const [],
  });
  final int id;
  final String uuid, name;
  final List<CareLine> lines;
}
