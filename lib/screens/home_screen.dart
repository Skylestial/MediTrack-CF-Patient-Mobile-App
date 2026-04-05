import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:intl/intl.dart';
import '../services/medicine_service.dart';
import '../services/notification_service.dart';
import '../services/alarm_service.dart';
import '../utils/error_utils.dart';
import '../models/medicine.dart';
import '../models/daily_log.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late MedicineService _medicineService;

  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;

  Map<String, DailyLog> _dailyLogs = {};
  List<Medicine> _medicines = [];
  DailyLog? _todayLog;
  bool _isLoggingMedicine = false;
  late NotificationService _notifService;
  List<AppNotification> _notifications = [];
  Timer? _refreshTimer;

  final String _todayDate = DateFormat('yyyy-MM-dd').format(DateTime.now());

  @override
  void initState() {
    super.initState();
    // Wait for auth state to be ready (avoids null userId on cold start)
    FirebaseAuth.instance.authStateChanges().first.then((user) {
      if (user != null && mounted) {
        _medicineService = MedicineService(user.uid);
        _notifService = NotificationService(user.uid);
        _loadData();
        _loadNotificationsFromServer(); // Initial fetch from server
        _notifService.getNotificationsStream().listen((notifs) {
          if (mounted) setState(() => _notifications = notifs);
        });
        _checkLowAdherence();
        // Fill in any missing days with 0% adherence
        _medicineService.fillMissingDays();
        // Initialize alarms and request permissions
        _initializeAlarms();
      }
    });
  }

  Future<void> _initializeAlarms() async {
    // Schedule daily reminder at 9 PM
    await AlarmService.scheduleDailyLogReminder();
    
    // Check if notifications are enabled and show prompt if not
    final enabled = await AlarmService.areNotificationsEnabled();
    if (!enabled && mounted) {
      _showNotificationPermissionPrompt();
    }
  }

  void _showNotificationPermissionPrompt() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.alarm, color: Colors.orange),
            SizedBox(width: 8),
            Text('Enable Alarms'),
          ],
        ),
        content: const Text(
          'MediTrack needs special permissions to remind you about medicines even when your phone is locked.\n\n'
          'Please:\n'
          '1. Allow notifications\n'
          '2. Allow alarms & reminders\n'
          '3. Disable battery optimization for MediTrack\n\n'
          'This ensures your medicine reminders work reliably.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Later'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              // Request permissions again
              await AlarmService.initialize();
            },
            child: const Text('Enable'),
          ),
        ],
      ),
    );
  }

  /// Initial fetch from server to bypass stale cache
  Future<void> _loadNotificationsFromServer() async {
    try {
      final notifs = await _notifService.getNotificationsFromServer();
      if (mounted) setState(() => _notifications = notifs);
    } catch (_) {
      // Fall through to stream if server fetch fails
    }
  }

  Future<void> _checkLowAdherence() async {
    // Check adherence for the last 7 days (including missed days as 0%)
    // while excluding days before the patient account existed.
    final nowRaw = DateTime.now();
    final now = DateTime(nowRaw.year, nowRaw.month, nowRaw.day);
    final windowStart = now.subtract(const Duration(days: 6));

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final db = FirebaseFirestore.instance;
      final userDoc = await db.collection('users').doc(user.uid).get();
      final createdAt = userDoc.data()?['createdAt'] as Timestamp?;
      final patientName = (userDoc.data()?['name'] as String?) ?? 'Patient';

      DateTime accountCreatedDate;
      if (createdAt != null) {
        final d = createdAt.toDate();
        accountCreatedDate = DateTime(d.year, d.month, d.day);
      } else {
        accountCreatedDate = windowStart;
      }

      final effectiveStart = accountCreatedDate.isAfter(windowStart)
          ? accountCreatedDate
          : windowStart;

      final startDate = DateFormat('yyyy-MM-dd').format(effectiveStart);
      final endDate = DateFormat('yyyy-MM-dd').format(now);

      // Get logs and medicines
      final logs = await _medicineService
          .getDailyLogsStream(startDate, endDate)
          .first;
      final medicines = await _medicineService.getMedicines();

      // If no medicines assigned, nothing to check
      if (medicines.isEmpty) return;

      // Build a map of date -> adherence for quick lookup
      final logsByDate = <String, DailyLog>{};
      for (final log in logs) {
        logsByDate[log.date] = log;
      }

      int totalTaken = 0;
      int totalMeds = 0;

      // Go through each day from effective start through today.
      final totalDays = now.difference(effectiveStart).inDays + 1;
      for (int i = 0; i < totalDays; i++) {
        final date = effectiveStart.add(Duration(days: i));
        final dateStr = DateFormat('yyyy-MM-dd').format(date);
        
        if (logsByDate.containsKey(dateStr)) {
          // Day has a log
          totalTaken += logsByDate[dateStr]!.takenCount;
          totalMeds += logsByDate[dateStr]!.totalMeds;
        } else {
          // Missed day - count as 0 taken, but add expected medicines
          totalMeds += medicines.length;
        }
      }

      if (totalMeds > 0) {
        final adherencePercent = (totalTaken / totalMeds * 100).toInt();

        // If adherence is below 50%, create a warning notification
        if (adherencePercent < 50 && mounted) {
          _showLowAdherenceWarning(adherencePercent);
          // Also notify doctors
          await _notifyDoctorsLowAdherence(adherencePercent, patientName: patientName);
        }
      }
    } catch (e) {
      // Silently ignore errors in background check
      debugPrint('Low adherence check error: $e');
    }
  }

  /// Notify doctors about low adherence by adding a system alert
  Future<void> _notifyDoctorsLowAdherence(int adherencePercent, {required String patientName}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final db = FirebaseFirestore.instance;

      // Check if we've already sent an alert today to avoid spam
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final existingAlert = await db
          .collection('low_adherence_alerts')
          .where('patientUid', isEqualTo: user.uid)
          .where('date', isEqualTo: today)
          .get();

      if (existingAlert.docs.isNotEmpty) {
        // Already sent alert today
        debugPrint('Low adherence alert already sent today');
        return;
      }

      // Create a low adherence alert for all doctors to see
      await db.collection('low_adherence_alerts').add({
        'patientUid': user.uid,
        'patientName': patientName,
        'adherencePercent': adherencePercent,
        'message': 'Low adherence warning: $patientName\'s 7-day adherence is only $adherencePercent%.',
        'date': today,
        'timestamp': FieldValue.serverTimestamp(),
        'read': false,
      });
      debugPrint('Low adherence alert created successfully');
    } catch (e) {
      debugPrint('Error creating low adherence alert: $e');
    }
  }

  void _showLowAdherenceWarning(int adherencePercent) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: Colors.red.shade700,
        duration: const Duration(seconds: 5),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        content: Row(
          children: [
            const Icon(Icons.warning_rounded, color: Colors.white, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Low Adherence Warning',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Your adherence in the last 7 days is less than 50%. Please maintain your medication schedule.',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _loadData() async {
    // Live stream of medicines
    _medicineService.getMedicinesStream().listen((medicines) {
      if (mounted) {
        setState(() => _medicines = medicines);
        _scheduleNextRefresh(); // Set timer to refresh at next medicine time
      }
    });

    // Load calendar logs for the current month
    _reloadMonthLogs();

    // Load today's log
    final todayLog = await _medicineService.getDailyLog(_todayDate);
    if (mounted) setState(() => _todayLog = todayLog);
  }

  /// Schedule a timer to refresh UI when the next medicine time is reached
  void _scheduleNextRefresh() {
    _refreshTimer?.cancel();
    
    if (_medicines.isEmpty) return;
    
    final now = DateTime.now();
    DateTime? nextTime;
    
    // Find the next upcoming medicine time today
    for (final medicine in _medicines) {
      for (final timeStr in medicine.times) {
        try {
          final parts = timeStr.trim().split(':');
          if (parts.length < 2) continue;
          
          final hourStr = parts[0].trim();
          final minPart = parts[1].trim();
          final minStr = minPart.length >= 2 ? minPart.substring(0, 2) : minPart;
          
          final hour = (int.tryParse(hourStr) ?? 0).clamp(0, 23);
          final minute = (int.tryParse(minStr) ?? 0).clamp(0, 59);
          final scheduledTime = DateTime(now.year, now.month, now.day, hour, minute);
          
          // Only consider future times
          if (scheduledTime.isAfter(now)) {
            if (nextTime == null || scheduledTime.isBefore(nextTime)) {
              nextTime = scheduledTime;
            }
          }
        } catch (e) {
          continue;
        }
      }
    }
    
    // If there's an upcoming time today, schedule refresh
    if (nextTime != null) {
      final duration = nextTime.difference(now) + const Duration(seconds: 1);
      _refreshTimer = Timer(duration, () {
        if (mounted) {
          setState(() {}); // Trigger rebuild to update canMark states
          _scheduleNextRefresh(); // Schedule next refresh
        }
      });
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  void _reloadMonthLogs() {
    final startDate = DateTime(_focusedDay.year, _focusedDay.month, 1);
    final endDate = DateTime(_focusedDay.year, _focusedDay.month + 1, 0);

    _medicineService
        .getDailyLogsStream(
      DateFormat('yyyy-MM-dd').format(startDate),
      DateFormat('yyyy-MM-dd').format(endDate),
    )
        .listen((logs) {
      if (mounted) {
        setState(() {
          _dailyLogs = {for (var log in logs) log.date: log};
          // Also keep today's log in sync
          final today = _dailyLogs[_todayDate];
          if (today != null) _todayLog = today;
        });
      }
    });
  }

  bool _canMarkMedicine(Medicine medicine) {
    // Only allow marking medicine AFTER any of its scheduled times have passed
    // If no valid times, default to not allowing marking
    if (medicine.times.isEmpty) return false;

    final now = DateTime.now();
    
    for (final timeStr in medicine.times) {
      try {
        // Parse time string (supports "HH:mm" or "H:mm")
        final parts = timeStr.trim().split(':');
        if (parts.length < 2) continue;

        final hourStr = parts[0].trim();
        final minPart = parts[1].trim();
        final minStr = minPart.length >= 2 ? minPart.substring(0, 2) : minPart;
        
        final hour = (int.tryParse(hourStr) ?? 0).clamp(0, 23);
        final minute = (int.tryParse(minStr) ?? 0).clamp(0, 59); // Handle "08:00 AM" case
        
        // Create scheduled time for TODAY
        final scheduledTime = DateTime(now.year, now.month, now.day, hour, minute);

        // If current time >= scheduled time, can mark this medicine
        if (!now.isBefore(scheduledTime)) {
          return true; // At least one scheduled time has been reached or passed
        }
      } catch (e) {
        // If parsing fails, continue to next time
        continue;
      }
    }
    
    // No scheduled time has passed yet - medicine is LOCKED
    return false;
  }

  Future<void> _toggleMedicineTaken(Medicine medicine, bool taken) async {
    if (_isLoggingMedicine) return;

    // Prevent marking if time hasn't been reached
    if (!_canMarkMedicine(medicine)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You can only mark this medicine after its scheduled time'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    setState(() => _isLoggingMedicine = true);
    try {
      await _medicineService.markMedicineTaken(
          _todayDate, medicine.id, taken,
          totalMedicineCount: _medicines.length);
      final updated = await _medicineService.getDailyLog(_todayDate);
      if (mounted) setState(() => _todayLog = updated);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(ErrorUtils.getFriendlyMessage(e)),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoggingMedicine = false);
    }
  }

  Color _getDayColor(DateTime day) {
    final dateStr = DateFormat('yyyy-MM-dd').format(day);
    final log = _dailyLogs[dateStr];
    if (log == null) return Colors.grey.shade300;
    final adherence = log.adherence;
    if (adherence == 100) return Colors.green;
    if (adherence > 0) return Colors.amber;
    return Colors.red;
  }

  void _onDaySelected(DateTime selectedDay, DateTime focusedDay) {
    setState(() {
      _selectedDay = selectedDay;
      _focusedDay = focusedDay;
    });
    if (_medicines.isEmpty) return;

    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final tapped = DateFormat('yyyy-MM-dd').format(selectedDay);
    if (tapped == today) {
      // Today — allow marking taken/not-taken
      _showEditableDialog(selectedDay);
    } else if (selectedDay.isBefore(DateTime.now())) {
      // Past day — read-only
      _showReadOnlyDialog(selectedDay);
    }
    // Future days: do nothing
  }

  /// Read-only dialog for past days
  void _showReadOnlyDialog(DateTime day) {
    final dateStr = DateFormat('yyyy-MM-dd').format(day);
    final log = _dailyLogs[dateStr];
    final medicineStatus = log?.medicines ?? {};

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${DateFormat('MMM d, yyyy').format(day)}',
            style: const TextStyle(fontWeight: FontWeight.bold)),
        content: SizedBox(
          width: double.maxFinite,
          child: log == null
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text('No data recorded for this day.',
                      textAlign: TextAlign.center),
                )
              : ListView(
                  shrinkWrap: true,
                  children: _medicines.map((medicine) {
                    final isTaken = medicineStatus[medicine.id] ?? false;
                    return ListTile(
                      leading: Icon(
                        isTaken ? Icons.check_circle_rounded : Icons.cancel_rounded,
                        color: isTaken ? Colors.green : Colors.red.shade400,
                      ),
                      title: Text(
                        medicine.name,
                        style: TextStyle(
                          decoration: isTaken ? TextDecoration.lineThrough : null,
                          color: isTaken ? Colors.grey : null,
                        ),
                      ),
                      subtitle: Text('${medicine.dosage} · ${medicine.times.join(', ')}'),
                      trailing: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: isTaken ? Colors.green.shade50 : Colors.red.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: isTaken ? Colors.green : Colors.red.shade300),
                        ),
                        child: Text(
                          isTaken ? 'Taken' : 'Missed',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: isTaken ? Colors.green.shade800 : Colors.red.shade800,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  /// Editable checklist for today only
  void _showEditableDialog(DateTime day) {
    final dateStr = DateFormat('yyyy-MM-dd').format(day);
    final log = _dailyLogs[dateStr];
    final medicineStatus = Map<String, bool>.from(log?.medicines ?? {});

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Today — ${DateFormat('MMM d').format(day)}'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _medicines.length,
              itemBuilder: (context, index) {
                final medicine = _medicines[index];
                final isTaken = medicineStatus[medicine.id] ?? false;
                final canMark = _canMarkMedicine(medicine);
                
                return CheckboxListTile(
                  title: Text(
                    medicine.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: canMark ? null : Colors.grey,
                    ),
                  ),
                  subtitle: Text(
                    '${medicine.dosage} · ${medicine.times.join(', ')}${!canMark ? ' (locked)' : ''}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: canMark ? null : Colors.grey,
                    ),
                  ),
                  value: isTaken,
                  onChanged: canMark
                      ? (value) async {
                          await _medicineService.markMedicineTaken(
                            dateStr,
                            medicine.id,
                            value ?? false,
                          );
                          setDialogState(() => medicineStatus[medicine.id] = value ?? false);
                        }
                      : null,
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final medicineStatus = _todayLog?.medicines ?? {};
    final taken = medicineStatus.values.where((t) => t).length;
    final total = _medicines.length;
    final adherence = total > 0 ? (taken / total * 100).round() : 0;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Calendar ──────────────────────────────────────────────────
          TableCalendar(
            firstDay: DateTime.utc(2020, 1, 1),
            lastDay: DateTime.utc(2030, 12, 31),
            focusedDay: _focusedDay,
            selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
            onDaySelected: _onDaySelected,
            onPageChanged: (focusedDay) {
              setState(() => _focusedDay = focusedDay);
              _reloadMonthLogs();
            },
            headerStyle: const HeaderStyle(
              formatButtonVisible: false,
              titleCentered: true,
            ),
            calendarStyle: CalendarStyle(
              outsideDaysVisible: false,
              defaultTextStyle: const TextStyle(color: Colors.black),
              weekendTextStyle: const TextStyle(color: Colors.black),
              todayTextStyle: const TextStyle(
                  color: Colors.black, fontWeight: FontWeight.bold),
              selectedTextStyle: const TextStyle(
                  color: Colors.black, fontWeight: FontWeight.bold),
              todayDecoration: BoxDecoration(
                color: Colors.blue.shade400,
                shape: BoxShape.circle,
              ),
              selectedDecoration: const BoxDecoration(
                color: Colors.blue,
                shape: BoxShape.circle,
              ),
            ),
            daysOfWeekStyle: DaysOfWeekStyle(
              weekdayStyle: TextStyle(
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.white70
                    : Colors.black87,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
              weekendStyle: TextStyle(
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.white54
                    : Colors.black54,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
            calendarBuilders: CalendarBuilders(
              defaultBuilder: (ctx, day, _) {
                final bg = _getDayColor(day);
                return Container(
                  margin: const EdgeInsets.all(4),
                  decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
                  child: Center(
                    child: Text('${day.day}',
                        style: const TextStyle(color: Colors.black)),
                  ),
                );
              },
              todayBuilder: (ctx, day, _) {
                final bg = _getDayColor(day);
                return Container(
                  margin: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: bg,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.blue.shade700, width: 2),
                  ),
                  child: Center(
                    child: Text('${day.day}',
                        style: const TextStyle(
                            color: Colors.black, fontWeight: FontWeight.bold)),
                  ),
                );
              },
              selectedBuilder: (ctx, day, _) {
                final bg = _getDayColor(day);
                return Container(
                  margin: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: bg,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.blue.shade300, width: 2),
                  ),
                  child: Center(
                    child: Text('${day.day}',
                        style: const TextStyle(
                            color: Colors.black, fontWeight: FontWeight.bold)),
                  ),
                );
              },
            ),
          ),

          // ── Legend ────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildLegendItem('Fully Taken', Colors.green),
                _buildLegendItem('Partially Taken', Colors.amber),
                _buildLegendItem('Not Taken', Colors.red),
              ],
            ),
          ),

          const Divider(height: 1),

          // ── Today's Medicines ─────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      "Today's Medicines",
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    if (_medicines.isNotEmpty)
                      _buildAdherenceBadge(taken, total, adherence),
                  ],
                ),
                const SizedBox(height: 12),
                if (_medicines.isEmpty)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Column(
                        children: [
                          Icon(Icons.medication_outlined,
                              size: 48, color: Colors.grey.shade400),
                          const SizedBox(height: 8),
                          Text('No medicines added yet',
                              style:
                                  TextStyle(color: Colors.grey.shade600)),
                          const SizedBox(height: 4),
                          Text(
                            'Go to Profile → Manage Medicines',
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey.shade500),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  ...  _medicines.map((medicine) {
                    final isTaken =
                        medicineStatus[medicine.id] ?? false;
                    return _buildMedicineRow(medicine, isTaken);
                  }),
              ],
            ),
          ),

          // ── Doctor Notifications ───────────────────────────────────────
          _buildNotificationsSection(),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildNotificationsSection() {
    final unreadCount = _notifications.where((n) => !n.read).length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(height: 1),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(children: [
                Text(
                  'Doctor Alerts',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                if (unreadCount > 0) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.indigo,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '$unreadCount new',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                ]
              ]),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (unreadCount > 0)
                    TextButton(
                      onPressed: () => _notifService.markAllAsRead(),
                      style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(0, 0)),
                      child: const Text('Mark all read',
                          style: TextStyle(fontSize: 12)),
                    ),
                  if (_notifications.isNotEmpty)
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert, size: 20),
                      padding: EdgeInsets.zero,
                      onSelected: (value) async {
                        if (value == 'delete_read') {
                          await _notifService.deleteAllReadNotifications();
                          // Force refresh from server
                          await _loadNotificationsFromServer();
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Deleted all read messages')),
                            );
                          }
                        } else if (value == 'delete_all') {
                          final confirm = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text('Delete All Messages'),
                              content: const Text('Are you sure you want to delete all messages from your doctor?'),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx, true),
                                  child: const Text('Delete All', style: TextStyle(color: Colors.red)),
                                ),
                              ],
                            ),
                          );
                          if (confirm == true) {
                            await _notifService.deleteAllNotifications();
                            // Force refresh from server
                            await _loadNotificationsFromServer();
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Deleted all messages')),
                              );
                            }
                          }
                        }
                      },
                      itemBuilder: (ctx) => [
                        const PopupMenuItem(value: 'delete_read', child: Text('Delete read messages')),
                        const PopupMenuItem(value: 'delete_all', child: Text('Delete all messages', style: TextStyle(color: Colors.red))),
                      ],
                    ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (_notifications.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.notifications_none_rounded,
                      size: 40, color: Colors.grey.shade400),
                  const SizedBox(height: 6),
                  Text('No alerts from your doctor',
                      style: TextStyle(color: Colors.grey.shade500)),
                ]),
              ),
            )
          else
            ...  _notifications.map((notif) {
              return GestureDetector(
                onTap: notif.read
                    ? null
                    : () => _notifService.markAsRead(notif.id),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                    color: notif.read
                        ? Theme.of(context).cardColor
                        : Colors.indigo.withAlpha(12),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: notif.read
                          ? Colors.grey.withAlpha(50)
                          : Colors.indigo.withAlpha(80),
                      width: notif.read ? 1 : 1.5,
                    ),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 6),
                    leading: CircleAvatar(
                      backgroundColor:
                          Colors.indigo.withAlpha(30),
                      child: const Icon(Icons.local_hospital,
                          color: Colors.indigo, size: 18),
                    ),
                    title: Text(
                      notif.message,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: notif.read
                            ? FontWeight.normal
                            : FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      DateFormat('MMM d, h:mm a')
                          .format(notif.timestamp),
                      style: const TextStyle(fontSize: 11),
                    ),
                    trailing: notif.read
                        ? IconButton(
                            icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                            onPressed: () async {
                              await _notifService.deleteNotification(notif.id);
                              await _loadNotificationsFromServer();
                            },
                            tooltip: 'Delete message',
                          )
                        : Container(
                            width: 10,
                            height: 10,
                            decoration: const BoxDecoration(
                              color: Colors.indigo,
                              shape: BoxShape.circle,
                            ),
                          ),
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildAdherenceBadge(int taken, int total, int adherence) {
    final color = adherence == 100
        ? Colors.green
        : adherence > 0
            ? Colors.amber.shade700
            : Colors.red;
    final bg = adherence == 100
        ? Colors.green.shade50
        : adherence > 0
            ? Colors.amber.shade50
            : Colors.red.shade50;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color),
      ),
      child: Text(
        '$taken / $total taken',
        style: TextStyle(
            fontSize: 12, fontWeight: FontWeight.w600, color: color),
      ),
    );
  }

  Widget _buildMedicineRow(Medicine medicine, bool isTaken) {
    final canMark = _canMarkMedicine(medicine);
    final opacity = canMark ? 1.0 : 0.5;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: (canMark && !_isLoggingMedicine)
            ? () => _toggleMedicineTaken(medicine, !isTaken)
            : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: !canMark
                ? Colors.grey.withAlpha(20)
                : isTaken
                    ? Colors.green.withAlpha(25)
                    : Theme.of(context).cardColor,
            border: Border.all(
              color: !canMark
                  ? Colors.grey.shade300
                  : isTaken
                      ? Colors.green.shade300
                      : Colors.grey.shade300,
            ),
          ),
          child: Opacity(
            opacity: opacity,
            child: Row(
              children: [
                // Checkbox indicator
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isTaken && canMark ? Colors.green : Colors.transparent,
                    border: Border.all(
                      color: !canMark
                          ? Colors.grey.shade400
                          : isTaken
                              ? Colors.green
                              : Colors.grey.shade400,
                      width: 2,
                    ),
                  ),
                  child: isTaken && canMark
                      ? const Icon(Icons.check, size: 16, color: Colors.white)
                      : !canMark
                          ? Icon(Icons.lock, size: 14, color: Colors.grey.shade400)
                          : null,
                ),
                const SizedBox(width: 12),
                // Name + Dosage
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        medicine.name,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          decoration:
                              isTaken && canMark ? TextDecoration.lineThrough : null,
                          color: isTaken && canMark ? Colors.grey :
                                !canMark ? Colors.grey.shade500 : null,
                        ),
                      ),
                      Text(
                        medicine.dosage,
                        style: TextStyle(
                            fontSize: 12,
                            color: !canMark
                                ? Colors.grey.shade400
                                : Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
                // Alarm times
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: medicine.times.map((t) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.alarm,
                              size: 12,
                              color: !canMark
                                  ? Colors.grey.shade400
                                  : isTaken && canMark
                                      ? Colors.green
                                      : Colors.blue.shade400),
                          const SizedBox(width: 3),
                          Text(
                            t,
                            style: TextStyle(
                              fontSize: 12,
                              color: !canMark
                                  ? Colors.grey.shade400
                                  : isTaken && canMark
                                      ? Colors.green
                                      : Colors.blue.shade700,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLegendItem(String label, Color color) {
    return Row(
      children: [
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 11)),
      ],
    );
  }
}
