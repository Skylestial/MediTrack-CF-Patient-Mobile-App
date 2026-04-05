import 'package:cloud_firestore/cloud_firestore.dart';

class AppNotification {
  final String id;
  final String type;
  final String doctorId;
  final String message;
  final DateTime timestamp;
  final bool read;
  final bool deletedByPatient;
  final bool deletedByDoctor;

  AppNotification({
    required this.id,
    required this.type,
    required this.doctorId,
    required this.message,
    required this.timestamp,
    required this.read,
    this.deletedByPatient = false,
    this.deletedByDoctor = false,
  });

  factory AppNotification.fromDoc(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return AppNotification(
      id:               doc.id,
      type:             data['type']     ?? 'alert',
      doctorId:         data['doctorId'] ?? '',
      message:          data['message']  ?? 'Your doctor sent you a message.',
      timestamp:        (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
      read:             data['read']     ?? false,
      deletedByPatient: data['deletedByPatient'] ?? false,
      deletedByDoctor:  data['deletedByDoctor']  ?? false,
    );
  }
}

class NotificationService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final String userId;

  NotificationService(this.userId);

  /// Real-time stream of notifications (excludes those deleted by patient)
  Stream<List<AppNotification>> getNotificationsStream() {
    return _db
        .collection('users')
        .doc(userId)
        .collection('notifications')
        .orderBy('timestamp', descending: true)
        .snapshots(includeMetadataChanges: true)
        .asyncMap((snapshot) async {
          // If from cache, try to get fresh data from server
          if (snapshot.metadata.isFromCache) {
            try {
              final serverSnap = await _db
                  .collection('users')
                  .doc(userId)
                  .collection('notifications')
                  .orderBy('timestamp', descending: true)
                  .get(const GetOptions(source: Source.server));
              return serverSnap.docs
                  .map(AppNotification.fromDoc)
                  .where((n) => !n.deletedByPatient) // Filter out patient-deleted
                  .toList();
            } catch (e) {
              return snapshot.docs
                  .map(AppNotification.fromDoc)
                  .where((n) => !n.deletedByPatient)
                  .toList();
            }
          }
          return snapshot.docs
              .map(AppNotification.fromDoc)
              .where((n) => !n.deletedByPatient)
              .toList();
        });
  }

  /// One-time fetch from server
  Future<List<AppNotification>> getNotificationsFromServer() async {
    final snap = await _db
        .collection('users')
        .doc(userId)
        .collection('notifications')
        .orderBy('timestamp', descending: true)
        .get(const GetOptions(source: Source.server));
    return snap.docs
        .map(AppNotification.fromDoc)
        .where((n) => !n.deletedByPatient)
        .toList();
  }

  /// Mark a single notification as read and sync to doctor's copy
  Future<void> markAsRead(String notifId) async {
    final notifDoc = await _db
        .collection('users')
        .doc(userId)
        .collection('notifications')
        .doc(notifId)
        .get();

    if (!notifDoc.exists) return;

    final data = notifDoc.data();
    final doctorId = data?['doctorId'] as String?;

    // Update patient's notification
    await _db
        .collection('users')
        .doc(userId)
        .collection('notifications')
        .doc(notifId)
        .update({'read': true});

    // Sync to doctor's sent_alerts
    if (doctorId != null && doctorId.isNotEmpty) {
      try {
        await _db
            .collection('doctors')
            .doc(doctorId)
            .collection('sent_alerts')
            .doc(notifId)
            .update({'read': true});
      } catch (e) {
        // Doctor's copy might not exist
      }
    }
  }

  /// Mark all notifications as read
  Future<void> markAllAsRead() async {
    final batch = _db.batch();
    final snap = await _db
        .collection('users')
        .doc(userId)
        .collection('notifications')
        .where('read', isEqualTo: false)
        .get();

    for (final doc in snap.docs) {
      final data = doc.data();
      // Skip if already deleted by patient
      if (data['deletedByPatient'] == true) continue;

      batch.update(doc.reference, {'read': true});

      final doctorId = data['doctorId'] as String?;
      if (doctorId != null && doctorId.isNotEmpty) {
        batch.update(
          _db.collection('doctors').doc(doctorId).collection('sent_alerts').doc(doc.id),
          {'read': true},
        );
      }
    }

    await batch.commit();
  }

