import 'dart:io';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:location/location.dart' as location_settings;

/// Makes sure GPS is on and location permission is granted before reading
/// the position, asking the user the way Android apps normally do:
///
/// - GPS off: Android's "Turn on location?" dialog (one tap). If that dialog
///   is unavailable (no Google Play services, or iOS), an explanation with
///   an "Open settings" button.
/// - Permission not decided: Android's own permission popup.
/// - Permission permanently denied: an explanation with "Open settings".
///
/// Returns true when the position can be read.
Future<bool> ensureLocationReady(BuildContext context) async {
  if (!await Geolocator.isLocationServiceEnabled()) {
    if (!context.mounted) return false;
    if (!await _turnOnLocation(context)) return false;
  }

  var permission = await Geolocator.checkPermission();

  if (permission == LocationPermission.denied) {
    // Shows Android's "Allow CivicBuddy to access this device's location?"
    permission = await Geolocator.requestPermission();
  }

  if (!context.mounted) return false;

  if (permission == LocationPermission.deniedForever) {
    await _explainAndOpenSettings(
      context,
      title: 'Allow location access',
      message:
          'Location permission is turned off for CivicBuddy. In Settings, '
          'open Permissions > Location and choose "Allow only while using '
          'the app".',
      openSettings: Geolocator.openAppSettings,
    );
    return false;
  }

  if (permission == LocationPermission.denied) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Location permission is needed to record where you are.'),
      ),
    );
    return false;
  }

  return true;
}

Future<bool> _turnOnLocation(BuildContext context) async {
  if (Platform.isAndroid) {
    try {
      // Android's one-tap "Turn on location?" dialog (Google Play services).
      final turnedOn = await location_settings.Location().requestService();

      if (!turnedOn && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Location is off. Turn it on to record your position.',
            ),
          ),
        );
      }
      return turnedOn;
    } catch (_) {
      // Dialog unavailable on this phone; explain instead.
    }
  }

  if (!context.mounted) return false;

  await _explainAndOpenSettings(
    context,
    title: 'Turn on location',
    message:
        'CivicBuddy needs your phone\'s location (GPS) to record where each '
        'survey point and interview is. Turn on Location, then try again.',
    openSettings: Geolocator.openLocationSettings,
  );
  return false;
}

Future<void> _explainAndOpenSettings(
  BuildContext context, {
  required String title,
  required String message,
  required Future<bool> Function() openSettings,
}) async {
  final open = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: Icon(
        Icons.location_on_outlined,
        size: 36,
        color: Theme.of(ctx).colorScheme.primary,
      ),
      title: Text(title, textAlign: TextAlign.center),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Not now'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Open settings'),
        ),
      ],
    ),
  );

  if (open == true) await openSettings();
}
