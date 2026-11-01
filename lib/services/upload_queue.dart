import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'auth_service.dart';
import 'draft_service.dart';
import 'survey_uploader.dart';

enum NetworkStatus { offline, wifi, mobile }

/// Finished surveys waiting to be uploaded (no internet at submit, or the
/// surveyor chose "Save to queue"). Stored on the phone next to the drafts,
/// and uploaded automatically whenever the phone is on Wi-Fi while the app
/// is running.
class UploadQueue {
  /// Bumped whenever the queue changes, so screens can reload.
  static final ValueNotifier<int> changes = ValueNotifier(0);

  /// The queued survey being uploaded right now, if any.
  static final ValueNotifier<SurveyUploader?> current = ValueNotifier(null);

  // Uploads run one after another.
  static Future<void> _chain = Future.value();

  static StreamSubscription<List<ConnectivityResult>>? _wifiWatch;

  /// Whether the phone can reach the server, and over which network.
  static Future<NetworkStatus> checkNetwork() async {
    final results = await Connectivity().checkConnectivity();
    if (results.every((r) => r == ConnectivityResult.none)) {
      return NetworkStatus.offline;
    }

    // Connected to a network is not the same as having internet.
    try {
      final host = Uri.tryParse(dotenv.env['SUPABASE_URL'] ?? '')?.host;
      final found = await InternetAddress.lookup(
        (host == null || host.isEmpty) ? 'supabase.co' : host,
      ).timeout(const Duration(seconds: 6));
      if (found.isEmpty) return NetworkStatus.offline;
    } catch (_) {
      return NetworkStatus.offline;
    }

    return results.contains(ConnectivityResult.wifi) ||
            results.contains(ConnectivityResult.ethernet)
        ? NetworkStatus.wifi
        : NetworkStatus.mobile;
  }

  /// Adds a finished survey (see [SurveyUploader] for the format). Replaces
  /// its draft, keeping the photos where they are.
  static Future<void> add(Map<String, dynamic> submission) async {
    final userId = AuthService.getCurrentUser()?.id;
    if (userId == null) throw Exception('You must be signed in.');

    final surveyId = submission['survey_id'].toString();
    await DraftService.save(surveyId, {
      'version': 1,
      'user_id': userId,
      'survey_id': surveyId,
      'started_at': submission['started_at'],
      'updated_at': DateTime.now().toIso8601String(),
      'queued': true,
      'submission': submission,
    });
    changes.value++;
  }

  /// The signed-in user's queued surveys, most recently queued first.
  static Future<List<Map<String, dynamic>>> list() async {
    final userId = AuthService.getCurrentUser()?.id;
    if (userId == null) return const [];
    return DraftService.list(userId, queued: true);
  }

  /// Deletes queued surveys and their photos (not the one uploading now).
  static Future<void> delete(Iterable<String> surveyIds) async {
    for (final id in surveyIds.toList()) {
      if (current.value?.surveyId == id) continue;
      await DraftService.delete(id);
    }
    changes.value++;
  }

  /// Uploads the given queued surveys one after another. Returns an error
  /// message per survey that failed (empty when all were uploaded).
  static Future<List<String>> upload(Iterable<String> surveyIds) {
    final ids = surveyIds.toList();
    final result = _chain.then((_) => _uploadNow(ids));
    _chain = result.then((_) {}, onError: (_) {});
    return result;
  }

  static Future<List<String>> _uploadNow(List<String> ids) async {
    final errors = <String>[];
    final queued = {
      for (final entry in await list()) entry['survey_id'].toString(): entry,
    };

    for (final id in ids) {
      // Already uploaded (e.g. automatically) or deleted meanwhile.
      final submission = queued[id]?['submission'];
      if (submission is! Map) continue;

      final uploader = SurveyUploader(Map<String, dynamic>.from(submission));
      current.value = uploader;
      try {
        await uploader.run();
      } catch (e) {
        errors.add('$id: ${e.toString().replaceFirst('Exception: ', '')}');
      } finally {
        current.value = null;
        changes.value++;
      }
    }
    return errors;
  }

  /// Uploads the whole queue if the phone is on Wi-Fi.
  static Future<void> uploadAllOnWifi() async {
    try {
      if (AuthService.getCurrentUser() == null) return;
      final queued = await list();
      if (queued.isEmpty) return;
      if (await checkNetwork() != NetworkStatus.wifi) return;
      await upload(queued.map((q) => q['survey_id'].toString()));
    } catch (_) {
      // Tried again on the next Wi-Fi connection or app start.
    }
  }

  /// Uploads the queue now (if on Wi-Fi) and whenever Wi-Fi connects.
  static void startAutoUpload() {
    if (_wifiWatch != null) return;
    _wifiWatch = Connectivity().onConnectivityChanged.listen((results) {
      if (results.contains(ConnectivityResult.wifi)) uploadAllOnWifi();
    });
    uploadAllOnWifi();
  }
}
