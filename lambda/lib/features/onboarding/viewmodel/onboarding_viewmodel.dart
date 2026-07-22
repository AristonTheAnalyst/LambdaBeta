import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../data/models/user_profile.dart';
import '../../../data/repositories/user_repository.dart';

class OnboardingState {
  const OnboardingState({
    this.isLoading = false,
    this.success = false,
    this.error,
    this.firstName = '',
    this.lastName = '',
    this.dateOfBirth,
    this.gender,
    this.heightCm,
    this.weightKg,
  });

  final bool isLoading;
  final bool success;
  final String? error;
  final String firstName;
  final String lastName;
  final DateTime? dateOfBirth;
  final String? gender;
  final double? heightCm;
  final double? weightKg;

  OnboardingState copyWith({
    bool? isLoading,
    bool? success,
    String? error,
    bool clearError = false,
    String? firstName,
    String? lastName,
    DateTime? dateOfBirth,
    bool clearDob = false,
    String? gender,
    bool clearGender = false,
    double? heightCm,
    double? weightKg,
  }) =>
      OnboardingState(
        isLoading: isLoading ?? this.isLoading,
        success: success ?? this.success,
        error: clearError ? null : error ?? this.error,
        firstName: firstName ?? this.firstName,
        lastName: lastName ?? this.lastName,
        dateOfBirth: clearDob ? null : (dateOfBirth ?? this.dateOfBirth),
        gender: clearGender ? null : (gender ?? this.gender),
        heightCm: heightCm ?? this.heightCm,
        weightKg: weightKg ?? this.weightKg,
      );
}

class OnboardingViewModel {
  OnboardingViewModel({UserRepository? userRepository})
      : _repo = userRepository ?? UserRepository();

  final UserRepository _repo;
  final state = ValueNotifier(const OnboardingState());

  void setFirstName(String v) =>
      state.value = state.value.copyWith(firstName: v, clearError: true);
  void setLastName(String v) =>
      state.value = state.value.copyWith(lastName: v, clearError: true);
  void setDateOfBirth(DateTime? v) =>
      state.value = v == null
          ? state.value.copyWith(clearDob: true, clearError: true)
          : state.value.copyWith(dateOfBirth: v, clearError: true);
  void setGender(String? v) =>
      state.value = v == null
          ? state.value.copyWith(clearGender: true, clearError: true)
          : state.value.copyWith(gender: v, clearError: true);
  void setHeightCm(double? v) =>
      state.value = state.value.copyWith(heightCm: v, clearError: true);
  void setWeightKg(double? v) =>
      state.value = state.value.copyWith(weightKg: v, clearError: true);

  Future<void> submit() async {
    final s = state.value;
    if (s.firstName.trim().isEmpty || s.lastName.trim().isEmpty) {
      state.value = s.copyWith(error: 'First and last name are required.');
      return;
    }
    final weightKg = s.weightKg;
    if (weightKg != null && (weightKg < 20 || weightKg > 300)) {
      state.value = s.copyWith(error: 'Weight must be between 20 and 300 kg.');
      return;
    }

    state.value = s.copyWith(isLoading: true, clearError: true);
    try {
      final userId = Supabase.instance.client.auth.currentUser!.id;
      final profile = UserProfile(
        userId: userId,
        userName: s.firstName.trim(),
        userLastname: s.lastName.trim(),
        userDateOfBirth: s.dateOfBirth,
        userGender: s.gender,
        userHeightCm: s.heightCm,
        userWeightKg: s.weightKg,
        onboarded: true,
      );
      await _repo.upsertProfile(profile);
      if (weightKg != null) {
        await _repo.logWeight(userId, weightKg);
      }
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
