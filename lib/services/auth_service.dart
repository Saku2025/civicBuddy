import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthService {
  static final SupabaseClient _supabase = Supabase.instance.client;

  // "CivicBuddy Web" OAuth client. Native sign-in asks Google for an ID token
  // issued to this client, so:
  // - the Android OAuth client (package + signing SHA-1) must be in the same
  //   Google Cloud project, and
  // - it must be listed in Supabase > Auth > Google > Client IDs (after the
  //   browser-flow client, which stays first).
  // Client IDs are not secret.
  static const String _googleWebClientId =
      '268032863942-bauhruu3qmgrlt04qqn9pe67o0rg12c8.apps.googleusercontent.com';

  // google_sign_in may only be initialised once per app run. The hashed nonce
  // goes into Google's ID token; Supabase checks it against the raw one.
  static Future<void>? _googleInit;
  static String? _rawNonce;

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

  /// Signs in with Google. On Android this uses the native account picker;
  /// elsewhere, or if native sign-in fails for any reason other than the user
  /// cancelling, it falls back to the browser flow (AuthGate then picks up the
  /// session from the login-callback redirect).
  ///
  /// Returns normally when signed in, cancelled, or the browser was opened.
  static Future<void> signInWithGoogle() async {
    if (Platform.isAndroid) {
      try {
        await _signInWithGoogleNative();
        return;
      } on GoogleSignInException catch (e) {
        if (e.code == GoogleSignInExceptionCode.canceled) return;
        debugPrint('Native Google sign-in failed, using browser: $e');
      } catch (e) {
        debugPrint('Native Google sign-in failed, using browser: $e');
      }
    }

    final launched = await _supabase.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: 'io.supabase.flutter://login-callback/',
    );

    if (!launched) {
      throw Exception('Unable to open Google Sign-In. Please try again.');
    }
  }

  static Future<void> _signInWithGoogleNative() async {
    final signIn = GoogleSignIn.instance;

    try {
      await (_googleInit ??= _initGoogleSignIn());
    } catch (_) {
      _googleInit = null; // Retry initialisation on the next attempt.
      rethrow;
    }

    if (!signIn.supportsAuthenticate()) {
      throw UnsupportedError('Native Google sign-in is not available.');
    }

    final account = await signIn.authenticate();
    final idToken = account.authentication.idToken;

    if (idToken == null) {
      throw StateError('Google did not return an ID token.');
    }

    await _supabase.auth.signInWithIdToken(
      provider: OAuthProvider.google,
      idToken: idToken,
      nonce: _rawNonce,
    );
  }

  static Future<void> _initGoogleSignIn() async {
    final random = Random.secure();
    final rawNonce = base64Url.encode(
      List<int>.generate(32, (_) => random.nextInt(256)),
    );
    _rawNonce = rawNonce;

    await GoogleSignIn.instance.initialize(
      serverClientId: _googleWebClientId,
      nonce: sha256.convert(utf8.encode(rawNonce)).toString(),
    );
  }

  static Future<void> signOut() async {
    await _supabase.auth.signOut();

    // Forget the chosen Google account so the picker appears next time.
    if (_googleInit != null) {
      try {
        await GoogleSignIn.instance.signOut();
      } catch (_) {}
    }
  }
}
