import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'firebase_options.dart';
import 'screens/login_screen.dart';
import 'screens/main_screen.dart';
import 'screens/alarm_screen.dart';
import 'services/auth_service.dart';
import 'services/medicine_service.dart';
import 'services/alarm_service.dart';
import 'package:provider/provider.dart';
import 'providers/theme_provider.dart';
import 'utils/navigator_key.dart';

// Store notification payload that launched the app
Map<String, dynamic>? _launchNotificationPayload;
int? _launchNotificationId;
bool _launchedFromAlarm = false;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Initialize alarm service FIRST (registers notification callbacks)
  await AlarmService.initialize();

  // Check if app was launched from a notification (for fullscreen intent)
  await _checkNotificationLaunch();

  // Lock orientation to portrait
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Reschedule alarms on launch (survives phone restarts) - runs async, doesn't block
  _rescheduleAlarmsOnLaunch();

  // If launched from alarm notification, show AlarmScreen immediately (no auth required)
  if (_launchedFromAlarm && _launchNotificationPayload != null) {
    final data = _launchNotificationPayload!;
    final notifId = _launchNotificationId ?? 0;
    
    runApp(
      MaterialApp(
        title: 'MediTrack CF - Alarm',
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark().copyWith(
          scaffoldBackgroundColor: Colors.black,
        ),
        home: AlarmScreen(
          notificationId: notifId,
          medicineId: data['id'] ?? '',
          medicineName: data['name'] ?? 'Medicine',
          dosage: data['dosage'] ?? '',
          medicineTimes: List<String>.from(data['times'] ?? []),
          launchedStandalone: true, // Will close app on dismiss
        ),
      ),
    );
    return; // Don't load the full app
  }

  // Restore saved theme before first frame
  final themeProvider = ThemeProvider();
  await themeProvider.loadTheme();

  runApp(
    ChangeNotifierProvider<ThemeProvider>.value(
      value: themeProvider,
      child: const MediTrackPatientApp(),
    ),
  );
}

/// Check if app was launched by tapping a notification or fullscreen intent
Future<void> _checkNotificationLaunch() async {
  try {
    final plugin = FlutterLocalNotificationsPlugin();
    final details = await plugin.getNotificationAppLaunchDetails();
    if (details?.didNotificationLaunchApp == true &&
        details?.notificationResponse != null) {
      final response = details!.notificationResponse!;
      if (response.payload != null) {
        _launchNotificationPayload = jsonDecode(response.payload!) as Map<String, dynamic>;
        _launchNotificationId = response.id;
        _launchedFromAlarm = true;
      }
    }
  } catch (_) {
    // Ignore errors
  }
}

/// Reschedule alarms after phone restart or cold app launch
Future<void> _rescheduleAlarmsOnLaunch() async {
  try {
    final authService = AuthService();
    final userId = authService.currentUserId;
    if (userId == null) return;

    final medicineService = MedicineService(userId);
    final medicines = await medicineService.getMedicines();
    if (medicines.isNotEmpty) {
      await AlarmService.rescheduleAllAlarms(medicines);
    }
  } catch (_) {
    // Don't block app launch if rescheduling fails
  }
}

class MediTrackPatientApp extends StatelessWidget {
  const MediTrackPatientApp({super.key});

  // Crimson color matching web app
  static const _crimson = Color(0xFFDC143C);
  static const _darkBg = Color(0xFF000000); // Pure black
  static const _darkCard = Color(0xFF1C1C1E); // Dark card
  static const _lightBg = Color(0xFFF0F4F8); // Light background matching web

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    
    return MaterialApp(
      title: 'MediTrack CF - Patient',
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,
      themeMode: themeProvider.themeMode,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: _crimson,
          brightness: Brightness.light,
          primary: _crimson,
          secondary: _crimson,
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: _lightBg,
        appBarTheme: const AppBarTheme(
          backgroundColor: _crimson,
          foregroundColor: Colors.white,
          elevation: 2,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: _crimson,
            foregroundColor: Colors.white,
          ),
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: _crimson,
          foregroundColor: Colors.white,
        ),
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: _crimson,
          brightness: Brightness.dark,
          primary: _crimson,
          secondary: _crimson,
          surface: _darkCard,
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: _darkBg,
        cardColor: _darkCard,
        appBarTheme: const AppBarTheme(
          backgroundColor: _crimson,
          foregroundColor: Colors.white,
          elevation: 2,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: _crimson,
            foregroundColor: Colors.white,
          ),
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: _crimson,
          foregroundColor: Colors.white,
        ),
      ),
      home: const AuthWrapper(),
    );
  }
}

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    final authService = AuthService();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return StreamBuilder(
      stream: authService.authStateChanges,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
            backgroundColor: isDark ? const Color(0xFF111827) : Colors.white,
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset('assets/images/logo.jpg', height: 100, width: 100),
                  const SizedBox(height: 24),
                  const Text(
                    'MediTrack CF',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'v0.0.8',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                  ),
                  const SizedBox(height: 32),
                  const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Color(0xFFDC143C),
                    ),
                  ),
                ],
              ),
            ),
          );
        }
        
        if (snapshot.hasData) {
          return const MainScreen();
        }
        
        return const LoginScreen();
      },
    );
  }
}
