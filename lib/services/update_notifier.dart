import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import 'update_service.dart';

const String _taskName = 'civicbuddy-update-check';
const String _notifiedVersionKey = 'notified_update_version';

/// Runs in a background isolate started by Android's WorkManager, even when
/// the app is closed.
@pragma('vm:entry-point')
void updateCheckDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      await UpdateNotifier.checkAndNotify();
    } catch (_) {
      // Try again at the next scheduled run.
    }
    return true;
  });
}

/// Shows a phone notification when a newer CivicBuddy release is on GitHub,
/// checked in the background every few hours (Android only).
class UpdateNotifier {
  static final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  static const AndroidNotificationDetails _androidDetails =
      AndroidNotificationDetails(
        'app_updates',
        'App updates',
        channelDescription: 'Tells you when a new CivicBuddy version is ready.',
        importance: Importance.high,
        priority: Priority.high,
      );

  /// Schedules the background check. Safe to call on every launch: an
  /// existing schedule is kept.
  static Future<void> start() async {
    if (!UpdateService.isSupported) return;

    await Workmanager().initialize(updateCheckDispatcher);
    await Workmanager().registerPeriodicTask(
      _taskName,
      _taskName,
      frequency: const Duration(hours: 4),
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
    );
  }

  /// Android 13+ asks "Allow CivicBuddy to send you notifications?" once.
  static Future<void> requestPermission() async {
    if (!Platform.isAndroid) return;

    await _init();
    await _notifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission();
  }

  /// Notifies once per new version; tapping the notification opens the app,
  /// which then shows the usual update popup.
  static Future<void> checkAndNotify() async {
    final update = await UpdateService.checkForUpdate();
    if (update == null || !update.updateAvailable) return;

    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString(_notifiedVersionKey) == update.latestVersion) return;

    await _init();
    await _notifications.show(
      id: 1001,
      title: 'CivicBuddy has a new version',
      body:
          'Version ${update.latestVersion} is ready. Tap to update to the '
          'latest version.',
      notificationDetails: const NotificationDetails(android: _androidDetails),
    );

    await prefs.setString(_notifiedVersionKey, update.latestVersion);
  }

  static Future<void> _init() async {
    await _notifications.initialize(
      settings: const InitializationSettings(
        // Monochrome-friendly icon: the logo disc on a transparent background.
        android: AndroidInitializationSettings('ic_launcher_foreground'),
      ),
    );
  }
}
