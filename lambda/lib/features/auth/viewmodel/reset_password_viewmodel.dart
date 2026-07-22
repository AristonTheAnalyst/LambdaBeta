import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ResetPasswordState {
  const ResetPasswordState({
    this.isLoading = false,
    this.error,
    this.success = false,
  });

  final bool isLoading;
  final String? error;
  final bool success;

  ResetPasswordState copyWith({
    bool? isLoading,
    String? error,
    bool clearError = false,
    bool? success,
  }) =>
      ResetPasswordState(
        isLoading: isLoading ?? this.isLoading,
        error: clearError ? null : error ?? this.error,
        success: success ?? this.success,
      );
}

class ResetPasswordViewModel {
  final state = ValueNotifier(const ResetPasswordState());

  Future<void> updatePassword(String newPassword) async {
    state.value = state.value.copyWith(isLoading: true, clearError: true);
    try {
      final response = await Supabase.instance.client.auth
          .updateUser(UserAttributes(password: newPassword));
      if (response.user == null) {
        state.value = state.value.copyWith(
          isLoading: false,
          error: 'Failed to update password. Please try again.',
        );
      } else {
        state.value = state.value.copyWith(isLoading: false, success: true);
      }
    } catch (e) {
      state.value = state.value.copyWith(
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  void clearError() =>
      state.value = state.value.copyWith(clearError: true);

  void dispose() => state.dispose();
}
