import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'update_dialog.dart';

class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  late final Future<PackageInfo> _packageInfo = PackageInfo.fromPlatform();

  bool _isChecking = false;

  static final Uri _websiteUrl = Uri.parse('https://civicbuddy.onrender.com/');

  Future<void> _openWebsite() async {
    final opened = await launchUrl(
      _websiteUrl,
      mode: LaunchMode.externalApplication,
    );

    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not open civicbuddy.onrender.com'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _checkForUpdates() async {
    if (_isChecking) return;

    setState(() => _isChecking = true);

    try {
      await checkForAppUpdate(context, manual: true);
    } finally {
      if (mounted) setState(() => _isChecking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('About')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: Image.asset(
                  'assets/icon/app_icon.png',
                  width: 96,
                  height: 96,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'CivicBuddy',
              textAlign: TextAlign.center,
              style: textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Keep your surroundings clean and green',
              textAlign: TextAlign.center,
              style: textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 28),
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
                side: BorderSide(color: colorScheme.outlineVariant),
              ),
              child: FutureBuilder<PackageInfo>(
                future: _packageInfo,
                builder: (context, snapshot) {
                  final info = snapshot.data;

                  return Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.info_outline),
                        title: const Text('Version'),
                        trailing: Text(
                          info == null ? '…' : 'v${info.version}',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.tag),
                        title: const Text('Build'),
                        trailing: Text(info?.buildNumber ?? '…'),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.language),
                        title: const Text('Website'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'civicbuddy.onrender.com',
                              style: TextStyle(
                                color: colorScheme.primary,
                                fontWeight: FontWeight.w600,
                                decoration: TextDecoration.underline,
                                decorationColor: colorScheme.primary,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(
                              Icons.open_in_new,
                              size: 16,
                              color: colorScheme.primary,
                            ),
                          ],
                        ),
                        onTap: _openWebsite,
                      ),
                    ],
                  );
                },
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 52,
              child: FilledButton.icon(
                onPressed: _isChecking ? null : _checkForUpdates,
                icon: _isChecking
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.system_update_outlined),
                label: Text(
                  _isChecking ? 'Checking for updates…' : 'Check for updates',
                ),
              ),
            ),
            const SizedBox(height: 28),
            Text(
              '© ${DateTime.now().year} CivicBuddy',
              textAlign: TextAlign.center,
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
