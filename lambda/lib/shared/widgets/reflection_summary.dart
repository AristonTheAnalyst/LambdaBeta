import 'package:flutter/material.dart';
import '../../core/styles/app_colors.dart';
import '../../core/styles/app_fonts.dart';
import 'container_styles.dart';
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
    this.showPrs = true,
    this.showLessons = true,
  });

  /// Exercises in display order (slots for the live session, first-appearance
  /// order for the prep card). Exercises with no PRs and no lessons are
  /// skipped; when none remain, the sections render their empty notes.
  final List<String> exerciseIds;

  /// exerciseId → that session's PR events (one per frontier-extending set).
  final Map<String, List<PrEvent>> prsByExercise;

  /// exerciseId → lesson texts.
  final Map<String, List<String>> lessonsByExercise;

  /// Raw display name for an exercise — [toProperCase] is applied here so
  /// both contexts render identically.
  final String Function(String exerciseId) exerciseNameFor;

  /// Which sections render — the past-session viewer's Summary tab is
  /// lessons-only and its PRs tab is PRs-only; the live reflection page and
  /// the prep card keep both.
  final bool showPrs;
  final bool showLessons;

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
    final sections = <Widget>[
      if (showPrs) ...[
        _sectionLabel(Icons.emoji_events_outlined, 'PRS'),
        const SizedBox(height: AppSpacing.sm),
        ..._sectionContent(prExercises, 'No PRs this session', _prCardsFor),
      ],
      if (showPrs && showLessons) const SizedBox(height: AppSpacing.xl),
      if (showLessons) ...[
        _sectionLabel(Icons.menu_book_outlined, 'LESSONS'),
        const SizedBox(height: AppSpacing.sm),
        ..._sectionContent(
            lessonExercises, 'No lessons this session', _lessonRowsFor),
      ],
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: sections,
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
                  fontSize: 13, letterSpacing: 0.8, color: AppColors.primary)),
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

  /// PR cards for one exercise — one card per event (one per PR set).
  List<Widget> _prCardsFor(String exerciseId) => [
        for (final e in prsByExercise[exerciseId] ?? const <PrEvent>[])
          _prCard(e),
      ];

  List<Widget> _lessonRowsFor(String exerciseId) => [
        for (final lesson in lessonsByExercise[exerciseId] ?? const [])
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: lambdaBox(ContainerTone.ghost, radius: AppRadius.md),
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

  /// One PR row — the set, plus the previous frontier values it beat. Both
  /// dimensions can be beaten at once ("was 6 × 10 · 100 × 3"): one PR, two
  /// facts. PR-set style: accentBg fill with the accent outline.
  Widget _prCard(PrEvent e) {
    final facts = <String>[
      // Previous best weight at ≥ this many reps.
      if (e.beforeWeight != null)
        'was ${_fmt(e.beforeWeight!)}kg × ${_fmt(e.reps)}',
      // Previous best reps at exactly this weight.
      if (e.beforeReps != null)
        'was ${_fmt(e.weight)}kg × ${_fmt(e.beforeReps!)}',
    ];
    final before = facts.isEmpty ? 'First PR' : facts.join(' · ');
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      decoration: lambdaBox(
        ContainerTone.accent,
        radius: AppRadius.md,
      ),
      child: Row(
        children: [
          Icon(Icons.emoji_events_outlined, size: 16, color: AppColors.accent),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (e.variationName != null)
                  Text(toProperCase(e.variationName!),
                      style: AppFonts.mono(
                          fontSize: 13,
                          letterSpacing: 0.6,
                          color: AppColors.accent)),
                Text('${_fmt(e.weight)}kg × ${_fmt(e.reps)}',
                    style: AppFonts.mono(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.accent)),
                Text(before,
                    style: AppFonts.mono(
                        fontSize: 14,
                        color: AppColors.accent)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
