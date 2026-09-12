import 'package:flutter/material.dart';
import '../../../core/styles/app_colors.dart';
import '../../../core/styles/app_fonts.dart';
import '../../../core/styles/app_radius.dart';
import '../../../core/styles/app_spacing.dart';
import '../../../core/styles/app_text_styles.dart';
import '../../../core/utils/session_format.dart';
import '../../../shared/widgets/container_styles.dart';
import '../../../shared/widgets/slide_up_modal.dart';
import '../viewmodel/session_viewmodel.dart';
import 'lessons_modal.dart';

/// PRS / LESSONS — the active workout's summary stats, in the Training
/// page's sticky bottom bar.
/// Both tiles are tappable: PRS opens the session PR breakdown, LESSONS
/// opens the session lessons breakdown. Rows navigate to the exercise
/// within the session (lessons also opens that exercise's lessons modal).
class SessionStatsBar extends StatelessWidget {
  const SessionStatsBar({super.key, required this.vm});

  final SessionViewModel vm;

  /// PR sets grouped by (exerciseId, variationId) — one entry per row of
  /// the PR breakdown. Derived from the same distinct-set ids the tile and
  /// the row highlights use (explicit rep-max only), so the group counts
  /// sum exactly to the tile.
  List<({String exerciseId, String? variationId, String label, int count})>
      _prBreakdown() {
    final groups = <(String, String?), Set<String>>{};
    final varNames = <(String, String?), String>{};
    for (final s in vm.sets) {
      final exerciseId = s.exerciseId;
      if (exerciseId == null) continue;
      if (!vm.prSetIds.contains(s.sessionExerciseSetId)) continue;
      final key = (exerciseId, s.variationId);
      groups.putIfAbsent(key, () => {}).add(s.sessionExerciseSetId);
      if (s.variationName != null && s.variationName!.isNotEmpty) {
        varNames.putIfAbsent(key, () => s.variationName!);
      }
    }
    final out = <({String exerciseId, String? variationId, String label, int count})>[];
    for (final e in groups.entries) {
      final exerciseName =
          toProperCase(vm.exerciseDisplayName(e.key.$1));
      final varName = varNames[e.key];
      final label = varName != null
          ? '$exerciseName · ${toProperCase(varName)}'
          : exerciseName;
      out.add((
        exerciseId: e.key.$1,
        variationId: e.key.$2,
        label: label,
        count: e.value.length,
      ));
    }
    out.sort((a, b) => b.count.compareTo(a.count));
    return out;
  }

  /// Exercises in the current session with their lesson counts, in slot
  /// order.
  List<({String exerciseId, String label, int count})> _lessonsBreakdown() {
    final seen = <String>{};
    final out = <({String exerciseId, String label, int count})>[];
    for (final slot in vm.exerciseSlots) {
      for (final exerciseId in slot.exerciseIds) {
        if (!seen.add(exerciseId)) continue;
        final count = vm.lessonsThisSession(exerciseId).length;
        out.add((
          exerciseId: exerciseId,
          label: toProperCase(vm.exerciseDisplayName(exerciseId)),
          count: count,
        ));
      }
    }
    out.removeWhere((e) => e.count == 0);
    return out;
  }

  int _sessionSlotIndexFor(String exerciseId) =>
      vm.exerciseSlots.indexWhere((s) => s.exerciseIds.contains(exerciseId));

  void _openPrBreakdown(BuildContext context) {
    final rows = _prBreakdown();
    showLambdaModal(
      context,
      fitContent: true,
      child: _BreakdownSheet(
        title: 'Session PRs',
        rows: [
          for (final r in rows)
            (label: r.label, count: r.count, exerciseId: r.exerciseId),
        ],
        onRowTap: (exerciseId) {
          Navigator.of(context, rootNavigator: true).pop();
          final idx = _sessionSlotIndexFor(exerciseId);
          if (idx >= 0) vm.tapTab(idx);
        },
      ),
    );
  }

