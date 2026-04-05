# MediTrack CF - Patient Mobile Application

A comprehensive medication adherence tracking system for Cystic Fibrosis patients with strict alarm reminders, rule-based risk analysis, and doctor consultation alerts.

## Features

✅ **Strict Medication Alarms**
- Full-screen notifications with exact timing
- Uses `exactAllowWhileIdle` for precise scheduling
- Alarms work even when device is locked

✅ **Rule-Based Risk Analysis** (NO Machine Learning)
- Green (Low Risk): ≥80% adherence
- Amber (Moderate Risk): 50-79% adherence
- Red (High Risk): <50% adherence

✅ **Calendar View**
- Color-coded daily adherence tracking
- Tap any day to view/mark medicines

✅ **Trend Analysis**
- Bar charts showing 7-day or 30-day adherence trends
- Average adherence calculation

✅ **Medicine Management**
- Add/Edit/Delete medicines with custom schedules
- Automatic alarm rescheduling on changes

✅ **Doctor Consultation Alerts**
- Real-time alerts when doctor requests consultation
- Dialog notification system

## Prerequisites

- Flutter SDK (3.0.0 or higher)
- Android SDK (API level 21+)
- Firebase project configured
- Physical Android device or emulator

## Setup Instructions

### 1. Install Dependencies

```bash
cd d:/meditrack_cf/meditrack_patient
flutter pub get
```

### 2. Configure Firebase

#### Option A: Using FlutterFire CLI (Recommended)

```bash
# Install FlutterFire CLI
dart pub global activate flutterfire_cli

# Configure Firebase
flutterfire configure
```

This will automatically:
- Create Firebase project (or select existing)
- Register Android app
- Download `google-services.json`
- Update `firebase_options.dart`

#### Option B: Manual Configuration

1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Create a new project or select existing
3. Add an Android app with package name: `com.meditrack.meditrack_patient`
4. Download `google-services.json`
5. Place it in: `d:/meditrack_cf/meditrack_patient/android/app/google-services.json`
6. Update `lib/firebase_options.dart` with your Firebase configuration

### 3. Enable Firestore

1. In Firebase Console, go to Firestore Database
2. Click "Create Database"
3. Start in **test mode** (or configure security rules)
4. Collections will be auto-created on first write:
   - `users/{uid}`
   - `users/{uid}/medicines/{medId}`
   - `daily_logs/{uid}_{date}`
   - `alerts/{alertId}`

### 4. Configure Firestore Security Rules (Optional)

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /users/{userId} {
      allow read, write: if request.auth != null && request.auth.uid == userId;
      match /medicines/{medId} {
        allow read, write: if request.auth != null && request.auth.uid == userId;
      }
    }
    match /daily_logs/{logId} {
      allow read, write: if request.auth != null;
    }
    match /alerts/{alertId} {
      allow read, write: if request.auth != null;
    }
  }
}
```

### 5. Run the Application

```bash
# Connect your Android device or start emulator
flutter devices

# Run the app
flutter run
```

## Testing

### Run Unit Tests

```bash
flutter test
```

The tests verify:
- ✅ 79% adherence → Moderate Risk
- ✅ 80% adherence → Low Risk
- ✅ 49% adherence → High Risk
- ✅ 50% adherence → Moderate Risk

### Manual Testing Checklist

#### Alarm Test
1. Add a medicine with alarm time 1 minute in future
2. Lock your device screen
3. **Expected**: Full-screen notification appears with sound
4. **Verify**: Notification shows medicine name and dosage

#### Calendar Color Test
1. Go to Home tab
2. Mark all medicines as taken for today
3. **Expected**: Today's calendar cell turns Green
4. Mark only some medicines
5. **Expected**: Cell turns Amber (if 50-79%) or Red (if <50%)

#### Consultation Alert Test
1. Have doctor click "Request Consultation" on web dashboard
2. **Expected**: Dialog appears on patient app within seconds
3. Tap "OK, I understand"
4. **Expected**: Alert is marked as acknowledged

#### Medicine Sync Test
1. Go to Profile → Manage Medicines
2. Add new medicine with specific times
3. **Expected**: Medicine appears in Firestore Console
4. **Expected**: Alarms are scheduled immediately
5. Delete the medicine
6. **Expected**: Alarms are cancelled

## Project Structure

```
lib/
├── main.dart                          # App entry point
├── firebase_options.dart              # Firebase configuration
├── models/                            # Data models
│   ├── user.dart
│   ├── medicine.dart
│   ├── daily_log.dart
│   └── alert.dart
├── services/                          # Business logic
│   ├── auth_service.dart              # Authentication
│   ├── risk_service.dart              # Rule-based risk calculation
│   ├── alarm_service.dart             # Strict alarm scheduling
│   ├── medicine_service.dart          # Medicine CRUD + sync
│   └── consultation_service.dart      # Doctor alert listener
└── screens/                           # UI screens
    ├── login_screen.dart
    ├── register_screen.dart
    ├── main_screen.dart               # Bottom navigation
    ├── home_screen.dart               # Calendar view
    ├── graphs_screen.dart             # Trend charts
    ├── profile_screen.dart
    └── manage_medicines_screen.dart
```

## Key Implementation Details

### Strict Alarm Configuration

The `AlarmService` uses the following critical settings:

```dart
AndroidNotificationDetails(
  importance: Importance.max,
  priority: Priority.high,
  fullScreenIntent: true,  // CRITICAL
  enableVibration: true,
  playSound: true,
)

// CRITICAL scheduling mode
androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle
```

### Android Manifest Permissions

```xml
<uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM" />
<uses-permission android:name="android.permission.USE_EXACT_ALARM" />
<uses-permission android:name="android.permission.USE_FULL_SCREEN_INTENT" />
<uses-permission android:name="android.permission.VIBRATE" />
<uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED" />
<uses-permission android:name="android.permission.WAKE_LOCK" />
```

### Risk Calculation Logic

```dart
if (adherence >= 80) return RiskLevel.low;      // Green
if (adherence >= 50) return RiskLevel.moderate; // Amber
return RiskLevel.high;                          // Red
```

## Compliance Verification

- ✅ **No ML**: All logic is deterministic if/else statements
- ✅ **Real Alarms**: Uses `exactAllowWhileIdle` and `fullScreenIntent`
- ✅ **Medicine Input**: Explicit "Manage Medicines" screen
- ✅ **Doctor Alerts**: Manual trigger from doctor dashboard
- ✅ **Scaffolding**: Standard Flutter Android project structure

## Troubleshooting

### Alarms Not Firing

1. Check if exact alarm permission is granted:
   - Settings → Apps → MediTrack CF → Permissions → Alarms & reminders
2. Ensure battery optimization is disabled for the app
3. Verify Android version is 12+ for `SCHEDULE_EXACT_ALARM`

### Firebase Connection Issues

1. Verify `google-services.json` is in correct location
2. Check Firebase project configuration
3. Ensure internet permission is in manifest
4. Run `flutterfire configure` again

### Build Errors

```bash
# Clean and rebuild
flutter clean
flutter pub get
flutter run
```

## Next Steps

1. Deploy to physical device for real-world testing
2. Configure production Firestore security rules
3. Add Firebase Authentication email verification
4. Implement push notifications for doctor alerts
5. Add data export functionality

## License

This project is part of the MediTrack CF healthcare system.
