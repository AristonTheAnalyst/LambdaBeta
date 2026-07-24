import 'dart:io';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthRepository {
  final _auth = Supabase.instance.client.auth;

  Future<String?> signIn(String email, String password) async {
    try {
      await _auth.signInWithPassword(email: email, password: password);
      return null;
    } on AuthException catch (e) {
      return e.message;
    } catch (_) {
      return 'An unexpected error occurred';
    }
  }

  Future<String?> signUp(String email, String password) async {
    try {
      final response = await _auth.signUp(email: email, password: password);
      // Supabase returns a fake success for existing confirmed emails
      if (response.user != null &&
          response.session == null &&
          (response.user!.identities?.isEmpty ?? false)) {
        return 'An account with this email already exists';
      }
      return null;
    } on AuthException catch (e) {
      return e.message;
    } catch (_) {
      return 'An unexpected error occurred';
    }
  }

  Future<String?> signInWithGoogle() async {
    try {
      final googleUser = await GoogleSignIn(
        serverClientId: '1087524383718-m5vrhjg3ug1u3q0t3hfp7qbrlo2bmesq.apps.googleusercontent.com',
      ).signIn();
      if (googleUser == null) return null; // user cancelled
      final googleAuth = await googleUser.authentication;
      final idToken = googleAuth.idToken;
      if (idToken == null) return 'Google sign-in did not return a token';
      await _auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
        accessToken: googleAuth.accessToken,
      );
      return null;
    } on AuthException catch (e) {
      return e.message;
    } catch (e) {
      return 'Google sign-in failed: $e';
    }
  }

  Future<String?> signInWithApple() async {
    if (!Platform.isIOS && !Platform.isMacOS) {
      return 'Apple sign-in is only available on iOS';
    }
    try {
      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
      );
      final idToken = credential.identityToken;
      if (idToken == null) return 'Apple sign-in did not return a token';
      await _auth.signInWithIdToken(
        provider: OAuthProvider.apple,
        idToken: idToken,
      );
      return null;
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code == AuthorizationErrorCode.canceled) return null;
      return e.message;
    } on AuthException catch (e) {
      return e.message;
    } catch (_) {
      return 'Apple sign-in failed';
    }
  }

  Future<String?> resetPassword(String email) async {
    try {
      await _auth.resetPasswordForEmail(
        email,
        redirectTo: 'com.rockyzubiri.lambda://reset-password/',
      );
      return null;
    } on AuthException catch (e) {
      return e.message;
    } catch (_) {
      return 'An unexpected error occurred';
    }
  }

  Future<String?> signOut() async {
    try {
      await _auth.signOut();
      return null;
    } on AuthException catch (e) {
      return e.message;
    } catch (_) {
      return 'An unexpected error occurred';
    }
  }
}
