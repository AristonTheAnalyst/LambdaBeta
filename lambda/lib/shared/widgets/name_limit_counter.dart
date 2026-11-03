import 'package:flutter/material.dart';
import '../../core/styles/app_colors.dart';
import '../../core/styles/app_fonts.dart';
import '../../core/styles/app_text_styles.dart';
import '../../core/utils/name_limit.dart';

/// The `12/20` counter that sits under every field taking a user-created name.
///
/// One widget rather than a per-screen `Text`, because the limit is stated in
/// the database too and a counter spelling the number a second time is how the
/// two drift. It also gives the cap somewhere to be *visible*: the field
/// silently refuses the character past the limit, and without this the refusal
/// reads as a broken keyboard.
///
/// [max] defaults to [kMaxExerciseNameLength] — the exercise and variation
/// fields were the first to wear the counter and pass nothing; every wider kind
/// of name (workout, program, block, goal, review) passes its own constant.
///
/// Turns [AppColors.danger] at the cap — the same colour the field's error state
/// uses — so "you are at the limit" is legible without being an error.
class NameLimitCounter extends StatelessWidget {
  const NameLimitCounter({
    super.key,
    required this.length,
    this.max = kMaxExerciseNameLength,
  });

  /// The length of the trimmed value on its way to being stored.
  final int length;

  /// The limit for this kind of name.
  final int max;

  @override
  Widget build(BuildContext context) {
    final atLimit = length >= max;
    return Text(
      '$length/$max',
      textAlign: TextAlign.right,
      style: AppFonts.mono(
        fontSize: AppTextStyles.xs,
        color: atLimit ? AppColors.danger : AppColors.inkSecondary,
      ),
    );
  }
}
