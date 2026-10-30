import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'presentation/home_screen.dart';
import 'presentation/login_screen.dart';
import 'presentation/update_dialog.dart';
import 'services/theme_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await dotenv.load(fileName: '.env');

  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL']!,
    publishableKey: dotenv.env['SUPABASE_PUBLISHABLE_KEY']!,
  );

  await ThemeService.init();

  runApp(const CivicBuddyApp());
}

class CivicBuddyApp extends StatelessWidget {
  const CivicBuddyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeService.themeMode,
      builder: (context, themeMode, child) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'CivicBuddy',
          themeMode: themeMode,
          theme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.light,
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF256D3F),
              onPrimary: Colors.white,
              primaryContainer: Color(0xFFE0F0E5),
              onPrimaryContainer: Color(0xFF183C28),
              secondary: Color(0xFF4CAF70),
              onSecondary: Colors.white,
              surface: Colors.white,
              onSurface: Color(0xFF183C28),
              surfaceContainerHighest: Color(0xFFEFF4F0),
              error: Color(0xFFBA1A1A),
              onError: Colors.white,
            ),
            scaffoldBackgroundColor: const Color(0xFFF5F8F5),
            appBarTheme: const AppBarTheme(
              backgroundColor: Colors.transparent,
              foregroundColor: Color(0xFF183C28),
              elevation: 0,
            ),
            cardTheme: const CardThemeData(color: Colors.white, elevation: 0),
          ),
          darkTheme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.dark,
            colorScheme: const ColorScheme.dark(
              primary: Color(0xFF65C98A),
              onPrimary: Color(0xFF00391B),
              primaryContainer: Color(0xFF1F4D32),
              onPrimaryContainer: Color(0xFFB9F5C8),
              secondary: Color(0xFF8ED5A5),
              onSecondary: Color(0xFF00391B),
              surface: Color(0xFF18221C),
              onSurface: Color(0xFFF1F7F3),
              surfaceContainerHighest: Color(0xFF26352C),
              error: Color(0xFFFFB4AB),
              onError: Color(0xFF690005),
            ),
            scaffoldBackgroundColor: const Color(0xFF0F1712),
            appBarTheme: const AppBarTheme(
              backgroundColor: Colors.transparent,
              foregroundColor: Color(0xFFF1F7F3),
              elevation: 0,
            ),
            cardTheme: const CardThemeData(
              color: Color(0xFF18221C),
              elevation: 0,
            ),
          ),
          home: const AuthGate(),
        );
      },
    );
  }
}

/// Responds to Supabase login/logout events, including Google OAuth callbacks.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  @override
  void initState() {
    super.initState();

    // Check for a newer release once per launch, signed in or not, so users
    // who cannot sign in still get fixes.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) checkForAppUpdate(context);
    });
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: Supabase.instance.client.auth.onAuthStateChange,
      builder: (context, snapshot) {
        final session =
            snapshot.data?.session ??
            Supabase.instance.client.auth.currentSession;

        if (session != null) {
          return const HomeScreen();
        }

        return const LoginScreen();
      },
    );
  }
}
