import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// FCM topic the release workflow sends "new version" pushes to.
const String _updatesTopic = 'app_updates';

/// Phone notifications for new CivicBuddy releases, pushed through Firebase
/// Cloud Messaging by the GitHub release workflow (Android only).
///
/// When the app is closed or in the background, Android shows the push
/// itself; tapping it opens the app, which then shows the update popup.
class UpdateNotifier {
  static final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'app_updates',
    'App updates',
    description: 'Tells you when a new CivicBuddy version is ready.',
    importance: Importance.high,
  );

  static bool _started = false;

  /// Connects to Firebase and subscribes to update pushes. Does nothing if
  /// the build has no Firebase config (android/app/google-services.json).
  static Future<void> start() async {
    if (!Platform.isAndroid) return;

    await Firebase.initializeApp();

    // The channel named in the push (and in AndroidManifest.xml).
    await _notifications.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_launcher_foreground'),
      ),
    );
    await _notifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(_channel);

    // Android does not show pushes while the app is open, so show it here.
    FirebaseMessaging.onMessage.listen((message) {
      final notification = message.notification;
      if (notification == null) return;
      _notifications.show(
        id: notification.hashCode,
        title: notification.title,
        body: notification.body,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            _channel.id,
            _channel.name,
            channelDescription: _channel.description,
            importance: Importance.high,
            priority: Priority.high,
            icon: 'ic_launcher_foreground',
          ),
        ),
      );
    });

    _started = true;
    // Needs the network; retried by Firebase, so do not wait for it.
    FirebaseMessaging.instance.subscribeToTopic(_updatesTopic).ignore();
  }

  /// Android 13+ asks "Allow CivicBuddy to send you notifications?" once.
  static Future<void> requestPermission() async {
    if (!_started) return;
    await FirebaseMessaging.instance.requestPermission();
  }
}