  void _openLessonsBreakdown(BuildContext context) {
    final rows = _lessonsBreakdown();
    showLambdaModal(
      context,
      fitContent: true,
      child: _BreakdownSheet(
        title: 'Session Lessons',
        accent: false,
        rows: [
          for (final r in rows)
            (label: r.label, count: r.count, exerciseId: r.exerciseId),
        ],
        onRowTap: (exerciseId) {
          Navigator.of(context, rootNavigator: true).pop();
          final idx = _sessionSlotIndexFor(exerciseId);
          if (idx >= 0) vm.tapTab(idx);
          showLessonsModal(
            context,
            listenable: vm,
            lessonsFor: vm.lessonsFor,
            loadLessonsFor: vm.loadLessonsFor,
            addLesson: vm.addLesson,
            toggleLessonPin: vm.toggleLessonPin,
            deleteLesson: vm.deleteLesson,
            updateLesson: vm.updateLessonText,
            exerciseId: exerciseId,
            exerciseName: toProperCase(vm.exerciseDisplayName(exerciseId)),
            sessionId: vm.currentWorkoutId,
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: vm,
      builder: (context, _) {
        final prs = vm.totalPRsThisSession;
        final lessons =
            vm.exerciseSlots.fold<int>(0, (sum, slot) {
              var s = sum;
              for (final exerciseId in slot.exerciseIds) {
                s += vm.lessonsThisSession(exerciseId).length;
              }
              return s;
            });
        return Row(
          children: [
            Expanded(
              child: _summaryTile(
                label: 'PRS',
                value: '$prs',
                highlighted: prs > 0,
                onTap: prs > 0 ? () => _openPrBreakdown(context) : null,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: _summaryTile(
                label: 'LESSONS',
                value: '$lessons',
                highlighted: lessons > 0,
                highlightColor: AppColors.primary,
                highlightBg: AppColors.surfaceHigh,
                onTap: lessons > 0 ? () => _openLessonsBreakdown(context) : null,
              ),
            ),
          ],
        );
      },
    );
  }

  /// One PRS/LESSONS tile, styled like a PR-highlighted set row: accentBg
  /// fill with an accent 1.2 outline when there's something to show.
  /// Label and value sit side by side so the tile reads as one line.
  Widget _summaryTile({
    required String label,
    required String value,
    required bool highlighted,
    Color? highlightColor,
    Color? highlightBg,
    VoidCallback? onTap,
  }) {
    final color = highlightColor ?? AppColors.accent;
    final tile = Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      // Highlighted tiles are pressables — the glass recipe in the tile's
      // semantic color, like every other control.
      decoration: highlighted
          ? glassBox(color)
          : BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: AppColors.border, width: 0.5),
            ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('$label:',
              style: AppFonts.mono(
                  fontSize: 13,
                  letterSpacing: 0.8,
                  color: highlighted ? color : AppColors.muted)),
          const SizedBox(width: 6),
          Text(value,
              style: AppFonts.mono(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: highlighted ? color : AppColors.primary)),
        ],
      ),
    );
    if (onTap == null) return tile;
    return GestureDetector(onTap: onTap, child: tile);
  }
}

// ── Breakdown sheet ──────────────────────────────────────────────────────────

class _BreakdownSheet extends StatelessWidget {
  const _BreakdownSheet({
    required this.title,
    required this.rows,
    required this.onRowTap,
    this.accent = true,
  });

  final String title;
  final bool accent;
  final List<({String label, int count, String exerciseId})> rows;
  final void Function(String exerciseId) onRowTap;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title,
                style: AppFonts.ui(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primary)),
            const SizedBox(height: AppSpacing.md),
            if (rows.isEmpty)
              Text('Nothing yet this session.',
                  style: AppFonts.ui(fontSize: 13, color: AppColors.muted))
            else
              for (final r in rows)
                InkWell(
                  onTap: () => onRowTap(r.exerciseId),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm, vertical: AppSpacing.md),
                    decoration: const BoxDecoration(
                      border: Border(
                        bottom: BorderSide(width: 0.5),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(r.label,
                              style: AppFonts.ui(
                                  fontSize: AppTextStyles.md,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.primary)),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: accent
                                ? AppColors.accentBg
                                : AppColors.surfaceHigh,
                            borderRadius: BorderRadius.circular(AppRadius.md),
                          ),
                          child: Text('${r.count}',
                              style: AppFonts.mono(
                                  fontSize: 13,
                                  color: accent
                                      ? AppColors.accent
                                      : AppColors.primary)),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Icon(Icons.chevron_right,
                            size: 18, color: AppColors.muted),
                      ],
                    ),
                  ),
                ),
            const SizedBox(height: AppSpacing.sm),
          ],
        ),
      ),
    );
  }
}
