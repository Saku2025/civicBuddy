import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

class SurveyService {
  static final SupabaseClient _client = Supabase.instance.client;
  static const String photoBucket = 'survey-photos';

  static Future<String> uploadPhoto({
    required String surveyId,
    required int pointNumber,
    required File photoFile,
    required int photoIndex,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw Exception('You must be signed in to upload survey photos.');
    }
    if (!await photoFile.exists()) {
      throw Exception('A captured photo could not be found on this device.');
    }

    final safeSurveyId = surveyId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    final path =
        '${user.id}/$safeSurveyId/point_$pointNumber/photo_$photoIndex.jpg';

    await _client.storage
        .from(photoBucket)
        .upload(
          path,
          photoFile,
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
}
