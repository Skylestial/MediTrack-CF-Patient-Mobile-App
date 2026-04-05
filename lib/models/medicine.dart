class Medicine {
  final String id;
  final String name;
  final String dosage;
  final List<String> times; // Format: ["08:00", "14:00", "20:00"]

  Medicine({
    required this.id,
    required this.name,
    required this.dosage,
    required this.times,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'dosage': dosage,
      'times': times,
    };
  }

  factory Medicine.fromMap(Map<String, dynamic> map, String id) {
    return Medicine(
      id: id,
      name: map['name'] ?? '',
      dosage: map['dosage'] ?? '',
      times: List<String>.from(map['times'] ?? []),
    );
  }

  Medicine copyWith({
    String? id,
    String? name,
    String? dosage,
    List<String>? times,
  }) {
    return Medicine(
      id: id ?? this.id,
      name: name ?? this.name,
      dosage: dosage ?? this.dosage,
      times: times ?? this.times,
    );
  }
}
