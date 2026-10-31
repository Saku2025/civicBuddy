import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';

import '../services/update_service.dart';

/// Checks GitHub for a newer release and, if there is one, offers to
/// download and install it.
///
/// The automatic check at startup stays silent otherwise; with [manual]
/// (the About screen's button) the user is also told when they are up to
/// date or the check failed.
Future<void> checkForAppUpdate(
  BuildContext context, {
  bool manual = false,
}) async {
  final updateInfo = await UpdateService.checkForUpdate();

  if (!context.mounted) return;

  if (updateInfo == null || !updateInfo.updateAvailable) {
    if (manual) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            updateInfo == null
                ? (UpdateService.isSupported
                      ? 'Could not check for updates. Check your internet '
                            'connection and try again.'
                      : 'Updates are only available in the Android app.')
                : 'You are on the latest version '
                      '(v${updateInfo.currentVersion}).',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
    return;
  }

  final shouldUpdate = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) {
      final colorScheme = Theme.of(dialogContext).colorScheme;

      return AlertDialog(
        icon: Icon(
          Icons.system_update_outlined,
          size: 42,
          color: colorScheme.primary,
        ),
        title: const Text(
          'New Update Available',
          textAlign: TextAlign.center,
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'A new version of CivicBuddy is available.',
                textAlign: TextAlign.center,
                style: TextStyle(color: colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              _VersionRow(
                label: 'Current',
                version: updateInfo.currentVersion,
                background: colorScheme.primaryContainer,
                labelColor: colorScheme.onPrimaryContainer,
                versionColor: colorScheme.onPrimaryContainer,
              ),
              const SizedBox(height: 8),
              _VersionRow(
                label: 'New version',
                version: updateInfo.latestVersion,
                background: colorScheme.surfaceContainerHighest,
                labelColor: colorScheme.onSurfaceVariant,
                versionColor: colorScheme.primary,
              ),
              if (updateInfo.releaseNotes.isNotEmpty) ...[
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'What’s new',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _plainReleaseNotes(updateInfo.releaseNotes),
                    maxLines: 5,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Later'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.download_outlined),
            label: const Text('Update Now'),
          ),
        ],
      );
    },
  );

  if (shouldUpdate == true && context.mounted) {
    await _downloadAndInstallUpdate(context, updateInfo);
  }
}

/// GitHub release notes are Markdown; show them as plain text, skipping
/// headings (the dialog already has its own title).
String _plainReleaseNotes(String markdown) {
  return markdown
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty && !line.startsWith('#'))
      .map(
        (line) => line
            .replaceFirst(RegExp(r'^[-*]\s+'), '• ')
            .replaceAll(RegExp(r'\*\*|__|`'), ''),
      )
      .join('\n');
}

Future<void> _downloadAndInstallUpdate(
  BuildContext context,
  UpdateInfo updateInfo,
) async {
  final progress = ValueNotifier<double>(0);
  final navigator = Navigator.of(context, rootNavigator: true);
  final messenger = ScaffoldMessenger.of(context);

  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) {
      return PopScope(
        canPop: false,
        child: AlertDialog(
          icon: const Icon(Icons.download_outlined, size: 40),
          title: const Text(
            'Downloading Update',
            textAlign: TextAlign.center,
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          content: ValueListenableBuilder<double>(
            valueListenable: progress,
            builder: (context, value, _) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Downloading v${updateInfo.latestVersion}...',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  LinearProgressIndicator(value: value > 0 ? value : null),
                  const SizedBox(height: 12),
                  Text(
                    value > 0
                        ? '${(value * 100).toStringAsFixed(0)}%'
                        : 'Starting download...',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ],
              );
            },
          ),
        ),
      );
    },
  );

  try {
    final apkFile = await UpdateService.downloadApk(
      updateInfo.downloadUrl,
      onProgress: (received, total) {
        if (total > 0) {
          progress.value = received / total;
        }
      },
    );

    // Close download dialog.
    navigator.pop();

    // Open Android APK installer.
    final result = await OpenFilex.open(
      apkFile.path,
      type: 'application/vnd.android.package-archive',
    );

    if (result.type != ResultType.done) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Could not open installer: ${result.message}'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  } catch (e) {
    // Close download dialog.
    navigator.pop();

    messenger.showSnackBar(
      SnackBar(
        content: Text(
          'Update failed: ${e.toString().replaceFirst('Exception: ', '')}',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

class _VersionRow extends StatelessWidget {
  const _VersionRow({
    required this.label,
    required this.version,
    required this.background,
    required this.labelColor,
    required this.versionColor,
  });

  final String label;
  final String version;
  final Color background;
  final Color labelColor;
  final Color versionColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: labelColor)),
          Text(
            'v$version',
            style: TextStyle(fontWeight: FontWeight.bold, color: versionColor),
          ),
        ],
      ),
    );
  }
}
