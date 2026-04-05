class Alert {
  final String id;
  final String uid;
  final String doctorId;
  final String type; // 'consultation_request'
  final bool acknowledged;
  final DateTime timestamp;
  final String? message;

  Alert({
    required this.id,
    required this.uid,
    required this.doctorId,
    required this.type,
    required this.acknowledged,
    required this.timestamp,
    this.message,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'uid': uid,
      'doctorId': doctorId,
      'type': type,
      'acknowledged': acknowledged,
      'timestamp': timestamp.toIso8601String(),
      'message': message,
    };
  }

  factory Alert.fromMap(Map<String, dynamic> map, String id) {
    return Alert(
      id: id,
      uid: map['uid'] ?? '',
      doctorId: map['doctorId'] ?? '',
      type: map['type'] ?? 'consultation_request',
      acknowledged: map['acknowledged'] ?? false,
      timestamp: DateTime.parse(map['timestamp'] ?? DateTime.now().toIso8601String()),
      message: map['message'],
    );
  }
}
