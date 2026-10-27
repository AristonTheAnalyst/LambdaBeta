import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/styles/app_colors.dart';
import '../../../core/styles/app_fonts.dart';
import '../../../core/styles/app_radius.dart';
import '../../../core/styles/app_spacing.dart';
import '../../../data/models/session_exercise_set.dart';
import '../../../shared/widgets/container_styles.dart';
import '../../../shared/widgets/dropdown_select.dart';
import '../../../shared/widgets/exercise_selector.dart';
import '../../../shared/widgets/header_icon_button.dart';
import '../../../shared/widgets/page_header.dart';
import '../../../shared/widgets/pr_event_row.dart';
import '../../../shared/widgets/scroll_shrink_nav_bar.dart';
import '../../../shared/widgets/session_exercise_card.dart';
import '../../../shared/widgets/session_set_row.dart';
import '../../../shared/widgets/undo_redo_buttons.dart';
import '../pr_history_fixture.dart';
import 'pr_history_sheet.dart';

/// The live session stage with dumb data — PR History's test bench
/// (2026-10-21).
///
/// Nothing here touches the database or a viewmodel: the card is the shared
/// `SessionExerciseCard` over hard-coded sets, and the only live control is
/// the PRs pill, which opens [showPrHistorySheet] for the exercise on
/// screen. Everything else is scenery that keeps the stage looking like the
/// real Training page.
class PrHistoryDemoScreen extends StatefulWidget {
  const PrHistoryDemoScreen({super.key});

  @override
  State<PrHistoryDemoScreen> createState() => _PrHistoryDemoScreenState();
}

class _PrHistoryDemoScreenState extends State<PrHistoryDemoScreen> {
  int _activeIndex = 0;

  DemoExercise get _exercise => kDemoExercises[_activeIndex];

  void _openHistory() {
    showPrHistorySheet(
      context,
      exerciseName: _exercise.name,
      prs: demoPrsFor(_exercise.id),
    );
  }

  @override
  Widget build(BuildContext context) {
    final exercise = _exercise;
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Column(
        children: [
          PageHeader(
            // The real Training header names a planned session here; a
            // freestyle demo has no template to name.
            title: 'Freestyle Session',
            left: HeaderIconButton(
              icon: Icons.arrow_back_ios_new,
              semanticsLabel: 'Back',
              glyphSize: 18,
              color: AppColors.primary,
              onPressed: () => context.pop(),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.md,
                AppSpacing.lg,
                AppSpacing.lg,
              ),
              child: SessionExerciseCard(
                key: ValueKey(exercise.id),
                exerciseNames: [for (final e in kDemoExercises) e.name],
                // A freestyle session's exercises are all beyond any plan —
                // the live card marks them with the green plus.
                exerciseMarks: [
                  for (final _ in kDemoExercises) ExerciseMark.added,
                ],
                activeIndex: _activeIndex,
                onSelect: (index) => setState(() => _activeIndex = index),
                onMove: null,
                onAdd: null,
                exerciseNotesCount: 0,
                onExerciseNotesTap: null,
                // What this session added — the pill's "+2 PRs" — while the
                // feed it opens stays all-time.
                prCount: demoSessionPrsFor(exercise.id),
                onPrTap: _openHistory,
                rows: _rowsFor(exercise),
                // Kept present (greyed would hide it) so the grid has the
                // live shape; the demo has nothing to add a set to.
                onAddSet: () {},
              ),
            ),
          ),
          Container(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.sm,
              AppSpacing.lg,
              ScrollShrinkNavBar.contentInset(context),
            ),
            decoration: BoxDecoration(
              color: AppColors.bg,
              border: Border(
                top: BorderSide(color: AppColors.border, width: 0.5),
              ),
            ),
            child: Row(
              children: [
                UndoRedoButtons(
                  canUndo: false,
                  canRedo: false,
                  onUndo: () {},
                  onRedo: () {},
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: _DemoStatsBar(
                    sessionPrs: kDemoSessionPrCount,
                    onTapPrs: _openHistory,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Today's sets as the shared live rows. The callbacks are inert — the row
  /// keeps its live chrome (which `readOnly` alone would not preserve), but
  /// nothing typed here is stored anywhere.
  List<Widget> _rowsFor(DemoExercise exercise) => [
    for (final set in demoSessionRows(exercise.id))
      SessionSetRow(
        key: ValueKey(set.sessionExerciseSetId),
        mode: SetRowMode.live,
        exerciseId: exercise.id,
        displayIndex: set.setNumber,
        isDraft: false,
        initialWeightText: formatPrNumber(set.weight ?? 0),
        initialRepsText: _repsText(set),
        initialVariationId: set.variationId,
        initialVariationName: set.variationName,
        hasNotes: false,
        isPr: kDemoSessionPrSetIds.contains(set.sessionExerciseSetId),
        onCommit: (isDraft, values, {bool immediate = false}) async {},
        onVariationChanged: (_) {},
        onNotesSave: (_) {},
        onDelete: () async {},
        onDuplicate: (_) {},
        variationOptions: _variationOptions,
        allVariations: _allVariations,
        findSimilarVariations: (_) => const [],
        submitNewVariation:
            (name, {required exerciseId, useExistingId}) async => null,
      ),
  ];

  String _repsText(PastSetRow set) =>
      set.reps.isEmpty ? '' : formatPrNumber(set.reps.first);
}

const _variationOptions = <DropdownOption<String?>>[
  DropdownOption(label: 'No Variation', value: null),
  DropdownOption(
    label: kDemoPausedVariationName,
    value: kDemoPausedVariationId,
  ),
];

const _allVariations = <({String id, String name})>[
  (id: kDemoPausedVariationId, name: kDemoPausedVariationName),
];

/// The live `SessionStatsBar` is bound to a `SessionViewModel`, which the
/// demo deliberately has none of. This copies its two-tile recipe for the
/// stage — dev-only scenery, not a shared widget. The PRS tile opens the
/// history; the live tile opens the session PR breakdown.
class _DemoStatsBar extends StatelessWidget {
  const _DemoStatsBar({required this.sessionPrs, required this.onTapPrs});

  final int sessionPrs;
  final VoidCallback onTapPrs;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _tile(
            key: const ValueKey('demo-prs-tile'),
            label: 'PRS',
            value: '$sessionPrs',
            highlighted: sessionPrs > 0,
            onTap: onTapPrs,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: _tile(
            key: const ValueKey('demo-notes-tile'),
            label: 'NOTES',
            value: '0',
            highlighted: false,
          ),
        ),
      ],
    );
  }

  /// `_summaryTile`'s recipe, verbatim: an accent glass tile when there is
  /// something to show, a plain surface tile when there is not.
  Widget _tile({
    Key? key,
    required String label,
    required String value,
    required bool highlighted,
    VoidCallback? onTap,
  }) {
    final color = AppColors.accent;
    final tile = Container(
      key: key,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: highlighted
          ? glassBox(color)
          : BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: AppColors.border, width: 0.5),
            ),
      // Scale-to-fit so a narrow stage narrows the line rather than
      // overflowing it (the goal card's squeeze, 2026-10-20). A no-op at the
      // tile's natural size.
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '$label:',
              style: AppFonts.mono(
                fontSize: 13,
                letterSpacing: 0.8,
                color: highlighted ? color : AppColors.muted,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              value,
              style: AppFonts.mono(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: highlighted ? color : AppColors.primary,
              ),
            ),
          ],
        ),
      ),
    );
    if (onTap == null) return tile;
    return GestureDetector(onTap: onTap, child: tile);
  }
}
