import 'dart:async';

import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

/// Area name used when it cannot be looked up (e.g. no internet).
const String unknownArea = 'Unknown Area';

class LocationService {
  /// Gets the user's current GPS position.
  ///
  /// Throws an exception if:
  /// - Location services are disabled
  /// - Location permission is denied
  /// - Location permission is permanently denied
  ///
  /// Waits for an accurate GPS fix (see [_accurateFix]); [onAccuracy] gets
  /// the accuracy in metres of the best fix so far, for showing progress.
  Future<Position> getCurrentLocation({
    void Function(double meters)? onAccuracy,
  }) async {
    // Check whether GPS/location service is enabled.
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();

    if (!serviceEnabled) {
      throw Exception('Location services are disabled. Please turn on GPS.');
    }

    // Check permission.
    LocationPermission permission = await Geolocator.checkPermission();

    // Request permission if necessary.
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();

      if (permission == LocationPermission.denied) {
        throw Exception('Location permission was denied.');
      }
    }

    // Permission permanently denied.
    if (permission == LocationPermission.deniedForever) {
      throw Exception(
        'Location permission is permanently denied. '
        'Please enable it from Settings.',
      );
    }

    return _accurateFix(onAccuracy);
  }

  // A fix this accurate (metres) is used at once; after [_settleTime] one
  // within [_goodEnough] is accepted; after [_maxWait] the best fix so far.
  static const double _target = 10;
  static const double _goodEnough = 25;
  static const Duration _settleTime = Duration(seconds: 8);
  static const Duration _maxWait = Duration(seconds: 25);

  /// Listens to live GPS (not the phone's last cached or Wi-Fi/tower
  /// estimate) until a precise fix arrives, reporting each fix's accuracy.
  Future<Position> _accurateFix(
    void Function(double meters)? onAccuracy,
  ) async {
    final started = DateTime.now();
    final done = Completer<Position>();
    Position? best;

    void finish() {
      if (done.isCompleted) return;
      if (best != null) {
        done.complete(best);
      } else {
        done.completeError(
          Exception(
            'Could not get a GPS fix. Move to an open area (away from tall '
            'buildings) and try again.',
          ),
        );
      }
    }

    final subscription =
        Geolocator.getPositionStream(
          locationSettings: AndroidSettings(
            accuracy: LocationAccuracy.best,
            intervalDuration: const Duration(seconds: 1),
            distanceFilter: 0,
          ),
        ).listen(
          (position) {
            // Skip a stale fix replayed from before this request.
            if (position.timestamp.isBefore(
              started.subtract(const Duration(seconds: 3)),
            )) {
              return;
            }

            if (best == null || position.accuracy < best!.accuracy) {
              best = position;
            }
            onAccuracy?.call(best!.accuracy);

            final waited = DateTime.now().difference(started);
            if (best!.accuracy <= _target ||
                (waited >= _settleTime && best!.accuracy <= _goodEnough)) {
              finish();
            }
          },
          onError: (Object e) {
            if (!done.isCompleted) done.completeError(e);
          },
        );

    // Accept a good-enough fix that arrived before the settle time.
    final settle = Timer(_settleTime, () {
      if (best != null && best!.accuracy <= _goodEnough) finish();
    });
    final giveUp = Timer(_maxWait, finish);

    try {
      return await done.future;
    } finally {
      settle.cancel();
      giveUp.cancel();
      await subscription.cancel();
    }
  }

  /// Converts latitude and longitude into a readable area name.
  Future<String> getAreaName({
    required double latitude,
    required double longitude,
  }) async {
    try {
      final placemarks = await placemarkFromCoordinates(latitude, longitude);

      if (placemarks.isEmpty) {
        return unknownArea;
      }

      final place = placemarks.first;

      // Prefer the most specific locality/sub-locality available.
      final area =
          [place.subLocality, place.locality, place.subAdministrativeArea]
              .where((value) => value != null && value.trim().isNotEmpty)
              .map((value) => value!.trim())
              .firstOrNull;

      if (area != null) {
        return area;
      }

      // Fallback to administrative area.
      if (place.administrativeArea != null &&
          place.administrativeArea!.trim().isNotEmpty) {
        return place.administrativeArea!.trim();
      }

      return unknownArea;
    } catch (_) {
      return unknownArea;
    }
  }
}
