import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../data/models/user_profile.dart';
import '../../../data/repositories/user_repository.dart';

class OnboardingState {
  const OnboardingState({
    this.isLoading = false,
    this.success = false,
    this.error,
  });

  final bool isLoading;
  final bool success;
  final String? error;

  OnboardingState copyWith({
    bool? isLoading,
    bool? success,
    String? error,
    bool clearError = false,
  }) =>
      OnboardingState(
        isLoading: isLoading ?? this.isLoading,
        success: success ?? this.success,
        error: clearError ? null : error ?? this.error,
      );
}

class OnboardingViewModel {
  OnboardingViewModel({UserRepository? userRepository})
      : _repo = userRepository ?? UserRepository();

  final UserRepository _repo;
  final state = ValueNotifier(const OnboardingState());

  Future<void> submit() async {
    state.value = state.value.copyWith(isLoading: true, clearError: true);
    try {
      final userId = Supabase.instance.client.auth.currentUser!.id;
      final profile = UserProfile(
        userId: userId,
        onboarded: true,
      );
      await _repo.upsertProfile(profile);
      state.value = state.value.copyWith(isLoading: false, success: true);
    } catch (e) {
      state.value = state.value.copyWith(
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  void dispose() => state.dispose();
}
