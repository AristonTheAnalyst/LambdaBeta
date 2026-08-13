import 'package:flutter/material.dart';
import '../../../core/styles/app_colors.dart';
import '../../../core/styles/app_fonts.dart';
import '../../../core/styles/app_radius.dart';
import '../../../core/styles/app_spacing.dart';
import '../../../core/styles/app_text_styles.dart';
import '../../../core/utils/session_format.dart';
import '../../../shared/widgets/slide_up_modal.dart';
import '../viewmodel/session_viewmodel.dart';
import 'lessons_modal.dart';

/// PRS / LESSONS — always visible at the bottom of the active workout.
/// Both tiles are tappable: PRS opens the session PR breakdown, LESSONS
/// opens the session lessons breakdown. Rows navigate to the exercise
/// within the session (lessons also opens that exercise's lessons modal).
class SessionStatsBar extends StatelessWidget {
  const SessionStatsBar({super.key, required this.vm});

  final SessionViewModel vm;

  /// Explicit PR records grouped by (exerciseId, variationId) — one entry
  /// per row of the PR breakdown.
  List<({String exerciseId, String? variationId, String label, int count})>
      _prBreakdown() {
    final groups = <(String, String?), List<dynamic>>{};
    final varNames = <(String, String?), String>{};
    for (final p in vm.prsThisSession) {
      groups.putIfAbsent((p.exerciseId, p.variationId), () => []).add(p);
      if (p.variationName != null && p.variationName!.isNotEmpty) {
        varNames.putIfAbsent((p.exerciseId, p.variationId), () => p.variationName!);
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
        final count = vm.lessonsFor(exerciseId).length;
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
            exerciseId: exerciseId,
            exerciseName: toProperCase(vm.exerciseDisplayName(exerciseId)),
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
        final prs = vm.prsThisSession.length;
        final lessons =
            vm.exerciseSlots.fold<int>(0, (sum, slot) {
              var s = sum;
              for (final exerciseId in slot.exerciseIds) {
                s += vm.lessonsFor(exerciseId).length;
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
  /// Label and value sit side by side so the tile stays short.
  Widget _summaryTile({
    required String label,
    required String value,
    required bool highlighted,
    Color? highlightColor,
    Color? highlightBg,
    VoidCallback? onTap,
  }) {
    final color = highlightColor ?? AppColors.accent;
    final bg = highlightBg ?? AppColors.accentBg;
    final tile = Container(
      padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 4),
      decoration: BoxDecoration(
        color: highlighted ? bg : AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: highlighted ? color : AppColors.border,
          width: highlighted ? 1.2 : 0.5,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(label,
              style: AppFonts.mono(
                  fontSize: 15,
                  letterSpacing: 0.8,
                  color: highlighted ? color : AppColors.muted)),
          const SizedBox(width: 6),
          Text(value,
              style: AppFonts.mono(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
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
  });

  final String title;
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
                            color: AppColors.accentBg,
                            borderRadius: BorderRadius.circular(AppRadius.md),
                          ),
                          child: Text('${r.count}',
                              style: AppFonts.mono(
                                  fontSize: 11, color: AppColors.accent)),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Icon(Icons.chevron_right,
                            size: 16, color: AppColors.muted),
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
