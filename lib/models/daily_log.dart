class DailyLog {
  final String date;       // 'yyyy-MM-dd'
  final int adherence;     // 0–100
  final String status;     // 'fully' | 'partial' | 'none'
  final Map<String, bool> medicines; // {medicineId: taken}
  final int totalMeds;
  final int takenCount;

  const DailyLog({
    required this.date,
    required this.adherence,
    required this.status,
    required this.medicines,
    this.totalMeds = 0,
    this.takenCount = 0,
  });

  Map<String, dynamic> toMap() => {
    'date': date,
    'adherence': adherence,
    'status': status,
    'medicines': medicines,
    'totalMeds': totalMeds,
    'takenCount': takenCount,
  };

  factory DailyLog.fromMap(Map<String, dynamic> map) {
    final rawMeds = map['medicines'] as Map<String, dynamic>? ?? {};
    final meds = rawMeds.map((k, v) => MapEntry(k, v == true));
    final total  = map['totalMeds']  as int? ?? meds.length;
    final taken  = map['takenCount'] as int? ?? meds.values.where((v) => v).length;
    return DailyLog(
      date:      map['date']     ?? '',
      adherence: map['adherence'] ?? 0,
      status:    map['status']   ?? 'none',
      medicines: meds,
      totalMeds: total,
      takenCount: taken,
    );
  }
}
