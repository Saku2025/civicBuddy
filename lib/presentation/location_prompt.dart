import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';

// Native "Turn on location?" dialog, implemented in MainActivity.kt.
const MethodChannel _locationSettings = MethodChannel(
  'civicbuddy/location_settings',
);

/// Makes sure location permission is granted and GPS is on before reading
/// the position, using Android's own popups:
///
/// 1. Permission not decided: "Allow CivicBuddy to access this device's
///    location?" (Android shows this only until the user has answered).
/// 2. GPS off: Google Play services' "Turn on location?" (one tap).
/// 3. Only approximate location allowed: "Change to precise location?".
///
/// Only when a native popup cannot be used (permission blocked for good, or
/// no Google Play services) does it explain and offer "Open settings".
///
/// Returns true when the position can be read.
Future<bool> ensureLocationReady(BuildContext context) async {
  var permission = await Geolocator.checkPermission();

  if (permission == LocationPermission.denied) {
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

  if (!await Geolocator.isLocationServiceEnabled()) {
    if (!context.mounted) return false;
    if (!await _turnOnLocation(context)) return false;
  }

  if (!context.mounted) return false;
  return _ensurePrecise(context);
}

/// Android 12+ lets the user allow only "Approximate" location, which is
/// shifted by up to ~2 km. Ask Android to upgrade to "Precise" (its own
/// popup), or explain how in Settings.
Future<bool> _ensurePrecise(BuildContext context) async {
  if (await Geolocator.getLocationAccuracy() !=
      LocationAccuracyStatus.reduced) {
    return true;
  }

  // Asking again shows Android's "Change to precise location?" popup.
  await Geolocator.requestPermission();
  if (await Geolocator.getLocationAccuracy() !=
      LocationAccuracyStatus.reduced) {
    return true;
  }

  if (!context.mounted) return false;
  await _explainAndOpenSettings(
    context,
    title: 'Turn on precise location',
    message:
        'CivicBuddy only has approximate location, which can be up to 2 km '
        'off. In Settings, open Permissions > Location and turn on "Use '
        'precise location".',
    openSettings: Geolocator.openAppSettings,
  );
  return false;
}

Future<bool> _turnOnLocation(BuildContext context) async {
  if (Platform.isAndroid) {
    String? outcome;

    try {
      outcome = await _locationSettings.invokeMethod<String>('requestTurnOn');
    } on PlatformException {
      outcome = 'unavailable';
    } on MissingPluginException {
      outcome = 'unavailable';
    }

    if (outcome == 'on') return true;

    if (outcome == 'declined') {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Location is off. Turn it on to record your position.',
            ),
          ),
        );
      }
      return false;
    }
  }

  // No Google Play services (or not Android): explain instead.
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
