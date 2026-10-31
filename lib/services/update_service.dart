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
  static const String _repositoryName = 'civicBuddy';

  static const String _latestReleaseUrl =
      'https://api.github.com/repos/'
      '$_repositoryOwner/$_repositoryName/releases/latest';

  // Web page that redirects to /releases/tag/<tag>. Unlike the API it has no
  // 60-requests-per-hour limit, which many phones behind one mobile-network
  // IP can exhaust.
  static const String _latestReleasePageUrl =
      'https://github.com/$_repositoryOwner/$_repositoryName/releases/latest';

  /// Updates are installed from an APK, which only works on Android.
  static bool get isSupported => Platform.isAndroid;

  static Future<UpdateInfo?> checkForUpdate() async {
    if (!isSupported) {
      return null;
    }

    try {
      final packageInfo = await PackageInfo.fromPlatform();

      // Version actually installed on the phone.
      final currentVersion = packageInfo.version.trim();

      return await _checkViaApi(currentVersion) ??
          await _checkViaReleasePage(currentVersion);
    } catch (e) {
      return null;
    }
  }

  /// Preferred source: includes the release notes.
  static Future<UpdateInfo?> _checkViaApi(String currentVersion) async {
    try {
      final response = await http
          .get(
            Uri.parse(_latestReleaseUrl),
            headers: const {
              'Accept': 'application/vnd.github+json',
              'Cache-Control': 'no-cache',
            },
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        return null;
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      return parseLatestRelease(data, currentVersion);
    } catch (e) {
      return null;
    }
  }

  /// Fallback when the API is rate-limited or unavailable.
  static Future<UpdateInfo?> _checkViaReleasePage(String currentVersion) async {
    final client = http.Client();

    try {
      var url = Uri.parse(_latestReleasePageUrl);

      // Follow redirects ourselves until one points at /releases/tag/<tag>.
      // Earlier hops can be "repository moved" redirects after a rename.
      for (var hop = 0; hop < 5; hop++) {
        final request = http.Request('GET', url)..followRedirects = false;

        final response = await client
            .send(request)
            .timeout(const Duration(seconds: 15));
        await response.stream.drain<void>();

        final location = response.headers['location'];

        if (location == null) {
          return null;
        }

        final info = parseReleaseRedirect(location, currentVersion);

        if (info != null) {
          return info;
        }

        url = url.resolve(location);
      }

      return null;
    } catch (e) {
      return null;
    } finally {
      client.close();
    }
  }

  /// Reads the tag from a ".../releases/tag/v1.2.3" redirect. CI attaches
  /// `garbage_detection_v<version>.apk` to every release, so the download URL
  /// can be built from the tag. Release notes are not available this way.
  static UpdateInfo? parseReleaseRedirect(
    String location,
    String currentVersion,
  ) {
    final match = RegExp(r'/releases/tag/([^/?#]+)').firstMatch(location);

    if (match == null) {
      return null;
    }

    final tag = Uri.decodeComponent(match.group(1)!);
    final latestVersion = _cleanVersion(tag);

    if (!RegExp(r'^\d+\.\d+\.\d+$').hasMatch(latestVersion)) {
      return null;
    }

    return UpdateInfo(
      updateAvailable: _isNewerVersion(latestVersion, currentVersion),
      currentVersion: currentVersion,
      latestVersion: latestVersion,
      downloadUrl:
          'https://github.com/$_repositoryOwner/$_repositoryName'
          '/releases/download/$tag/garbage_detection_v$latestVersion.apk',
      releaseNotes: '',
    );
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
