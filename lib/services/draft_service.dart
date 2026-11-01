import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Unfinished surveys kept on the phone so they survive leaving the screen,
/// closing the app or the app being killed.
///
/// Each draft is a folder `survey_drafts/<surveyId>/` in the app's private
/// documents directory with `draft.json` and a `photos/` folder holding
/// copies of the captured photos (the camera's cache folder can be cleared
/// by Android).
class DraftService {
  // Saves and deletes run one after another, and reads wait for them, so a
  // quick Back right after a change never sees a stale or half-written file.
  static Future<void> _queue = Future.value();

  static Future<T> _serialized<T>(Future<T> Function() task) {
    final result = _queue.then((_) => task());
    _queue = result.then((_) {}, onError: (_) {});
    return result;
  }

  static Future<Directory> _root() async {
    final documents = await getApplicationDocumentsDirectory();
    return Directory('${documents.path}/survey_drafts');
  }

  static Future<Directory> _folderFor(String surveyId) async {
    final safeId = surveyId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    return Directory('${(await _root()).path}/$safeId');
  }

  /// Copies a captured photo into the draft's folder and returns the copy's
  /// path, which stays valid until the draft is submitted or deleted.
  static Future<String> storePhoto(String surveyId, String sourcePath) async {
    final folder = Directory('${(await _folderFor(surveyId)).path}/photos');
    await folder.create(recursive: true);

    final copy = await File(
      sourcePath,
    ).copy('${folder.path}/photo_${DateTime.now().microsecondsSinceEpoch}.jpg');

    // The camera's own temporary file is no longer needed.
    try {
      await File(sourcePath).delete();
    } catch (_) {}

    return copy.path;
  }

  /// Deletes a photo copy belonging to a draft (e.g. its point was removed).
  static Future<void> deletePhoto(String path) async {
    final root = (await _root()).path;
    if (!path.startsWith(root)) return;

    try {
      await File(path).delete();
    } catch (_) {}
  }

  /// Writes the draft (replacing any previous save of the same survey).
  static Future<void> save(String surveyId, Map<String, dynamic> data) {
    return _serialized(() async {
      final folder = await _folderFor(surveyId);
      await folder.create(recursive: true);

      // Write a temporary file first so a crash never leaves broken JSON.
      final temp = File('${folder.path}/draft.json.tmp');
      await temp.writeAsString(jsonEncode(data), flush: true);
      await temp.rename('${folder.path}/draft.json');
    });
  }

  /// Removes a draft and its photo copies.
  static Future<void> delete(String surveyId) {
    return _serialized(() async {
      final folder = await _folderFor(surveyId);
      if (await folder.exists()) await folder.delete(recursive: true);
    });
  }

  /// The signed-in user's drafts, most recently edited first.
  static Future<List<Map<String, dynamic>>> list(String userId) {
    return _serialized(() async {
      final root = await _root();
      if (!await root.exists()) return <Map<String, dynamic>>[];

      final drafts = <Map<String, dynamic>>[];

      await for (final entity in root.list()) {
        if (entity is! Directory) continue;

        final file = File('${entity.path}/draft.json');
        if (!await file.exists()) continue;

        try {
          final data = jsonDecode(await file.readAsString());
          if (data is Map<String, dynamic> && data['user_id'] == userId) {
            drafts.add(data);
          }
        } catch (_) {
          // Skip a damaged draft rather than failing the whole list.
        }
      }

      drafts.sort(
        (a, b) => (b['updated_at']?.toString() ?? '').compareTo(
          a['updated_at']?.toString() ?? '',
        ),
      );
      return drafts;
    });
  }
}
