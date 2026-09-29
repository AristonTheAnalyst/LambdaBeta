import 'package:flutter/material.dart';
import '../../core/styles/app_colors.dart';
import '../../core/styles/app_fonts.dart';
import '../../core/utils/name_limit.dart';

/// The `12/20` counter that sits under every field taking an exercise or
/// variation name.
///
/// One widget rather than a per-screen `Text`, because [kMaxExerciseNameLength]
/// is stated in the database too and a counter spelling the number a second time
/// is how the two drift. It also gives the cap somewhere to be *visible*: the
/// field silently refuses the twenty-first character, and without this the
/// refusal reads as a broken keyboard.
///
/// Turns [AppColors.danger] at the cap — the same colour the field's error state
/// uses — so "you are at the limit" is legible without being an error.
class NameLimitCounter extends StatelessWidget {
  const NameLimitCounter({super.key, required this.length});

  /// The length of the trimmed value on its way to being stored.
  final int length;

  @override
  Widget build(BuildContext context) {
    final atLimit = length >= kMaxExerciseNameLength;
    return Text(
      '$length/$kMaxExerciseNameLength',
      textAlign: TextAlign.right,
      style: AppFonts.mono(
        fontSize: 12,
        letterSpacing: 0.4,
        color: atLimit ? AppColors.danger : AppColors.muted,
      ),
    );
  }
}