  /// Delete a notification (soft delete for patient, permanent if both deleted)
  Future<void> deleteNotification(String notifId) async {
    final notifDoc = await _db
        .collection('users')
        .doc(userId)
        .collection('notifications')
        .doc(notifId)
        .get(const GetOptions(source: Source.server));

    if (!notifDoc.exists) return;

    final data = notifDoc.data();
    final doctorId = data?['doctorId'] as String?;
    final deletedByDoctor = data?['deletedByDoctor'] ?? false;

    if (deletedByDoctor) {
      // Doctor already deleted, so permanently delete from both
      await _db
          .collection('users')
          .doc(userId)
          .collection('notifications')
          .doc(notifId)
          .delete();

      if (doctorId != null && doctorId.isNotEmpty) {
        try {
          await _db
              .collection('doctors')
              .doc(doctorId)
              .collection('sent_alerts')
              .doc(notifId)
              .delete();
        } catch (e) {}
      }
    } else {
      // Soft delete - mark as deleted by patient
      await _db
          .collection('users')
          .doc(userId)
          .collection('notifications')
          .doc(notifId)
          .update({'deletedByPatient': true});

      // Sync to doctor's copy
      if (doctorId != null && doctorId.isNotEmpty) {
        try {
          await _db
              .collection('doctors')
              .doc(doctorId)
              .collection('sent_alerts')
              .doc(notifId)
              .update({'deletedByPatient': true});
        } catch (e) {}
      }
    }
  }

  /// Delete all read notifications
  Future<void> deleteAllReadNotifications() async {
    final snap = await _db
        .collection('users')
        .doc(userId)
        .collection('notifications')
        .where('read', isEqualTo: true)
        .get(const GetOptions(source: Source.server));

    if (snap.docs.isEmpty) return;

    final batch = _db.batch();

    for (final doc in snap.docs) {
      final data = doc.data();
      // Skip if already deleted by patient
      if (data['deletedByPatient'] == true) continue;

      final deletedByDoctor = data['deletedByDoctor'] ?? false;
      final doctorId = data['doctorId'] as String?;

      if (deletedByDoctor) {
        // Permanent delete
        batch.delete(doc.reference);
        if (doctorId != null && doctorId.isNotEmpty) {
          batch.delete(
            _db.collection('doctors').doc(doctorId).collection('sent_alerts').doc(doc.id),
          );
        }
      } else {
        // Soft delete
        batch.update(doc.reference, {'deletedByPatient': true});
        if (doctorId != null && doctorId.isNotEmpty) {
          batch.update(
            _db.collection('doctors').doc(doctorId).collection('sent_alerts').doc(doc.id),
            {'deletedByPatient': true},
          );
        }
      }
    }

    await batch.commit();
  }

  /// Delete all notifications (read and unread)
  Future<void> deleteAllNotifications() async {
    final snap = await _db
        .collection('users')
        .doc(userId)
        .collection('notifications')
        .get(const GetOptions(source: Source.server));

    if (snap.docs.isEmpty) return;

    final batch = _db.batch();

    for (final doc in snap.docs) {
      final data = doc.data();
      // Skip if already deleted by patient
      if (data['deletedByPatient'] == true) continue;

      final deletedByDoctor = data['deletedByDoctor'] ?? false;
      final doctorId = data['doctorId'] as String?;

      if (deletedByDoctor) {
        // Permanent delete
        batch.delete(doc.reference);
        if (doctorId != null && doctorId.isNotEmpty) {
          batch.delete(
            _db.collection('doctors').doc(doctorId).collection('sent_alerts').doc(doc.id),
          );
        }
      } else {
        // Soft delete
        batch.update(doc.reference, {'deletedByPatient': true});
        if (doctorId != null && doctorId.isNotEmpty) {
          batch.update(
            _db.collection('doctors').doc(doctorId).collection('sent_alerts').doc(doc.id),
            {'deletedByPatient': true},
          );
        }
      }
    }

    await batch.commit();
  }
}
