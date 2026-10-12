import 'package:supabase_flutter/supabase_flutter.dart';

class AuthService {
  static final SupabaseClient _supabase = Supabase.instance.client;

  static bool get isLoggedIn => _supabase.auth.currentSession != null;

  static User? getCurrentUser() => _supabase.auth.currentUser;

  static Future<void> signUp({
    required String email,
    required String password,
    String? name,
  }) async {
    final response = await _supabase.auth.signUp(
      email: email,
      password: password,
      data: {if (name != null && name.isNotEmpty) 'name': name},
    );

    if (response.user == null) {
      throw Exception('Signup failed. Please try again.');
    }
  }

  static Future<void> signIn({
    required String email,
    required String password,
  }) async {
    await _supabase.auth.signInWithPassword(email: email, password: password);
  }

  static Future<bool> signInWithGoogle() async {
    return await _supabase.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: 'io.supabase.flutter://login-callback/',
    );
  }

  static Future<void> signOut() async {
    await _supabase.auth.signOut();
  }
}
