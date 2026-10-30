import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/theme_service.dart';
import 'start_survey_screen.dart';
import 'previous_surveys_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _userName = '';
  String _userEmail = '';

  @override
  void initState() {
    super.initState();
    _loadUserDetails();
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

    if (!mounted) return;
    setState(() {
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
                CircleAvatar(
                  radius: 32,
                  backgroundColor: colorScheme.primaryContainer,
                  child: Text(
                    _initials,
                    style: TextStyle(
                      color: colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.bold,
                      fontSize: 20,
                    ),
                  ),
                ),
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

  void _openScreen(Widget screen) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
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
            icon: CircleAvatar(
              radius: 17,
              backgroundColor: colorScheme.primaryContainer,
              child: Text(
                _initials,
                style: TextStyle(
                  color: colorScheme.onPrimaryContainer,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
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
