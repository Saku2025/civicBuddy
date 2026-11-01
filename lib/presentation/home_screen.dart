import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/draft_service.dart';
import '../services/theme_service.dart';
import '../services/upload_queue.dart';
import 'about_screen.dart';
import 'drafts_screen.dart';
import 'start_survey_screen.dart';
import 'upload_queue_screen.dart';
import 'previous_surveys_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _userName = '';
  String _userEmail = '';
  // Google profile picture, if the account has one.
  String? _photoUrl;
  // Unfinished surveys saved on this phone.
  int _draftCount = 0;
  // Finished surveys waiting to be uploaded.
  int _queueCount = 0;

  @override
  void initState() {
    super.initState();
    _loadUserDetails();
    _loadDraftCount();
    UploadQueue.changes.addListener(_loadDraftCount);
    // Upload queued surveys now and whenever Wi-Fi connects.
    UploadQueue.startAutoUpload();
  }

  @override
  void dispose() {
    UploadQueue.changes.removeListener(_loadDraftCount);
    super.dispose();
  }

  Future<void> _loadDraftCount() async {
    final userId = AuthService.getCurrentUser()?.id;
    if (userId == null) return;

    final drafts = await DraftService.list(userId);
    final queued = await UploadQueue.list();
    if (mounted) {
      setState(() {
        _draftCount = drafts.length;
        _queueCount = queued.length;
      });
    }
  }

  void _loadUserDetails() {
    final user = AuthService.getCurrentUser();
    if (user == null) return;

    final metadata = user.userMetadata ?? <String, dynamic>{};
    final email = user.email?.trim() ?? '';
    final name =
        (metadata['name'] ??
                metadata['full_name'] ??
                metadata['display_name'] ??
                '')
            .toString()
            .trim();
    final photoUrl = (metadata['avatar_url'] ?? metadata['picture'] ?? '')
        .toString()
        .trim();

    if (!mounted) return;
    setState(() {
      _photoUrl = photoUrl.isEmpty ? null : photoUrl;
      _userEmail = email;
      _userName = name.isNotEmpty
          ? name
          : (email.isNotEmpty ? email.split('@').first : 'User');
    });
  }

  String get _initials {
    final name = _userName.trim();
    if (name.isEmpty) return 'U';
    final parts = name
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.length == 1) {
      return parts.first.substring(0, 1).toUpperCase();
    }
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  /// Google photo, with the initials underneath while it loads or if it
  /// fails.
  Widget _avatar({required double radius, required double fontSize}) {
    final colorScheme = Theme.of(context).colorScheme;
    final photoUrl = _photoUrl;

    return CircleAvatar(
      radius: radius,
      backgroundColor: colorScheme.primaryContainer,
      foregroundImage: photoUrl == null ? null : NetworkImage(photoUrl),
      onForegroundImageError: photoUrl == null ? null : (_, _) {},
      child: Text(
        _initials,
        style: TextStyle(
          color: colorScheme.onPrimaryContainer,
          fontWeight: FontWeight.bold,
          fontSize: fontSize,
        ),
      ),
    );
  }

  Future<void> _showProfileMenu() async {
    final colorScheme = Theme.of(context).colorScheme;
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: colorScheme.surface,
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _avatar(radius: 32, fontSize: 20),
                const SizedBox(height: 12),
                Text(
                  _userName.isEmpty ? 'User profile' : _userName,
                  style: Theme.of(sheetContext).textTheme.titleLarge,
                ),
                const SizedBox(height: 4),
                Text(
                  _userEmail.isEmpty ? 'No email available' : _userEmail,
                  textAlign: TextAlign.center,
                  style: Theme.of(sheetContext).textTheme.bodyMedium,
                ),
                const SizedBox(height: 20),
                ListTile(
                  leading: const Icon(Icons.palette_outlined),
                  title: const Text('Appearance'),
                  subtitle: const Text('Change app theme'),
                  onTap: () => Navigator.pop(sheetContext, 'appearance'),
                ),
                ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: const Text('About'),
                  subtitle: const Text('App version and updates'),
                  onTap: () => Navigator.pop(sheetContext, 'about'),
                ),
                const Divider(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: colorScheme.errorContainer,
                      foregroundColor: colorScheme.onErrorContainer,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: () => Navigator.pop(sheetContext, 'logout'),
                    icon: const Icon(Icons.logout),
                    label: const Text('Sign out'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (!mounted) return;
    if (choice == 'appearance') {
      await _showThemeSelector();
    } else if (choice == 'about') {
      _openScreen(const AboutScreen());
    } else if (choice == 'logout') {
      await _logout();
    }
  }

  Future<void> _logout() async {
    try {
      // AuthGate swaps to LoginScreen on sign-out. Do not replace the route
      // stack here: removing AuthGate would stop the next sign-in from ever
      // reaching HomeScreen.
      await AuthService.signOut();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Unable to sign out: $e')));
    }
  }

  Future<void> _showThemeSelector() async {
    final selectedTheme = await showDialog<ThemeMode>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Appearance'),
        content: ValueListenableBuilder<ThemeMode>(
          valueListenable: ThemeService.themeMode,
          builder: (context, currentTheme, _) => RadioGroup<ThemeMode>(
            groupValue: currentTheme,
            onChanged: (value) => Navigator.pop(dialogContext, value),
            child: const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                RadioListTile<ThemeMode>(
                  value: ThemeMode.system,
                  title: Text('System'),
                  subtitle: Text('Follow device setting'),
                ),
                RadioListTile<ThemeMode>(
                  value: ThemeMode.light,
                  title: Text('Light'),
                ),
                RadioListTile<ThemeMode>(
                  value: ThemeMode.dark,
                  title: Text('Dark'),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (selectedTheme != null) {
      await ThemeService.setTheme(selectedTheme);
    }
  }

  Future<void> _openScreen(Widget screen) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
    // A survey may have been saved to, resumed from or removed from Drafts.
    _loadDraftCount();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'CivicBuddy',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            onPressed: _showProfileMenu,
            tooltip: 'Profile and sign out',
            icon: _avatar(radius: 17, fontSize: 12),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Survey Management',
                style: Theme.of(context).textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'Start a new survey or review your previous surveys.',
                style: Theme.of(context).textTheme.bodyLarge
                    ?.copyWith(color: colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 24),
              _SurveyActionCard(
                icon: Icons.play_circle_outline,
                title: 'Start Survey',
                subtitle: 'Create a new survey',
                onTap: () => _openScreen(const StartSurveyScreen()),
              ),
              const SizedBox(height: 16),
              _SurveyActionCard(
                icon: Icons.edit_note,
                title: _draftCount == 0 ? 'Drafts' : 'Drafts ($_draftCount)',
                subtitle: _draftCount == 0
                    ? 'Unfinished surveys are saved here'
                    : 'Continue or delete unfinished surveys',
                onTap: () => _openScreen(const DraftsScreen()),
              ),
              const SizedBox(height: 16),
              _SurveyActionCard(
                icon: Icons.cloud_upload_outlined,
                title: _queueCount == 0
                    ? 'Upload queue'
                    : 'Upload queue ($_queueCount)',
                subtitle: _queueCount == 0
                    ? 'Finished surveys waiting for internet'
                    : 'Waiting to upload · automatic on Wi-Fi',
                onTap: () => _openScreen(const UploadQueueScreen()),
              ),
              const SizedBox(height: 16),
              _SurveyActionCard(
                icon: Icons.history,
                title: 'Previous Surveys',
                subtitle: 'View your saved survey history',
                onTap: () => _openScreen(const PreviousSurveysScreen()),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SurveyActionCard extends StatelessWidget {
  const _SurveyActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, color: colorScheme.primary, size: 29),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodyMedium
                          ?.copyWith(color: colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}
