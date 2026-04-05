# Flutter Local Notifications - CRITICAL for release builds
-keep class com.dexterous.** { *; }
-keep class com.dexterous.flutterlocalnotifications.** { *; }
-keep class androidx.core.app.NotificationCompat** { *; }
-keep class androidx.core.app.NotificationManagerCompat** { *; }

# Keep Gson classes used by notifications
-keepattributes Signature
-keepattributes *Annotation*
-dontwarn sun.misc.**
-keep class com.google.gson.** { *; }
-keep class * extends com.google.gson.TypeAdapter
-keep class * implements com.google.gson.TypeAdapterFactory
-keep class * implements com.google.gson.JsonSerializer
-keep class * implements com.google.gson.JsonDeserializer

# Keep timezone data
-keep class org.threeten.** { *; }

# Firebase
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }

# Flutter
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Audioplayers
-keep class xyz.luan.audioplayers.** { *; }

# Vibration
-keep class com.benjaminabel.vibration.** { *; }

# Permission handler
-keep class com.baseflow.permissionhandler.** { *; }

# Keep all notification-related Android classes
-keep class android.app.Notification** { *; }
-keep class android.app.AlarmManager** { *; }
-keep class android.app.PendingIntent** { *; }

# Keep WorkManager for scheduled notifications
-keep class androidx.work.** { *; }

# Prevent stripping of broadcast receivers 
-keep public class * extends android.content.BroadcastReceiver

# Ignore missing Play Core classes (not used without deferred components)
-dontwarn com.google.android.play.core.splitcompat.SplitCompatApplication
-dontwarn com.google.android.play.core.splitinstall.**
-dontwarn com.google.android.play.core.tasks.**
