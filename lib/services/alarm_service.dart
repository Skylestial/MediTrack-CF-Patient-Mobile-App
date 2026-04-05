import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:flutter_timezone/flutter_timezone.dart';
import '../models/medicine.dart';
import '../screens/alarm_screen.dart';
import '../utils/navigator_key.dart';

class AlarmService {
  static final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  static bool _initialized = false;
  static const int _followUpCount = 0;

  static Future<void> initialize() async {
    if (_initialized) return;

    // Initialize timezones
    tz.initializeTimeZones();
    try {
      final String deviceTimeZone = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(deviceTimeZone));
    } catch (_) {
      // Fallback - use a safe default
    }

    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    await _notifications.initialize(
      const InitializationSettings(android: androidSettings),
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );
    
    // Ensure notifications show in foreground with sound and alert
    final androidPlugin = _notifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    
    // Delete old notification channels and recreate with correct settings
    await androidPlugin?.deleteNotificationChannel('meditrack_alarms');
    await androidPlugin?.deleteNotificationChannel('meditrack_alarms_v2');
    await androidPlugin?.deleteNotificationChannel('meditrack_alarms_v3');
    await androidPlugin?.deleteNotificationChannel('meditrack_alarms_v4');

    _initialized = true;
    
    // Request permissions (non-blocking)
    _requestPermissions();
  }

  static Future<void> _requestPermissions() async {
    try {
      // Request notification permission (Android 13+)
      final plugin = _notifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      await plugin?.requestNotificationsPermission();
      
      // Request exact alarm permission (Android 12+)
      final canSchedule = await plugin?.canScheduleExactNotifications() ?? false;
      if (!canSchedule) {
        await plugin?.requestExactAlarmsPermission();
      }
      
      // Request battery optimization exemption (critical for locked screen alarms)
      final batteryStatus = await Permission.ignoreBatteryOptimizations.status;
      if (!batteryStatus.isGranted) {
        await Permission.ignoreBatteryOptimizations.request();
      }
    } catch (_) {}
  }
  
  /// Check if notifications are enabled
  static Future<bool> areNotificationsEnabled() async {
    final plugin = _notifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    return await plugin?.areNotificationsEnabled() ?? false;
  }

  static Future<bool> hasExactAlarmPermission() async {
    final plugin = _notifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    return await plugin?.canScheduleExactNotifications() ?? false;
  }

  /// Called when user taps a notification — opens the AlarmScreen
  static void _onNotificationTapped(NotificationResponse response) {
    if (response.payload == null) return;
    // Cancel the notification that was tapped (removes it from lock screen)
    _notifications.cancel(response.id ?? 0);
    try {
      final data = jsonDecode(response.payload!) as Map<String, dynamic>;
      navigatorKey.currentState?.push(
        MaterialPageRoute(
          builder: (_) => AlarmScreen(
            notificationId: response.id ?? 0,
            medicineId: data['id'] ?? '',
            medicineName: data['name'] ?? 'Medicine',
            dosage: data['dosage'] ?? '',
            medicineTimes: List<String>.from(data['times'] ?? []),
          ),
          fullscreenDialog: true,
        ),
      );
    } catch (_) {
      // Payload parse failed
    }
  }

  /// Show a notification IMMEDIATELY (no scheduling, no timezone).
  static Future<void> showImmediateNotification() async {
    await initialize();
    try {
      await _notifications.show(
        888888,
        '🔔 Notification Test',
        'If you see this, notifications are working!',
        NotificationDetails(android: _alarmDetails()),
      );
    } catch (e) {
      rethrow;
    }
  }

  /// Schedule all alarms for a medicine:
  /// - Main alarm at the exact time
  /// - 5 follow-up reminders at T+1, T+2, T+3, T+4, T+5 minutes
  /// All repeat daily.
  static Future<void> scheduleAlarmsForMedicine(Medicine medicine) async {
    await initialize();

    for (int timeIdx = 0; timeIdx < medicine.times.length; timeIdx++) {
      try {
        final timeStr = medicine.times[timeIdx];
        final parts = timeStr.split(':');
        
        // Safe parsing with fallback - strip non-numeric characters
        int baseHour = 8;
        int baseMinute = 0;
        
        if (parts.length >= 2) {
          final hourStr = parts[0].replaceAll(RegExp(r'[^0-9]'), '');
          final minStr = parts[1].replaceAll(RegExp(r'[^0-9]'), '');
          baseHour = (int.tryParse(hourStr) ?? 8).clamp(0, 23);
          baseMinute = (int.tryParse(minStr) ?? 0).clamp(0, 59);
        } else if (parts.length == 1) {
          final hourStr = parts[0].replaceAll(RegExp(r'[^0-9]'), '');
          baseHour = (int.tryParse(hourStr) ?? 8).clamp(0, 23);
        }

        // Schedule main + follow-up alarms
        for (int offset = 0; offset <= _followUpCount; offset++) {
          // Handle minute/hour overflow (e.g., 23:58 + 3 min = 00:01 next day)
          final totalMinutes = baseHour * 60 + baseMinute + offset;
          final hour = (totalMinutes ~/ 60) % 24;
          final minute = totalMinutes % 60;

          final notificationId = '${medicine.id}_${timeIdx}_$offset'.hashCode;

          final bool isMain = offset == 0;
          final String title = isMain
              ? '💊 Medicine Reminder: ${medicine.name}'
              : '⏰ Missed Dose: ${medicine.name}';
          final String body = isMain
              ? 'Time to take ${medicine.dosage}'
              : 'You missed your ${medicine.dosage} – Take it now!';

          final String payload = jsonEncode({
            'id': medicine.id,
            'name': medicine.name,
            'dosage': medicine.dosage,
            'times': medicine.times,
          });

          await _scheduleDailyAlarm(
            notificationId,
            title,
            body,
            hour,
            minute,
            payload,
          );
        }
      } catch (_) {
        // Skip this time slot if scheduling fails
        continue;
      }
    }
  }

  /// Build standard alarm notification details
  static AndroidNotificationDetails _alarmDetails({bool useCustomSound = true}) {
    return AndroidNotificationDetails(
      'meditrack_alarms_v5', // New channel for alarmClock mode
      'Medicine Alarms',
      channelDescription: 'Medicine reminders that wake your phone',
      importance: Importance.max,
      priority: Priority.max,
      fullScreenIntent: true,
      playSound: true,
      sound: useCustomSound ? const RawResourceAndroidNotificationSound('alarm') : null,
      enableVibration: true,
      vibrationPattern: Int64List.fromList([0, 1000, 500, 1000, 500, 1000]),
      category: AndroidNotificationCategory.alarm,
      autoCancel: false,
      ongoing: true,  // Keep notification until dismissed
      visibility: NotificationVisibility.public,
      ticker: 'Medicine Reminder',
      // Additional settings for lock screen wake
      showWhen: true,
      when: DateTime.now().millisecondsSinceEpoch,
      usesChronometer: false,
      colorized: true,
      color: const Color(0xFFDC143C),
    );
  }

  /// Schedule a single daily exact alarm
  static Future<void> _scheduleDailyAlarm(
    int id,
    String title,
    String body,
    int hour,
    int minute,
    String payload,
  ) async {
    final now = tz.TZDateTime.now(tz.local);
    var scheduledDate = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );

    if (scheduledDate.isBefore(now)) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }

    // Use alarmClock mode - most reliable for medicine reminders
    // This uses AlarmManager.setAlarmClock() which:
    // - Shows alarm icon in status bar
    // - Wakes device even in Doze mode
    // - Works when phone is locked
    try {
      await _notifications.zonedSchedule(
        id,
        title,
        body,
        scheduledDate,
        NotificationDetails(android: _alarmDetails()),
        androidScheduleMode: AndroidScheduleMode.alarmClock,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.time,
        payload: payload,
      );
    } catch (_) {
      // Fallback: try exactAllowWhileIdle if alarmClock fails
      try {
        await _notifications.zonedSchedule(
          id,
          title,
          body,
          scheduledDate,
          NotificationDetails(android: _alarmDetails(useCustomSound: false)),
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
          matchDateTimeComponents: DateTimeComponents.time,
          payload: payload,
        );
      } catch (_) {
        // Alarm scheduling failed completely
      }
    }
  }

  /// Fire a test notification in 5 seconds
  static Future<void> scheduleTestAlarm() async {
    await initialize();
    final scheduledDate =
        tz.TZDateTime.now(tz.local).add(const Duration(seconds: 5));
    await _notifications.zonedSchedule(
      999999,
      '🔔 Test Alarm',
      'Notification system is working!',
      scheduledDate,
      NotificationDetails(android: _alarmDetails()),
      androidScheduleMode: AndroidScheduleMode.alarmClock,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      payload: 'test',
    );
  }

  /// Schedule a one-time snooze notification in [minutes] minutes
  static Future<void> scheduleSnooze(Medicine medicine, {int minutes = 1}) async {
    await initialize();
    final snoozeId = '${medicine.id}_snooze'.hashCode;
    final fireAt = tz.TZDateTime.now(tz.local).add(Duration(minutes: minutes));
    final payload = jsonEncode({
      'id': medicine.id,
      'name': medicine.name,
      'dosage': medicine.dosage,
      'times': medicine.times,
    });
    try {
      await _notifications.zonedSchedule(
        snoozeId,
        '⏰ Snooze: ${medicine.name}',
        'Time to take ${medicine.dosage}',
        fireAt,
        NotificationDetails(android: _alarmDetails()),
        androidScheduleMode: AndroidScheduleMode.alarmClock,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        // No matchDateTimeComponents → fires once only (not daily)
        payload: payload,
      );
    } catch (_) {
      // Snooze scheduling failed
    }
  }

  /// Cancel all alarms (main + follow-ups) for a medicine
  static Future<void> cancelAlarmsForMedicine(Medicine medicine) async {
    for (int timeIdx = 0; timeIdx < medicine.times.length; timeIdx++) {
      for (int offset = 0; offset <= _followUpCount; offset++) {
        final notificationId = '${medicine.id}_${timeIdx}_$offset'.hashCode;
        await _notifications.cancel(notificationId);
      }
    }
  }

  /// Reschedule all alarms — call this after any medicine list change
  /// or on app launch to survive phone restarts
  static Future<void> rescheduleAllAlarms(List<Medicine> medicines) async {
    try {
      await _notifications.cancelAll();
      for (final medicine in medicines) {
        await scheduleAlarmsForMedicine(medicine);
      }
    } catch (_) {
      // Silently handle alarm scheduling errors
    }
  }

  /// Cancel all alarms
  static Future<void> cancelAllAlarms() async {
    await _notifications.cancelAll();
  }

  // ─── Daily Log Reminder ─────────────────────────────────────────────────

  static const int _dailyLogReminderId = 777777;

  /// Schedule a daily reminder at 9 PM to log medicines
  /// This ensures patients open the app, which triggers fillMissingDays()
  static Future<void> scheduleDailyLogReminder({int hour = 21, int minute = 0}) async {
    await initialize();
    try {
      final now = tz.TZDateTime.now(tz.local);
      var scheduledDate = tz.TZDateTime(
        tz.local,
        now.year,
        now.month,
        now.day,
        hour,
        minute,
      );

      if (scheduledDate.isBefore(now)) {
        scheduledDate = scheduledDate.add(const Duration(days: 1));
      }

      await _notifications.zonedSchedule(
        _dailyLogReminderId,
        '📝 Daily Log Reminder',
        'Don\'t forget to log your medicines today!',
        scheduledDate,
        NotificationDetails(
          android: AndroidNotificationDetails(
            'meditrack_reminders_v2',
            'Daily Reminders',
            channelDescription: 'Reminds you to log your daily medicines',
            importance: Importance.high,
            priority: Priority.high,
            playSound: true,
            enableVibration: true,
            autoCancel: true,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.time,
      );
    } catch (_) {
      // Reminder scheduling failed
    }
  }

  /// Cancel the daily log reminder
  static Future<void> cancelDailyLogReminder() async {
    await _notifications.cancel(_dailyLogReminderId);
  }
}
