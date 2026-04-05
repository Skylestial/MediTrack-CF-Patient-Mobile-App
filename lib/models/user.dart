class UserModel {
  final String uid;
  final String name;
  final int age;
  final String email;
  final String diagnosis;

  UserModel({
    required this.uid,
    required this.name,
    required this.age,
    required this.email,
    this.diagnosis = 'Cystic Fibrosis',
  });

  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'name': name,
      'age': age,
      'email': email,
      'diagnosis': diagnosis,
    };
  }

  factory UserModel.fromMap(Map<String, dynamic> map) {
    return UserModel(
      uid: map['uid'] ?? '',
      name: map['name'] ?? '',
      age: map['age'] ?? 0,
      email: map['email'] ?? '',
      diagnosis: map['diagnosis'] ?? 'Cystic Fibrosis',
    );
  }
}
