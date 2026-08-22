import 'package:flutter/material.dart';
import '../../core/styles/app_colors.dart';
import '../../core/styles/app_fonts.dart';
import '../../core/styles/app_radius.dart';
import '../../core/styles/app_spacing.dart';
import '../../core/styles/app_text_styles.dart';
import '../../core/utils/session_format.dart';
import '../../features/session/model/pr_engine.dart';

/// The PR showcase + Lessons list of a session's reflection — two dedicated
/// sections (PRS, LESSONS), each with an explicit empty note when the session
/// had none, and one exercise block per exercise that has content. The exact
/// styling used on the session Reflection page. Shared between the live
/// Reflection page and the prep page's LAST SESSION card so the two can never
/// drift.
class ReflectionSummary extends StatelessWidget {
  const ReflectionSummary({
    super.key,
    required this.exerciseIds,
    required this.prsByExercise,
    required this.lessonsByExercise,
    required this.exerciseNameFor,
    required this.previousFor,
  });

  /// Exercises in display order (slots for the live session, first-appearance
  /// order for the prep card). Exercises with no PRs and no lessons are
  /// skipped; when none remain, the sections render their empty notes.
  final List<String> exerciseIds;

  /// exerciseId → that session's explicit (non-propagated) PRs.
  final Map<String, List<PrRecord>> prsByExercise;

  /// exerciseId → lesson texts.
  final Map<String, List<String>> lessonsByExercise;

  /// Raw display name for an exercise — [toProperCase] is applied here so
  /// both contexts render identically.
  final String Function(String exerciseId) exerciseNameFor;

  /// The record a PR beat on its axis — history OR an earlier set in the
  /// same session. Null means "first PR" (rendered without a before value).
  final PrRecord? Function(PrRecord p) previousFor;

  static String _fmt(num n) =>
      n == n.roundToDouble() ? n.toInt().toString() : n.toString();

  @override
  Widget build(BuildContext context) {
    final prExercises = exerciseIds
        .where((id) => (prsByExercise[id] ?? const []).isNotEmpty)
        .toList();
    final lessonExercises = exerciseIds
        .where((id) => (lessonsByExercise[id] ?? const []).isNotEmpty)
        .toList();

    // Vertical rhythm, all gaps explicit here (content widgets carry only
    // their trailing 8): 8 label→first block, 8 name→content and card→card,
    // 16 between exercises, 24 between sections.
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionLabel(Icons.emoji_events_outlined, 'PRS'),
        const SizedBox(height: AppSpacing.sm),
        ..._sectionContent(prExercises, 'No PRs this session', _prCardsFor),
        const SizedBox(height: AppSpacing.xl),
        _sectionLabel(Icons.menu_book_outlined, 'LESSONS'),
        const SizedBox(height: AppSpacing.sm),
        ..._sectionContent(
            lessonExercises, 'No lessons this session', _lessonRowsFor),
      ],
    );
  }

  /// One section's body: the empty note, or each exercise's name header +
  /// its content blocks with a consistent gap between exercises.
  List<Widget> _sectionContent(List<String> exercises, String emptyText,
      List<Widget> Function(String) contentFor) {
    if (exercises.isEmpty) return [_emptyNote(emptyText)];
    final blocks = <Widget>[];
    for (var i = 0; i < exercises.length; i++) {
      if (i > 0) blocks.add(const SizedBox(height: AppSpacing.lg));
      blocks.add(_exerciseHeader(exercises[i]));
      blocks.addAll(contentFor(exercises[i]));
    }
    return blocks;
  }

  Widget _sectionLabel(IconData icon, String text) => Row(
        children: [
          Icon(icon, size: 14, color: AppColors.accent),
          const SizedBox(width: 6),
          Text(text,
              style: AppFonts.mono(
                  fontSize: 9, letterSpacing: 0.8, color: AppColors.primary)),
        ],
      );

  Widget _emptyNote(String text) => Text(text,
      style: AppFonts.ui(fontSize: AppTextStyles.xs, color: AppColors.muted));

  Widget _exerciseHeader(String exerciseId) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
        child: Text(toProperCase(exerciseNameFor(exerciseId)),
            style: AppFonts.ui(
                fontSize: AppTextStyles.md,
                fontWeight: FontWeight.w700,
                color: AppColors.primary)),
      );

  /// PR cards for one exercise — grouped by source set; a set that fired
  /// both axes shows its RM only.
  List<Widget> _prCardsFor(String exerciseId) {
    final bySet = <String?, List<PrRecord>>{};
    for (final p in prsByExercise[exerciseId] ?? const []) {
      bySet.putIfAbsent(p.setId, () => []).add(p);
    }
    final cards = <Widget>[];
    for (final group in bySet.values) {
      final rm = group.where((p) => p.type == PrType.repMax).firstOrNull;
      final wm = group.where((p) => p.type == PrType.weightMax).firstOrNull;
      if (rm != null && wm != null) {
        // Both axes fired: prefer the one with a meaningful "before"
        // (5kg x 9 after 5kg x 7 reads as a weight-max progression,
        // not another first RM). Both or neither -> RM.
        final rmHasPrev = previousFor(rm) != null;
        final wmHasPrev = previousFor(wm) != null;
        cards.add(rmHasPrev || !wmHasPrev ? _prCard(rm) : _prCard(wm));
      } else if (rm != null) {
        cards.add(_prCard(rm));
      } else if (wm != null) {
        cards.add(_prCard(wm));
      }
    }
    return cards;
  }

  List<Widget> _lessonRowsFor(String exerciseId) => [
        for (final lesson in lessonsByExercise[exerciseId] ?? const [])
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: AppColors.surfaceHigh,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.menu_book_outlined,
                      size: 16, color: AppColors.primary),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(lesson,
                        style: AppFonts.ui(
                            fontSize: AppTextStyles.sm,
                            color: AppColors.primary)),
                  ),
                ],
              ),
            ),
          ),
      ];

  /// One PR row: the axis beaten this session with its before/after.
  /// rep-max: "5RM: 100kg → 105kg"; weight-max: "100kg: 3 → 5 reps".
  /// PR-set style: accentBg fill with the accent outline.
  Widget _prCard(PrRecord p) {
    final String? before;
    final String after;
    final String axisLabel;
    if (p.type == PrType.repMax) {
      final prev = previousFor(p);
      before = prev != null ? '${_fmt(prev.weight)}kg' : null;
      after = '${_fmt(p.weight)}kg';
      axisLabel = '${p.targetReps ?? ''}RM';
    } else {
      final prev = previousFor(p);
      before = prev != null ? '${_fmt(prev.reps)} reps' : null;
      after = '${_fmt(p.reps)} reps';
      axisLabel = '${_fmt(p.targetWeight ?? p.weight)}kg';
    }
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.accentBg,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.accent, width: 1.2),
      ),
      child: Row(
        children: [
          Icon(Icons.emoji_events_outlined, size: 16, color: AppColors.accent),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (p.variationName != null)
                  Text(toProperCase(p.variationName!),
                      style: AppFonts.mono(
                          fontSize: 9,
                          letterSpacing: 0.6,
                          color: AppColors.accent)),
                Text(before != null
                    ? '$axisLabel: $before  →  $after'
                    : '$axisLabel: $after (First PR)',
                    style: AppFonts.mono(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.accent)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
