import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/styles/app_colors.dart';
import '../../../core/styles/app_spacing.dart';
import '../../../shared/widgets/bar_icon_button.dart';
import '../../../shared/widgets/dropdown_select.dart';
import '../../../shared/widgets/header_icon_button.dart';
import '../../../shared/widgets/keyboard_floor_layout.dart';
import '../../../shared/widgets/page_header.dart';
import '../../../shared/widgets/scroll_shrink_nav_bar.dart';
import '../../../shared/widgets/session_date_bar.dart';
import '../../../shared/widgets/session_exercise_card.dart';
import '../../../shared/widgets/session_set_row.dart';
import '../../../shared/widgets/undo_redo_buttons.dart';
import '../../session/model/session_local_state.dart';
import '../../session/view/ratings_sheet.dart';
import '../../session/view/session_stats_bar.dart';
import 'session_cards_screen.dart';

/// The past-session viewer, drawn statically from a lab sample (2026-11-03).
///
/// It is the real screen's furniture, element for element — the name in the
/// header with its back chevron and edit pencil, the flat exercise card on
/// the 16pt gutter, and the floor's date bar, undo/redo pair, star and
/// PR · goals · notes tiles. Nothing is wired to a database: the set rows
/// come from the sample's exercise counts, and every door that would read
/// real history is drawn but spent. The shape is the point.
class SessionLabScreen extends StatefulWidget {
  const SessionLabScreen({super.key, required this.sample});

  final SessionCardSample sample;

  static Route<void> route(SessionCardSample sample) =>
      MaterialPageRoute(builder: (_) => SessionLabScreen(sample: sample));

  @override
  State<SessionLabScreen> createState() => _SessionLabScreenState();
}

class _SessionLabScreenState extends State<SessionLabScreen> {
  int _activeIndex = 0;
  SessionDateMode _mode = SessionDateMode.exercise;

  List<String> get _names => [
    for (final (name, _, _) in widget.sample.exercises) name,
  ];

