import 'package:flutter_test/flutter_test.dart';

import 'package:my_app/services/update_service.dart';

Map<String, dynamic> _release(String tag, List<String> assetNames) => {
  'tag_name': tag,
  'body': 'Notes',
  'assets': [
    for (final name in assetNames)
      {'name': name, 'browser_download_url': 'https://example.com/$name'},
  ],
};

void main() {
  test('prefers garbage_detection_v<version>.apk', () {
    final info = UpdateService.parseLatestRelease(
      _release('v1.7.1', ['app-release.apk', 'garbage_detection_v1.7.1.apk']),
      '1.7.0',
    );

    expect(info!.updateAvailable, isTrue);
    expect(info.latestVersion, '1.7.1');
    expect(info.downloadUrl, endsWith('/garbage_detection_v1.7.1.apk'));
  });

  test('falls back to any APK when the expected name is missing', () {
    final info = UpdateService.parseLatestRelease(
      _release('v1.7.1', ['app-release.apk']),
      '1.7.0',
    );

    expect(info!.downloadUrl, endsWith('/app-release.apk'));
  });

  test('returns null when the release has no APK', () {
    final info = UpdateService.parseLatestRelease(
      _release('v1.7.1', ['notes.txt']),
      '1.7.0',
    );

    expect(info, isNull);
  });

  test('reads the version from the release page redirect', () {
    final info = UpdateService.parseReleaseRedirect(
      'https://github.com/Saku2025/civicBuddy/releases/tag/v1.7.4',
      '1.7.3',
    );

    expect(info!.updateAvailable, isTrue);
    expect(info.latestVersion, '1.7.4');
    expect(
      info.downloadUrl,
      'https://github.com/Saku2025/civicBuddy'
      '/releases/download/v1.7.4/garbage_detection_v1.7.4.apk',
    );
  });

  test('ignores redirects that are not a release tag', () {
    expect(
      UpdateService.parseReleaseRedirect(
        'https://github.com/Saku2025/civicBuddy/releases',
        '1.7.3',
      ),
      isNull,
    );
  });

  test('compares versions numerically', () {
    bool newer(String latest, String current) =>
        UpdateService.parseLatestRelease(
          _release('v$latest', ['a.apk']),
          current,
        )!.updateAvailable;

    expect(newer('1.10.0', '1.9.0'), isTrue);
    expect(newer('1.7.0', '1.7.0'), isFalse);
    expect(newer('1.6.2', '1.7.0'), isFalse);
    expect(newer('2.0.0', '1.7.0'), isTrue);
  });
}
