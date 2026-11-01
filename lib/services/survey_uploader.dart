import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'draft_service.dart';
import 'survey_service.dart';

/// Uploads one finished survey: its photos first (resized up front, so the
/// total size is known), then the survey row. Used by Submit and by the
/// upload queue.
///
/// [submission] format (also how queued surveys are stored):
/// `survey_id`, `started_at`, `ended_at` (ISO dates), `citizens` (list of
/// interview documents) and `points`, each with `point_number`, `latitude`,
/// `longitude`, `area`, `captured_at`, `surveyor_answers` and `photo_paths`
/// (photo files on this phone).
class SurveyUploader extends ChangeNotifier {
  SurveyUploader(this.submission, {Map<String, String>? alreadyUploaded})
    : _uploaded = alreadyUploaded ?? {};

  final Map<String, dynamic> submission;

  // Photos already uploaded (key: point, index and local file), so a retry
  // skips them.
  final Map<String, String> _uploaded;

  String get surveyId => submission['survey_id'].toString();

  bool preparing = false;

  int photosDone = 0;

  int photosTotal = 0;

  int bytesDone = 0;

  int bytesTotal = 0;

  // Pause takes effect between photos; null while not paused.
  Completer<void>? _resumeGate;

  bool get paused => _resumeGate != null;

  void togglePause() {
    if (_resumeGate == null) {
      _resumeGate = Completer<void>();
    } else {
      _resumeGate!.complete();
      _resumeGate = null;
    }
    notifyListeners();
  }

  Future<void> _waitIfPaused() async {
    final gate = _resumeGate;
    if (gate != null) await gate.future;
  }

  static List<Map<String, dynamic>> _maps(Object? list) => [
    if (list is List)
      for (final item in list)
        if (item is Map) Map<String, dynamic>.from(item),
  ];

  static List<String> _photoPaths(Map<String, dynamic> point) => [
    if (point['photo_paths'] is List)
      for (final path in point['photo_paths'] as List) path.toString(),
  ];

  static String _key(Map<String, dynamic> point, int index, String path) =>
      '${point['point_number']}_${index}_$path';

  /// Uploads everything, then removes the survey's local copy (draft or
  /// queue entry). Throws on failure; calling again resumes.
  Future<void> run() async {
    final points = _maps(submission['points']);
    final citizens = _maps(submission['citizens']);

    final pending = <({Map<String, dynamic> point, int index, String path})>[
      for (final point in points)
        for (final (index, path) in _photoPaths(point).indexed)
          if (!_uploaded.containsKey(_key(point, index, path)))
            (point: point, index: index, path: path),
    ];

    preparing = true;
    photosDone = 0;
    photosTotal = pending.length;
    bytesDone = 0;
    bytesTotal = 0;
    _resumeGate = null;
    notifyListeners();

    Directory? uploadDir;
    try {
      // 1. Prepare (resize) every photo first, so the total size is known.
      final safeId = surveyId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
      uploadDir = Directory(
        '${(await getTemporaryDirectory()).path}/upload_$safeId',
      );
      await uploadDir.create(recursive: true);

      final prepared = <File>[];
      for (var n = 0; n < pending.length; n++) {
        await _waitIfPaused();
        final file = await SurveyService.prepareForUpload(
          File(pending[n].path),
          '${uploadDir.path}/photo_$n.jpg',
        );
        prepared.add(file);
        bytesTotal += await file.length();
        notifyListeners();
      }
      preparing = false;
      notifyListeners();

      // 2. Upload them one by one; Pause waits between photos.
      for (var n = 0; n < pending.length; n++) {
        await _waitIfPaused();
        final p = pending[n];
        _uploaded[_key(
          p.point,
          p.index,
          p.path,
        )] = await SurveyService.uploadPhoto(
          surveyId: surveyId,
          pointNumber: (p.point['point_number'] as num).toInt(),
          preparedFile: prepared[n],
          photoIndex: p.index + 1,
        );
        photosDone++;
        bytesDone += await prepared[n].length();
        notifyListeners();
      }

      // 3. The survey row, pointing at the uploaded photos.
      final pointDocuments = [
        for (final point in points)
          {
            for (final entry in point.entries)
              if (entry.key != 'photo_paths') entry.key: entry.value,
            'photos': [
              for (final (index, path) in _photoPaths(point).indexed)
                {
                  'storage_path': _uploaded[_key(point, index, path)],
                  'photo_number': index + 1,
                },
            ],
          },
      ];

      await SurveyService.saveSurvey(
        surveyId: surveyId,
        startedAt: DateTime.parse(submission['started_at'].toString()),
        endedAt: DateTime.parse(submission['ended_at'].toString()),
        surveyData: {
          'points': pointDocuments,
          'citizens': citizens,
          // Single-interview field read by app versions up to 1.7.4.
          'citizen': citizens.isEmpty ? null : citizens.first,
        },
      );

      // Submitted: the local copy (and its photos) is no longer needed.
      await DraftService.delete(surveyId);
    } finally {
      try {
        await uploadDir?.delete(recursive: true);
      } catch (_) {
        // Temp files; the OS clears them eventually.
      }
      preparing = false;
      _resumeGate?.complete();
      _resumeGate = null;
      notifyListeners();
    }
  }
}