  int get _activePrs => widget.sample.exercises[_activeIndex].$3;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      resizeToAvoidBottomInset: false,
      body: Column(
        children: [
          PageHeader(
            title: widget.sample.plan ?? 'Freestyle Session',
            left: HeaderIconButton(
              icon: LucideIcons.chevronLeft,
              semanticsLabel: 'Back',
              glyphSize: 18,
              color: AppColors.primary,
              onPressed: () => Navigator.of(context).pop(),
            ),
            // The training viewer's edit door. A lab sample has nothing to
            // write, so the glyph is drawn for the shape and stays inert.
            right: HeaderIconButton(
              icon: LucideIcons.pencil,
              semanticsLabel: 'Edit session',
              glyphSize: 20,
              color: AppColors.primary,
              onPressed: () {},
            ),
          ),
          Expanded(
            child: KeyboardFloorLayout(
              page: SingleChildScrollView(
                // The live Training page's own insets — the card opens on
                // the same 22pt gutter, from the same place, with the same
                // 16 of air under the header (2026-10-22).
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: SessionExerciseCard(
                  exerciseNames: _names,
                  activeIndex: _activeIndex,
                  onSelect: (i) => setState(() => _activeIndex = i),
                  // View mode has no structural affordances.
                  onMove: null,
                  onAdd: null,
                  // The viewer's two pills are doors at every count; their
                  // sheets read real history, which a sample has none of.
                  exerciseNotesCount: 0,
                  onExerciseNotesTap: () {},
                  prCount: _activePrs,
                  onPrTap: () {},
                  // The viewer is the Training view read-only: the same
                  // flat card, with no plan rim.
                  planned: false,
                  flat: true,
                  rows: _rows(),
                  reserveAddSet: false,
                ),
              ),
              floor: _floor(context),
            ),
          ),
        ],
      ),
    );
  }

  /// The sample's sets for the active exercise: its own count of rows, the
  /// prescription repeated, and the first `prs` rows wearing the badge —
  /// enough to read the card's full height and chrome.
  List<Widget> _rows() {
    final (name, setCount, prCount) = widget.sample.exercises[_activeIndex];
    final (weight, reps) = _prescription(name);
    return [
      for (var i = 0; i < setCount; i++)
        SessionSetRow(
          key: ValueKey('$name-$i'),
          mode: SetRowMode.history,
          exerciseId: name,
          displayIndex: i + 1,
          isDraft: false,
          initialWeightText: weight == 0 ? '' : _fmtWeight(weight),
          initialRepsText: '$reps',
          initialVariationId: null,
          hasNotes: false,
          isPr: i < prCount,
          readOnly: true,
          canDelete: false,
          onCommit: (_, _, {bool immediate = false}) async {},
          onVariationChanged: (_) {},
          onNotesSave: (_) {},
          onDelete: () async {},
          onDuplicate: (_) {},
          // The row always resolves a selected variation option, so the
          // empty pick's own row must exist even when there is nothing to
          // choose from.
          variationOptions: const [
            DropdownOption<String?>(label: 'No Variation', value: null),
          ],
          allVariations: const [],
          findSimilarVariations: (_) => const [],
          submitNewVariation:
              (_, {required exerciseId, useExistingId}) async => null,
        ),
    ];
  }

  /// The floor bar the viewer wears (2026-10-22): the date bar, the
  /// undo/redo pair with its trash slot, the ratings star, and the three
  /// stat doors. The arithmetical parts are spent — a sample has no walk,
  /// no edits and no history — but every control is in its place.
  Widget _floor(BuildContext context) {
    return Container(
      key: const ValueKey('session-lab-bar'),
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        ScrollShrinkNavBar.contentInset(context),
      ),
      decoration: BoxDecoration(
        color: AppColors.bg,
        border: Border(top: BorderSide(color: AppColors.border, width: 0.5)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SessionDateBar(
            isToday: false,
            date: widget.sample.date,
            mode: _mode,
            onToggleMode: () => setState(
              () => _mode = _mode == SessionDateMode.exercise
                  ? SessionDateMode.session
                  : SessionDateMode.exercise,
            ),
            onOlder: null,
            onNewer: null,
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              UndoRedoButtons(
                canUndo: false,
                canRedo: false,
                onUndo: () {},
                onRedo: () {},
                deletedExercises: const [],
                onPickDeletedExercise: (_) {},
              ),
              const SizedBox(width: AppSpacing.sm),
              BarIconButton(
                icon: LucideIcons.star,
                semanticsLabel: 'Session ratings',
                onPressed: () => showSessionRatingsSheet(
                  context,
                  editing: false,
                  preFeeling: widget.sample.pre,
                  postFeeling: widget.sample.post,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: SessionStatsTiles(
                  prCount: _activePrs,
                  exerciseNoteCount: 0,
                  goalCount: 0,
                  onPrTap: () {},
                  onNoteTap: () {},
                  onGoalTap: () {},
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A plausible prescription per exercise, for the rows' values. Bodyweight
/// movements carry 0 and draw an empty kg cell; everything else repeats its
/// pair across the sample's set count.
const _prescriptions = <String, (double, int)>{
  'Back Squat': (100, 5),
  'Leg Press': (180, 8),
  'Leg Curl': (45, 10),
  'Leg Extension': (50, 12),
  'Calf Raise': (80, 12),
  'Hip Thrust': (120, 8),
  'Bench Press': (80, 5),
  'Cable Row': (65, 8),
  'Deadlift': (160, 3),
  'Front Squat': (90, 5),
  'Overhead Press': (50, 6),
  'Lateral Raise': (12, 12),
  'Face Pull': (25, 15),
  'Pull-ups': (0, 8),
  'Dip': (0, 10),
};

(double, int) _prescription(String exercise) =>
    _prescriptions[exercise] ?? (60, 8);

String _fmtWeight(double weight) => weight == weight.roundToDouble()
    ? weight.toInt().toString()
    : weight.toString();
