import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SurveyService {
  static final SupabaseClient _client = Supabase.instance.client;
  static const String photoBucket = 'survey-photos';

  // Full-resolution camera photos are several MB; ~2048 px at quality 85 is
  // about 0.5-1 MB and still sharp. Saves mobile data on submit.
  static const int _uploadMinSide = 2048;
  static const int _uploadQuality = 85;

  /// JPEG bytes to upload: a resized copy (orientation fixed, metadata such
  /// as embedded GPS stripped), or the original file if resizing fails.
  static Future<Uint8List> _compressForUpload(File photoFile) async {
    try {
      final compressed = await FlutterImageCompress.compressWithFile(
        photoFile.path,
        minWidth: _uploadMinSide,
        minHeight: _uploadMinSide,
        quality: _uploadQuality,
      );
      if (compressed != null && compressed.isNotEmpty) return compressed;
    } catch (_) {
      // Fall through to the original photo.
    }
    return photoFile.readAsBytes();
  }

  /// Writes the resized upload copy of [photoFile] to [outPath], so its exact
  /// size is known before uploading starts.
  static Future<File> prepareForUpload(File photoFile, String outPath) async {
    if (!await photoFile.exists()) {
      throw Exception('A captured photo could not be found on this device.');
    }
    return File(outPath).writeAsBytes(await _compressForUpload(photoFile));
  }

  /// Uploads a photo prepared by [prepareForUpload].
  static Future<String> uploadPhoto({
    required String surveyId,
    required int pointNumber,
    required File preparedFile,
    required int photoIndex,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw Exception('You must be signed in to upload survey photos.');
    }

    final safeSurveyId = surveyId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    final path =
        '${user.id}/$safeSurveyId/point_$pointNumber/photo_$photoIndex.jpg';

    await _client.storage
        .from(photoBucket)
        .uploadBinary(
          path,
          await preparedFile.readAsBytes(),
          fileOptions: const FileOptions(
            upsert: true,
            contentType: 'image/jpeg',
          ),
        );
    return path;
  }

  static Future<void> saveSurvey({
    required String surveyId,
    required DateTime startedAt,
    required DateTime endedAt,
    required Map<String, dynamic> surveyData,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw Exception('You must be signed in to save a survey.');
    }

    await _client.from('surveys').upsert({
      'user_id': user.id,
      'survey_id': surveyId,
      'status': 'completed',
      'started_at': startedAt.toUtc().toIso8601String(),
      'ended_at': endedAt.toUtc().toIso8601String(),
      'survey_data': surveyData,
    }, onConflict: 'user_id,survey_id');
  }

  static Future<List<Map<String, dynamic>>> getPreviousSurveys() async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw Exception('You must be signed in to view surveys.');
    }
    final rows = await _client
        .from('surveys')
        .select(
          'id, survey_id, status, started_at, ended_at, created_at, survey_data',
        )
        .eq('user_id', user.id)
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(rows);
  }

  /// Storage paths of every photo in a survey row from [getPreviousSurveys].
  static List<String> photoPathsOf(Map<String, dynamic> survey) {
    final data = survey['survey_data'];
    final points = data is Map ? data['points'] : null;

    return [
      if (points is List)
        for (final point in points.whereType<Map>())
          if (point['photos'] is List)
            for (final photo in (point['photos'] as List).whereType<Map>())
              if ((photo['storage_path']?.toString() ?? '').isNotEmpty)
                photo['storage_path'].toString(),
    ];
  }

  /// Permanently deletes a survey and its photos.
  ///
  /// The row is deleted first: if Supabase refuses (no DELETE policy), it
  /// throws and nothing is removed. Photos are removed afterwards; a failure
  /// there only leaves unused files in storage.
  static Future<void> deleteSurvey(Map<String, dynamic> survey) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw Exception('You must be signed in to delete surveys.');
    }

    // Row-level security silently skips rows it does not allow, so ask for
    // the deleted rows back to know whether anything was deleted.
    final deleted = await _client
        .from('surveys')
        .delete()
        .eq('id', survey['id'])
        .eq('user_id', user.id)
        .select('id');

    if (deleted.isEmpty) {
      throw Exception(
        'This survey could not be deleted. Deleting surveys is not enabled '
        'in the database yet.',
      );
    }

    final paths = photoPathsOf(survey);
    if (paths.isEmpty) return;

    try {
      await _client.storage.from(photoBucket).remove(paths);
    } catch (_) {
      // The survey is already gone; leftover files are only wasted storage.
    }
  }
}
