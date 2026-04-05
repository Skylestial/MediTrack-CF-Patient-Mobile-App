import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:vibration/vibration.dart';
import '../services/alarm_service.dart';
import '../models/medicine.dart';

/// Full-screen alarm UI shown when a medicine notification is tapped.
/// Features a pulsing animation and a slide-to-dismiss gesture.
class AlarmScreen extends StatefulWidget {
  final int notificationId;
  final String medicineName;
  final String dosage;
  final String medicineId;
  final List<String> medicineTimes;
  /// If true, app was launched just for this alarm (cold start from notification).
  /// When dismissed, the app will close entirely.
  /// If false, alarm was opened while app was running - will return to app on dismiss.
  final bool launchedStandalone;

  const AlarmScreen({
    super.key,
    required this.notificationId,
    required this.medicineName,
    required this.dosage,
    required this.medicineId,
    required this.medicineTimes,
    this.launchedStandalone = false,
  });

  @override
  State<AlarmScreen> createState() => _AlarmScreenState();
}

class _AlarmScreenState extends State<AlarmScreen>
    with TickerProviderStateMixin {
  // MethodChannel to control lock screen display
  static const _channel = MethodChannel('alarm_screen_channel');

  // Audio
  final AudioPlayer _audioPlayer = AudioPlayer();

  // Vibration timer
  Timer? _vibrationTimer;

  // Pulsing ring animations
  late AnimationController _pulseController;
  late AnimationController _scaleController;
  late Animation<double> _pulseAnimation;
  late Animation<double> _scaleAnimation;

  // Slide to dismiss
  bool _dismissed = false;

  // Clock
  late Timer _clockTimer;
  String _timeString = '';

  @override
  void initState() {
    super.initState();
    _updateTime();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) => _updateTime());

    // Turn screen on and show over lock screen
    _channel.invokeMethod('showOnLockScreen').catchError((_) {});
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    // Play looping alarm sound
    _startSound();

    // Start vibration pattern (repeat every 1.5s)
    _startVibration();

    // Outer pulse ring
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: false);
    _pulseAnimation = Tween<double>(begin: 0.8, end: 1.6).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeOut),
    );

    // Icon scale bounce
    _scaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);
    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.12).animate(
      CurvedAnimation(parent: _scaleController, curve: Curves.easeInOut),
    );
  }

  Future<void> _startSound() async {
    try {
      // Use the alarm audio stream (not media) so volume matches system alarm
      await AudioPlayer.global.setAudioContext(
        AudioContext(
          android: AudioContextAndroid(
            usageType: AndroidUsageType.alarm,
            audioFocus: AndroidAudioFocus.gain,
            contentType: AndroidContentType.music,
          ),
        ),
      );
      await _audioPlayer.setReleaseMode(ReleaseMode.loop);
      await _audioPlayer.setVolume(1.0);
      await _audioPlayer.play(
        AssetSource('alarm ringtone/alarm.mp3'),
      );
    } catch (_) {
      // Sound playback error
    }
  }

  void _startVibration() async {
    final hasVibrator = await Vibration.hasVibrator();
    if (hasVibrator != true) return;
    // Vibrate immediately then repeat every 1.5 seconds
    _vibrationTimer = Timer.periodic(const Duration(milliseconds: 1500), (_) async {
      Vibration.vibrate(pattern: [0, 400, 200, 400]);
    });
    Vibration.vibrate(pattern: [0, 400, 200, 400]);
  }

  void _stopSoundAndVibration() {
    _audioPlayer.stop();
    _audioPlayer.dispose();
    _vibrationTimer?.cancel();
    Vibration.cancel();
  }

  void _updateTime() {
    final now = DateTime.now();
    setState(() {
      _timeString =
          '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    });
  }

  Future<void> _dismiss() async {
    if (_dismissed) return;
    setState(() => _dismissed = true);

    _stopSoundAndVibration();

    // Cancel the notification that triggered this screen
    FlutterLocalNotificationsPlugin().cancel(widget.notificationId);

    // Cancel all follow-up alarms
    final medicine = Medicine(
      id: widget.medicineId,
      name: widget.medicineName,
      dosage: widget.dosage,
      times: widget.medicineTimes,
    );
    await AlarmService.cancelAlarmsForMedicine(medicine);

    if (mounted) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      _channel.invokeMethod('clearLockScreen').catchError((_) {});
      
      if (widget.launchedStandalone) {
        // App was launched just for this alarm (lock screen / cold start)
        // Close the app entirely
        SystemNavigator.pop();
      } else {
        // App was already running - return to previous screen
        Navigator.of(context).pop();
      }
    }
  }

  Future<void> _snooze() async {
    if (_dismissed) return;
    setState(() => _dismissed = true);

    _stopSoundAndVibration();

    // Cancel the triggering notification AND all pre-scheduled follow-ups
    // so they don't fire while the snooze is pending
    FlutterLocalNotificationsPlugin().cancel(widget.notificationId);
    final medicine = Medicine(
      id: widget.medicineId,
      name: widget.medicineName,
      dosage: widget.dosage,
      times: widget.medicineTimes,
    );
    await AlarmService.cancelAlarmsForMedicine(medicine);

    // Schedule single one-time snooze
    await AlarmService.scheduleSnooze(medicine, minutes: 1);

    if (mounted) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      _channel.invokeMethod('clearLockScreen').catchError((_) {});
      
      if (widget.launchedStandalone) {
        // App was launched just for this alarm - close entirely
        SystemNavigator.pop();
      } else {
        // App was already running - return to previous screen
        Navigator.of(context).pop();
      }
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _scaleController.dispose();
    _clockTimer.cancel();
    _stopSoundAndVibration();
    _channel.invokeMethod('clearLockScreen').catchError((_) {});
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenW = MediaQuery.of(context).size.width;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF0A0E2E),
              Color(0xFF0D1B4B),
              Color(0xFF1A0533),
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // ── Top: Time & Label ──────────────────────────────────────
              Padding(
                padding: const EdgeInsets.only(top: 32),
                child: Column(
                  children: [
                    Text(
                      _timeString,
                      style: const TextStyle(
                        fontSize: 72,
                        fontWeight: FontWeight.w100,
                        color: Colors.white,
                        letterSpacing: 4,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: Colors.white.withOpacity(0.2)),
                      ),
                      child: const Text(
                        'Medicine Reminder',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                          letterSpacing: 2,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // ── Center: Pulsing Ring + Icon ────────────────────────────
              SizedBox(
                width: 260,
                height: 260,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Outer fading pulse ring
                    AnimatedBuilder(
                      animation: _pulseAnimation,
                      builder: (context, child) => Opacity(
                        opacity: (1.6 - _pulseAnimation.value).clamp(0.0, 0.6),
                        child: Transform.scale(
                          scale: _pulseAnimation.value,
                          child: Container(
                            width: 160,
                            height: 160,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: const Color(0xFF6C63FF),
                                width: 2,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    // Second pulse ring (offset phase)
                    AnimatedBuilder(
                      animation: _pulseController,
                      builder: (context, child) {
                        final v = (_pulseController.value + 0.5) % 1.0;
                        final scale = 0.8 + v * 0.8;
                        final opacity = (1.6 - scale).clamp(0.0, 0.5);
                        return Opacity(
                          opacity: opacity,
                          child: Transform.scale(
                            scale: scale,
                            child: Container(
                              width: 160,
                              height: 160,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: const Color(0xFF9C89FF),
                                  width: 1.5,
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                    // Center circle + icon
                    AnimatedBuilder(
                      animation: _scaleAnimation,
                      builder: (context, child) => Transform.scale(
                        scale: _scaleAnimation.value,
                        child: child,
                      ),
                      child: Container(
                        width: 130,
                        height: 130,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: const RadialGradient(
                            colors: [Color(0xFF7C6FFF), Color(0xFF4B3DC8)],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF6C63FF).withOpacity(0.6),
                              blurRadius: 40,
                              spreadRadius: 8,
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.medication_rounded,
                          size: 64,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // ── Medicine Info ──────────────────────────────────────────
              Column(
                children: [
                  Text(
                    widget.medicineName,
                    style: const TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      letterSpacing: 0.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.dosage,
                    style: TextStyle(
                      fontSize: 18,
                      color: Colors.white.withOpacity(0.7),
                    ),
                  ),
                ],
              ),

              // ── Snooze + Slide Row ─────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(32, 0, 32, 20),
                child: GestureDetector(
                  onTap: _dismissed ? null : _snooze,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(40),
                      color: Colors.white.withAlpha(20),
                      border: Border.all(color: Colors.white.withAlpha(45)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.snooze_rounded,
                            color: Colors.white70, size: 20),
                        const SizedBox(width: 8),
                        const Text(
                          'Snooze 1 min',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // ── Slide to Dismiss ───────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(32, 0, 32, 48),
                child: _SlideToStop(
                  trackWidth: screenW - 64,
                  onDismissed: _dismiss,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Custom slide-to-stop widget
class _SlideToStop extends StatefulWidget {
  final double trackWidth;
  final VoidCallback onDismissed;

  const _SlideToStop({required this.trackWidth, required this.onDismissed});

  @override
  State<_SlideToStop> createState() => _SlideToStopState();
}

class _SlideToStopState extends State<_SlideToStop>
    with SingleTickerProviderStateMixin {
  static const double _thumbSize = 62.0;
  double _offset = 0.0;
  bool _done = false;

  late AnimationController _snapBack;
  late Animation<double> _snapAnimation;

  @override
  void initState() {
    super.initState();
    _snapBack = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
  }

  @override
  void dispose() {
    _snapBack.dispose();
    super.dispose();
  }

  double get _maxOffset => widget.trackWidth - _thumbSize - 8;
  double get _progress => (_offset / _maxOffset).clamp(0.0, 1.0);

  void _onDrag(DragUpdateDetails d) {
    if (_done) return;
    setState(() {
      _offset = (_offset + d.delta.dx).clamp(0.0, _maxOffset);
    });
  }

  void _onDragEnd(DragEndDetails d) {
    if (_done) return;
    if (_progress >= 0.88) {
      setState(() {
        _done = true;
        _offset = _maxOffset;
      });
      widget.onDismissed();
    } else {
      // Snap back
      _snapAnimation =
          Tween<double>(begin: _offset, end: 0.0).animate(
        CurvedAnimation(parent: _snapBack, curve: Curves.elasticOut),
      )..addListener(() {
          setState(() => _offset = _snapAnimation.value);
        });
      _snapBack.forward(from: 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: _thumbSize + 8,
      width: widget.trackWidth,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular((_thumbSize + 8) / 2),
        color: Colors.white.withOpacity(0.08),
        border: Border.all(color: Colors.white.withOpacity(0.15)),
      ),
      child: Stack(
        alignment: Alignment.centerLeft,
        children: [
          // Fill progress
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular((_thumbSize + 8) / 2),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  width: _offset + _thumbSize,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        const Color(0xFF6C63FF).withOpacity(0.4),
                        const Color(0xFF6C63FF).withOpacity(0.1),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          // Label text
          Align(
            alignment: Alignment.center,
            child: Opacity(
              opacity: (1 - _progress * 1.5).clamp(0.0, 1.0),
              child: const Text(
                'Slide to stop  →',
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 15,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
          // Thumb
          Positioned(
            left: _offset + 4,
            child: GestureDetector(
              onHorizontalDragUpdate: _onDrag,
              onHorizontalDragEnd: _onDragEnd,
              child: Container(
                width: _thumbSize,
                height: _thumbSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF9C89FF), Color(0xFF5B4FCF)],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF6C63FF).withOpacity(0.6),
                      blurRadius: 16,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Icon(
                  _done ? Icons.check_rounded : Icons.arrow_forward_ios_rounded,
                  color: Colors.white,
                  size: 26,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
