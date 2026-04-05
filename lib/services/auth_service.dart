import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user.dart' as models;

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Get current user
  User? get currentUser => _auth.currentUser;

  /// Get current user ID
  String? get currentUserId => _auth.currentUser?.uid;

  /// Auth state changes stream
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  /// Sign in with email and password (patients only)
  Future<User?> signIn(String email, String password) async {
    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      // Role check — only patients allowed
      final uid = credential.user!.uid;
      final doc = await _firestore.collection('users').doc(uid).get();

      if (!doc.exists || doc['role'] != 'patient') {
        await _auth.signOut();
        throw Exception('Only patients are allowed to use this app.');
      }

      return credential.user;
    } catch (e) {
      rethrow;
    }
  }

  /// Register new user
  Future<User?> register(String email, String password, String name, int age) async {
    try {
      // Create auth user
      final UserCredential cred = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      if (cred.user != null) {
        // Create user document in Firestore (including role + createdAt)
        await _firestore
            .collection('users')
            .doc(cred.user!.uid)
            .set({
          'uid': cred.user!.uid,
          'email': email,
          'name': name,
          'age': age,
          'diagnosis': 'Cystic Fibrosis',
          'role': 'patient',
          'createdAt': Timestamp.now(),
        });

        return cred.user;
      }
      return null;
    } catch (e) {
      rethrow;
    }
  }

  /// Sign out
  Future<void> signOut() async {
    await _auth.signOut();
  }

  /// Send password reset email
  Future<void> sendPasswordResetEmail(String email) async {
    await _auth.sendPasswordResetEmail(email: email);
  }

  /// Get user data from Firestore
  Future<models.UserModel?> getUserData(String uid) async {
    try {
      final doc = await _firestore.collection('users').doc(uid).get();
      if (doc.exists) {
        return models.UserModel.fromMap(doc.data()!);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Update or create user data
  Future<void> updateUserData(models.UserModel user) async {
    try {
      final docRef = _firestore.collection('users').doc(user.uid);
      final existing = await docRef.get();
      
      final data = user.toMap();
      // Add createdAt for new documents
      if (!existing.exists || existing.data()?['createdAt'] == null) {
        data['createdAt'] = Timestamp.now();
      }
      
      await docRef.set(data, SetOptions(merge: true));
    } catch (e) {
      rethrow;
    }
  }
}
