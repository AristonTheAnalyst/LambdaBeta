import 'package:flutter/foundation.dart';
import '../../../data/repositories/auth_repository.dart';

enum SocialProvider { google, apple }

class AuthFormState {
  final bool isLoading;
  final SocialProvider? socialLoading;
  final String? error;
  final bool emailSent;

  const AuthFormState({
    this.isLoading = false,
    this.socialLoading,
    this.error,
    this.emailSent = false,
  });

  bool get isBusy => isLoading || socialLoading != null;

  AuthFormState copyWith({
    bool? isLoading,
    SocialProvider? socialLoading,
    bool clearSocial = false,
    String? error,
    bool clearError = false,
    bool? emailSent,
  }) {
    return AuthFormState(
      isLoading: isLoading ?? this.isLoading,
      socialLoading: clearSocial ? null : (socialLoading ?? this.socialLoading),
      error: clearError ? null : (error ?? this.error),
      emailSent: emailSent ?? this.emailSent,
    );
  }
}

class AuthViewModel {
  final ValueNotifier<AuthFormState> state =
      ValueNotifier(const AuthFormState());
  final AuthRepository _repo;

  AuthViewModel({AuthRepository? repo}) : _repo = repo ?? AuthRepository();

  Future<void> signIn(String email, String password) async {
    state.value = const AuthFormState(isLoading: true);
    final error = await _repo.signIn(email, password);
    state.value = AuthFormState(error: error);
  }

  Future<void> signUp(String email, String password) async {
    state.value = const AuthFormState(isLoading: true);
    final error = await _repo.signUp(email, password);
    state.value = AuthFormState(error: error);
  }

  Future<void> signInWithGoogle() async {
    state.value = const AuthFormState(socialLoading: SocialProvider.google);
    final error = await _repo.signInWithGoogle();
    state.value = AuthFormState(error: error);
  }

  Future<void> signInWithApple() async {
    state.value = const AuthFormState(socialLoading: SocialProvider.apple);
    final error = await _repo.signInWithApple();
    state.value = AuthFormState(error: error);
  }

  Future<void> resetPassword(String email) async {
    state.value = const AuthFormState(isLoading: true);
    final error = await _repo.resetPassword(email);
    state.value = error != null
        ? AuthFormState(error: error)
        : const AuthFormState(emailSent: true);
  }

  void clearError() {
    state.value = state.value.copyWith(clearError: true);
  }

  void dispose() => state.dispose();
}
