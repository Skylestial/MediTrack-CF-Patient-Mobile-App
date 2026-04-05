import 'package:flutter/material.dart';

/// Global navigator key — used by AlarmService to navigate to AlarmScreen
/// when a notification is tapped, even from a static callback.
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
