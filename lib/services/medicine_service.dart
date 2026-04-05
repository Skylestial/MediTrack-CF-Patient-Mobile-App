import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../models/medicine.dart';
import '../models/daily_log.dart';
import 'alarm_service.dart';
import 'risk_service.dart';

class MedicineService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final String userId;

  MedicineService(this.userId);

  // ─── Path helper ────────────────────────────────────────────────────────
  /// users/{uid}/daily_logs/{date}  ← ONE document per day
  DocumentReference _logDoc(String date) => _firestore
      .collection('users')
      .doc(userId)
      .collection('daily_logs')
      .doc(date);

  CollectionReference _logsCol() => _firestore
      .collection('users')
      .doc(userId)
      .collection('daily_logs');

  // ─── Medicines ───────────────────────────────────────────────────────────

  Stream<List<Medicine>> getMedicinesStream() {
    return _firestore
        .collection('users')
        .doc(userId)
        .collection('medicines')
        .snapshots()
        .map((s) => s.docs.map((d) => Medicine.fromMap(d.data(), d.id)).toList());
  }

  Future<List<Medicine>> getMedicines() async {
    final s = await _firestore
        .collection('users')
        .doc(userId)
        .collection('medicines')
        .get();
    return s.docs.map((d) => Medicine.fromMap(d.data(), d.id)).toList();
  }

  Future<void> addMedicine(Medicine medicine) async {
    await _firestore
        .collection('users')
        .doc(userId)
        .collection('medicines')
        .doc(medicine.id)
        .set(medicine.toMap());
    final medicines = await getMedicines();
    await AlarmService.rescheduleAllAlarms(medicines);
  }

  Future<void> updateMedicine(Medicine medicine) async {
    await _firestore
        .collection('users')
        .doc(userId)
        .collection('medicines')
        .doc(medicine.id)
        .update(medicine.toMap());
    final medicines = await getMedicines();
    await AlarmService.rescheduleAllAlarms(medicines);
  }

  Future<void> deleteMedicine(String medicineId) async {
    final doc = await _firestore
        .collection('users')
        .doc(userId)
        .collection('medicines')
        .doc(medicineId)
        .get();
    if (doc.exists) {
      await AlarmService.cancelAlarmsForMedicine(
          Medicine.fromMap(doc.data()!, doc.id));
    }
    await _firestore
        .collection('users')
        .doc(userId)
        .collection('medicines')
        .doc(medicineId)
        .delete();
    final medicines = await getMedicines();
    await AlarmService.rescheduleAllAlarms(medicines);
  }

  // ─── Daily Logs ──────────────────────────────────────────────────────────

  /// Mark a medicine as taken or missed for [date].
  /// Uses SetOptions(merge: true) — always updates the SAME daily document.
  /// Recomputes totalMeds, takenCount, and adherence after each toggle.
  Future<void> markMedicineTaken(
      String date, String medicineId, bool taken,
      {int totalMedicineCount = 0}) async {
    final docRef = _logDoc(date);

    // 1 — Read current state (to preserve other medicines in the map)
    final snap = await docRef.get();
    Map<String, bool> medicines = {};
    if (snap.exists) {
      final raw =
          (snap.data() as Map<String, dynamic>)['medicines'] as Map? ?? {};
      medicines = raw.map((k, v) => MapEntry(k.toString(), v == true));
    }

    // 2 — Toggle this medicine
    medicines[medicineId] = taken;

    // 3 — Recompute counters
    // Use the larger of: how many medicines are in the log vs total count
    // This prevents 1/1=100% when other medicines haven't been logged yet
    final totalMeds = totalMedicineCount > 0
        ? totalMedicineCount
        : medicines.length;
    final takenCount = medicines.values.where((t) => t).length;
    final adherence = RiskService.calculateAdherence(takenCount, totalMeds);
    final status = RiskService.getStatus(adherence);

    // 4 — Write — merge:true preserves any other top-level fields
    await docRef.set({
      'date':       date,
      'medicines':  medicines,
      'totalMeds':  totalMeds,
      'takenCount': takenCount,
      'adherence':  adherence,
      'status':     status,
    }, SetOptions(merge: true));

    // 5 — Keep user doc's lastAdherence in sync for doctor dashboard
    await _firestore
        .collection('users')
        .doc(userId)
        .set({'lastAdherence': adherence}, SetOptions(merge: true));
  }

  /// Get the daily log for a specific date (one-time fetch)
  Future<DailyLog?> getDailyLog(String date) async {
    final doc = await _logDoc(date).get();
    if (!doc.exists) return null;
    return DailyLog.fromMap(doc.data() as Map<String, dynamic>);
  }

  /// Stream of daily logs for a month — used by the calendar
  Stream<List<DailyLog>> getDailyLogsStream(
      String startDate, String endDate) {
    return _logsCol()
        .where('date', isGreaterThanOrEqualTo: startDate)
        .where('date', isLessThanOrEqualTo: endDate)
        .snapshots()
        .map((s) => s.docs
            .map((d) => DailyLog.fromMap(d.data() as Map<String, dynamic>))
            .toList());
  }

  /// Fill in missing days with 0% adherence entries.
  /// Called on app startup to ensure no gaps in data.
  /// Only fills days from account creation (or first log) until yesterday.
  Future<void> fillMissingDays() async {
    final medicines = await getMedicines();
    if (medicines.isEmpty) return; // No medicines = nothing to log

    // Get user creation date or find earliest log
    final userDoc = await _firestore.collection('users').doc(userId).get();
    final createdAt = userDoc.data()?['createdAt'] as Timestamp?;
    
    DateTime startDate;
    if (createdAt != null) {
      startDate = createdAt.toDate();
    } else {
      // Fallback: find earliest log date
      final firstLog = await _logsCol()
          .orderBy('date', descending: false)
          .limit(1)
          .get();
      if (firstLog.docs.isEmpty) {
        // No logs yet, nothing to fill
        return;
      }
      final firstDate = firstLog.docs.first['date'] as String?;
      if (firstDate == null) return;
      startDate = DateFormat('yyyy-MM-dd').parse(firstDate);
    }

    // End at yesterday (don't fill today - user might still log)
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    final endDate = DateTime(yesterday.year, yesterday.month, yesterday.day);
    
    // Start from the day after account creation
    startDate = DateTime(startDate.year, startDate.month, startDate.day);
    if (startDate.isAfter(endDate)) return;

    // Get all existing logs in date range
    final startStr = DateFormat('yyyy-MM-dd').format(startDate);
    final endStr = DateFormat('yyyy-MM-dd').format(endDate);
    
    final existingLogs = await _logsCol()
        .where('date', isGreaterThanOrEqualTo: startStr)
        .where('date', isLessThanOrEqualTo: endStr)
        .get();
    
    final existingDates = existingLogs.docs
        .map((d) => d['date'] as String?)
        .whereType<String>()
        .toSet();

    // Create empty logs for missing dates
    final batch = _firestore.batch();
    int batchCount = 0;
    
    DateTime current = startDate;
    while (!current.isAfter(endDate)) {
      final dateStr = DateFormat('yyyy-MM-dd').format(current);
      
      if (!existingDates.contains(dateStr)) {
        // Create a 0% adherence log for this missing day
        final docRef = _logDoc(dateStr);
        final emptyMeds = <String, bool>{};
        for (final med in medicines) {
          emptyMeds[med.id] = false;
        }
        
        batch.set(docRef, {
          'date': dateStr,
          'medicines': emptyMeds,
          'totalMeds': medicines.length,
          'takenCount': 0,
          'adherence': 0,
          'status': 'none',
        });
        batchCount++;
        
        // Firestore batch limit is 500
        if (batchCount >= 450) {
          await batch.commit();
          batchCount = 0;
        }
      }
      current = current.add(const Duration(days: 1));
    }
    
    if (batchCount > 0) {
      await batch.commit();
    }
  }
}
