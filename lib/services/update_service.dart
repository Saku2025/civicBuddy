import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

class UpdateInfo {
  final bool updateAvailable;
  final String currentVersion;
  final String latestVersion;
  final String downloadUrl;
  final String releaseNotes;

  const UpdateInfo({
    required this.updateAvailable,
    required this.currentVersion,
    required this.latestVersion,
    required this.downloadUrl,
    required this.releaseNotes,
  });
}

class UpdateService {
  static const String _repositoryOwner = 'Saku2025';
  static const String _repositoryName = 'garbage-detection-App';

  static const String _latestReleaseUrl =
      'https://api.github.com/repos/'
      '$_repositoryOwner/$_repositoryName/releases/latest';

  static Future<UpdateInfo?> checkForUpdate() async {
    // Updates are installed from an APK, which only works on Android.
    if (!Platform.isAndroid) {
      return null;
    }

    try {
      final packageInfo = await PackageInfo.fromPlatform();

      // Version actually installed on the phone.
      final currentVersion = packageInfo.version.trim();

      // Get latest GitHub release.
      final response = await http.get(
        Uri.parse(_latestReleaseUrl),
        headers: const {
          'Accept': 'application/vnd.github+json',
          'Cache-Control': 'no-cache',
        },
      );

      if (response.statusCode != 200) {
        return null;
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      return parseLatestRelease(data, currentVersion);
    } catch (e) {
      return null;
    }
  }

  /// Reads a GitHub "latest release" response. Returns null when the
  /// release has no tag or no APK attached.
  static UpdateInfo? parseLatestRelease(
    Map<String, dynamic> data,
    String currentVersion,
  ) {
    final tagName = data['tag_name']?.toString() ?? '';

    if (tagName.isEmpty) {
      return null;
    }

    final latestVersion = _cleanVersion(tagName);

    // Find APK.
    final assets = data['assets'];

    if (assets is! List) {
      return null;
    }

    // Prefer garbage_detection_v<version>.apk (the name v1.4.0 and older
    // look for), but fall back to any other .apk attached to the release.
    final expectedName = 'garbage_detection_v$latestVersion.apk';

    String? downloadUrl;
    String? fallbackUrl;

    for (final asset in assets) {
      if (asset is! Map<String, dynamic>) {
        continue;
      }

      final name = (asset['name']?.toString() ?? '').toLowerCase();
      final url = asset['browser_download_url']?.toString() ?? '';

      if (url.isEmpty || !name.endsWith('.apk')) {
        continue;
      }

      if (name == expectedName.toLowerCase()) {
        downloadUrl = url;
        break;
      }

      fallbackUrl ??= url;
    }

    downloadUrl ??= fallbackUrl;

    if (downloadUrl == null) {
      return null;
    }

    return UpdateInfo(
      updateAvailable: _isNewerVersion(latestVersion, currentVersion),
      currentVersion: currentVersion,
      latestVersion: latestVersion,
      downloadUrl: downloadUrl,
      releaseNotes: data['body']?.toString().trim() ?? '',
    );
  }

  static String _cleanVersion(String version) {
    return version.trim().replaceFirst(RegExp(r'^v', caseSensitive: false), '');
  }

  static bool _isNewerVersion(String latest, String current) {
    final latestParts = _versionParts(latest);
    final currentParts = _versionParts(current);

    for (int i = 0; i < 3; i++) {
      if (latestParts[i] > currentParts[i]) {
        return true;
      }

      if (latestParts[i] < currentParts[i]) {
        return false;
      }
    }

    return false;
  }

  static List<int> _versionParts(String version) {
    final cleaned = _cleanVersion(version);
    final parts = cleaned.split('.');

    return List<int>.generate(3, (index) {
      if (index >= parts.length) {
        return 0;
      }

      return int.tryParse(parts[index].replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
    });
  }

  static Future<File> downloadApk(
    String downloadUrl, {
    void Function(int received, int total)? onProgress,
  }) async {
    final client = http.Client();

    try {
      final request = http.Request('GET', Uri.parse(downloadUrl));

      request.headers['Cache-Control'] = 'no-cache';

      final response = await client.send(request);

      if (response.statusCode != 200) {
        throw Exception('APK download failed: ${response.statusCode}');
      }

      final directory = await getTemporaryDirectory();

      final file = File('${directory.path}/garbage_detection_update.apk');

      if (await file.exists()) {
        await file.delete();
      }

      final sink = file.openWrite();

      int received = 0;
      final total = response.contentLength ?? -1;

      await for (final chunk in response.stream) {
        received += chunk.length;

        sink.add(chunk);

        onProgress?.call(received, total);
      }

      await sink.close();

      if (!await file.exists()) {
        throw Exception('Downloaded APK file was not found.');
      }

      final fileSize = await file.length();

      if (fileSize == 0) {
        throw Exception('Downloaded APK is empty.');
      }

      return file;
    } finally {
      client.close();
    }
  }
}
