import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../data/models/user_profile.dart';
import '../../../data/repositories/user_repository.dart';

class ProfileState {
  const ProfileState({
    this.isLoading = false,
    this.isSaving = false,
    this.isDeleting = false,
    this.isEditing = false,
    this.saveSuccess = false,
    this.error,
    this.profile,
  });

  final bool isLoading;
  final bool isSaving;
  final bool isDeleting;
  final bool isEditing;
  final bool saveSuccess;
  final String? error;
  final UserProfile? profile;

  bool get isBusy => isLoading || isSaving || isDeleting;

  ProfileState copyWith({
    bool? isLoading,
    bool? isSaving,
    bool? isDeleting,
    bool? isEditing,
    bool? saveSuccess,
    String? error,
    bool clearError = false,
    UserProfile? profile,
  }) =>
      ProfileState(
        isLoading: isLoading ?? this.isLoading,
        isSaving: isSaving ?? this.isSaving,
        isDeleting: isDeleting ?? this.isDeleting,
        isEditing: isEditing ?? this.isEditing,
        saveSuccess: saveSuccess ?? false,
        error: clearError ? null : error ?? this.error,
        profile: profile ?? this.profile,
      );
}

class ProfileViewModel {
  ProfileViewModel({UserRepository? userRepository})
      : _repo = userRepository ?? UserRepository();

  final UserRepository _repo;
  final state = ValueNotifier(const ProfileState());

  Future<void> loadProfile() async {
    state.value = state.value.copyWith(isLoading: true, clearError: true);
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;
      final profile = await _repo.fetchProfile(userId);
      state.value = state.value.copyWith(isLoading: false, profile: profile);
    } catch (e) {
      state.value =
          state.value.copyWith(isLoading: false, error: e.toString());
    }
  }

  void startEditing() =>
      state.value = state.value.copyWith(isEditing: true, clearError: true);

  void cancelEditing() =>
      state.value = state.value.copyWith(isEditing: false, clearError: true);

  Future<void> saveProfile({
    required String firstName,
    required String lastName,
    required DateTime? dateOfBirth,
    required String? gender,
    required double? heightCm,
    required double? weightKg,
  }) async {
    if (firstName.trim().isEmpty) {
      state.value =
          state.value.copyWith(error: 'First name is required.');
      return;
    }
    if (weightKg != null && (weightKg < 20 || weightKg > 300)) {
      state.value =
          state.value.copyWith(error: 'Weight must be between 20 and 300 kg.');
      return;
    }

    state.value = state.value.copyWith(isSaving: true, clearError: true);
    try {
      final userId = Supabase.instance.client.auth.currentUser!.id;
      final current = state.value.profile;
      final updated = UserProfile(
        userId: userId,
        userName: firstName.trim(),
        userLastname: lastName.trim().isNotEmpty ? lastName.trim() : null,
        userDateOfBirth: dateOfBirth,
        userGender: gender?.isNotEmpty == true ? gender : null,
        userHeightCm: heightCm,
        userWeightKg: weightKg,
        onboarded: current?.onboarded ?? true,
        userDateCreated: current?.userDateCreated,
      );
      await _repo.upsertProfile(updated);

      // Log weight only if it changed
      if (weightKg != null && weightKg != current?.userWeightKg) {
        await _repo.logWeight(userId, weightKg);
      }

      state.value = state.value.copyWith(
        isSaving: false,
        isEditing: false,
        saveSuccess: true,
        profile: updated,
      );
      Future.delayed(const Duration(seconds: 2), () {
        state.value = state.value.copyWith(saveSuccess: false);
      });
    } catch (e) {
      state.value = state.value.copyWith(
          isSaving: false, error: 'Failed to save changes.');
    }
  }

  Future<void> signOut() async {
    await Supabase.instance.client.auth.signOut();
  }

  Future<bool> deleteAccount() async {
    state.value = state.value.copyWith(isDeleting: true, clearError: true);
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId != null) await _repo.deleteAccount(userId);
      await Supabase.instance.client.auth.signOut();
      state.value = state.value.copyWith(isDeleting: false);
      return true;
    } catch (e) {
      state.value = state.value.copyWith(
          isDeleting: false, error: 'Failed to delete account. Please try again.');
      return false;
    }
  }

  void dispose() => state.dispose();
}
