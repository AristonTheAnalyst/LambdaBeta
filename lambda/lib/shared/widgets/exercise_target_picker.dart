import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/styles/app_colors.dart';
import '../../core/styles/app_fonts.dart';
import '../../core/styles/app_radius.dart';
import '../../core/styles/app_spacing.dart';
import '../../core/styles/app_text_styles.dart';
import '../../core/utils/session_format.dart';
import '../../data/models/custom_variation.dart';
import '../../data/models/exercise_detail.dart';
import '../../data/models/goal.dart';
import '../../data/models/session_exercise_set.dart';
import '../../features/programs/model/program_achievements.dart';
import 'container_styles.dart';
import 'date_picker_sheet.dart';
import 'dropdown_select.dart';
import 'glass_button.dart';
import 'lambda_input.dart';
import 'lambda_search_field.dart';
import 'segmented_control.dart';

/// What [ExerciseTargetPicker] produced — the exercise, optionally a variation,
/// the weight × reps being chased, and the notes saying why.
///
/// A value object rather than five positional arguments: the variation is
/// optional and sits between two required values, and a callback whose third
/// parameter can mean either "no variation" or "the caller forgot" is a bug
/// waiting to be written.
///
/// Two shapes, one object (2026-10-26): a single-set target carries its one
/// pair in [weight] / [reps] and leaves [targets] empty; a multi-set target
/// carries its rungs in [targets] and leaves the pair null.
class ExerciseTarget {
  const ExerciseTarget({
    required this.exerciseId,
    required this.exerciseName,
    this.variationId,
    this.weight,
    this.reps,
    this.targets = const [],
    this.notes,
    this.targetDate,
  });

  final String exerciseId;

  /// The display name, resolved from the dims by the caller that built the
  /// map. Carried so a goal can name its lift without a second lookup.
  final String exerciseName;

  /// NULL = the exercise performed with no variation — a plain bench set, not
  /// any bench set. Its own scope, the same way the PR frontier keys one.
  final String? variationId;

  final num? weight;
  final int? reps;

  /// A multi-set goal's requirements, in the order they were listed. Empty =
  /// a single-set target.
  final List<GoalTargetSet> targets;

  /// Free prose about the target — the goal's own notes. NULL when left blank,
  /// the one spelling of "none" the goal model normalizes to.
  final String? notes;

  /// The day the goal is aimed at. NULL = no deadline.
  final DateTime? targetDate;
}

/// One requirement row after the first, in a multi-set draft (2026-10-26) —
/// a pair of cells of its own, disposed with the draft that owns them.
class TargetRowDraft {
  final weightCtrl = TextEditingController();
  final repsCtrl = TextEditingController();

  void dispose() {
    weightCtrl.dispose();
    repsCtrl.dispose();
  }
}

/// What the New Goal form has in it, owned by the host rather than the sheet
/// that draws it (2026-10-19).
///
/// A dismissed sheet — a tap outside, the back gesture — takes its widget
/// tree with it, and controllers created inside it would take the typed
/// target too. The host keeps one of these for the screen's lifetime, so
/// reopening the sheet resumes at the exercise picked, the numbers typed and
/// the date chosen. The only thing that clears it is a successful add.
class ExerciseTargetDraft {
  final weightCtrl = TextEditingController();
  final repsCtrl = TextEditingController();
  final notesCtrl = TextEditingController();

  /// Whether the form states several requirements instead of one — a
  /// multi-set goal ("100 × 5, then 110 × 3"), every one of which a session
  /// must meet with its own set (2026-10-26). The first requirement always
  /// lives in [weightCtrl] / [repsCtrl]; the rest in [extraRows].
  bool multiSet = false;

  /// The second and later requirement rows, in order. Empty in single mode
  /// and while the form states only one row.
  final List<TargetRowDraft> extraRows = [];

  /// The pick made in the exercise dropdown; null = still asking.
  String? exerciseId;

  /// The variation picked in the row's third cell; null = no variation.
  String? variationId;

  /// The day the goal is aimed at; null = no deadline.
  DateTime? targetDate;

  /// Back to a blank form — the host calls this after a goal was written, so
  /// the next New Goal starts from nothing rather than from the last one.
  void reset() {
    weightCtrl.clear();
    repsCtrl.clear();
    notesCtrl.clear();
    multiSet = false;
    _clearRows();
    exerciseId = null;
    variationId = null;
    targetDate = null;
  }

  /// Fill the form from a stored goal — the focused goal sheet's preview, and
  /// the normalization it lands on again after a save. The numbers use the
  /// same text a target reads as (`100`, not `100.0`), so the box shows what
  /// the row showed (2026-10-19).
  ///
  /// [targets] is the stored requirement list and [multiSet] chooses the
  /// shape; a single-set goal's pair arrives in [weight] / [reps] exactly as
  /// it always has (2026-10-26).
  void seed({
    String? exerciseId,
    String? variationId,
    num? weight,
    int? reps,
    List<GoalTargetSet> targets = const [],
    bool multiSet = false,
    String? notes,
    DateTime? targetDate,
  }) {
    this.exerciseId = exerciseId;
    this.variationId = variationId;
    this.multiSet = multiSet;
    _clearRows();
    if (multiSet && targets.isNotEmpty) {
      _fill(weightCtrl, repsCtrl, targets.first);
      for (final target in targets.skip(1)) {
        final row = TargetRowDraft();
        _fill(row.weightCtrl, row.repsCtrl, target);
        extraRows.add(row);
      }
    } else {
      weightCtrl.text = weight == null ? '' : goalNumberText(weight);
      repsCtrl.text = reps?.toString() ?? '';
    }
    notesCtrl.text = notes ?? '';
    this.targetDate = targetDate;
  }

  static void _fill(
    TextEditingController weightCtrl,
    TextEditingController repsCtrl,
    GoalTargetSet target,
  ) {
    weightCtrl.text = target.weight == null
        ? ''
        : goalNumberText(target.weight!);
    repsCtrl.text = target.reps?.toString() ?? '';
  }

  /// The requirement rows the form states right now, in order — a row with no
  /// numbers is dropped, because a blank cell is not a rung yet. Empty means
  /// "no numbers at all", the reading the single form has always given an
  /// empty pair.
  List<GoalTargetSet> get statedTargets {
    final out = <GoalTargetSet>[];
    void add(TextEditingController weightCtrl, TextEditingController repsCtrl) {
      final weight = double.tryParse(weightCtrl.text.trim());
      final reps = int.tryParse(repsCtrl.text.trim());
      if (weight == null && reps == null) return;
      out.add(GoalTargetSet(order: out.length + 1, weight: weight, reps: reps));
    }

    add(weightCtrl, repsCtrl);
    for (final row in extraRows) {
      add(row.weightCtrl, row.repsCtrl);
    }
    return out;
  }

  /// The cells of requirement row [index] (0 = the pair the form always
  /// draws).
  ({TextEditingController weight, TextEditingController reps}) rowAt(
    int index,
  ) => index == 0
      ? (weight: weightCtrl, reps: repsCtrl)
      : (
          weight: extraRows[index - 1].weightCtrl,
          reps: extraRows[index - 1].repsCtrl,
        );

  /// The number of rows currently drawn.
  int get rowCount => 1 + extraRows.length;

  /// Draws one more empty requirement row.
  void addRow() => extraRows.add(TargetRowDraft());

  /// Removes requirement row [index]. Removing the first promotes the next
  /// row into its cells, so the form always keeps the one pair it always
  /// draws; the last row cannot be removed.
  void removeRowAt(int index) {
    if (index == 0) {
      if (extraRows.isEmpty) return;
      final next = extraRows.removeAt(0);
      weightCtrl.text = next.weightCtrl.text;
      repsCtrl.text = next.repsCtrl.text;
      next.dispose();
      return;
    }
    if (index > extraRows.length) return;
    extraRows.removeAt(index - 1).dispose();
  }

  void _clearRows() {
    for (final row in extraRows) {
      row.dispose();
    }
    extraRows.clear();
  }

  void dispose() {
    weightCtrl.dispose();
    repsCtrl.dispose();
    notesCtrl.dispose();
    _clearRows();
  }
}

/// Composes a goal target the way a live session composes a set: the exercise
/// above, then one set row — KG · REPS · VARIATION — in the shared set-row
/// chrome, notes under it, and the ADD that commits the whole thing
/// (2026-10-19).
///
/// It was a three-column strip (search → variation → weight × reps → Add);
/// the goal sheet now speaks the session's vocabulary instead, so a reader who
/// logs sets all day meets the same cells when they say what they are chasing.
/// The row reproduces `SessionSetRow`'s recipe by hand — the 38px mono cells
/// on the page fill, the flex-2 variation cell — because a live row is wired
/// to a session's VMs and this one is a plain form. No number cell: a goal is
/// one set to beat, not a progression.
///
/// The exercise is a dropdown, the way a session picks one: a field naming the
/// pick (or asking for one), and a popover that opens over the screen —
/// search, then the catalog, anchored under the field and dismissed by a
/// scrim tap — so the list never pushes the form around. The catalog opens
/// most recently used first, as every exercise and variation picker in the
/// app does (2026-10-19). A failed write keeps the form standing, values and
/// all — the host owns the dismissal.
///
/// The form itself lives in [ExerciseTargetDraft], not in this State: the host
/// keeps it across the sheet's dismissal, so tapping outside and reopening
/// finds the work still there. And the set row answers a question a session
/// cannot: when the typed target is **already met** by the user's history, the
/// row turns green with the achieved outline and a sentence under it names the
/// day it was beaten — a tap on that sentence opens that workout (2026-10-19).
class ExerciseTargetPicker extends StatefulWidget {
  const ExerciseTargetPicker({
    super.key,
    required this.detailMap,
    required this.onAdd,
    required this.draft,
    this.variations = const [],
    this.lastUsed = const {},
    this.pastSets = const [],
    this.onOpenWorkout,
    this.enabled = true,
    this.actionLabel = 'ADD',
    this.actionEnabled,
    this.fallbackExerciseName,
    this.onOpenTargetDateHistory,
    this.showNotes = true,
    this.showAchievedNote = true,
    this.completedSet,
  });

  /// Every active exercise, by id. The picker searches it; it does not load it.
  final Map<String, ExerciseDetail> detailMap;

  /// Variations offered on the selected exercise.
  final List<CustomVariation> variations;

  /// exercise-id/variation-id → the most recent date it was trained, as
  /// `lastUsedByEntity` reads it off the timeline (ids never collide, so one
  /// map serves both). Drives the ordering: most recently used first,
  /// never-used last, then by name — the same order every exercise and
  /// variation picker in the app speaks (2026-10-19). Empty = no history, and
  /// everything falls back to the name.
  final Map<String, DateTime> lastUsed;

  /// The user's logged sets, as `loadPastSetsTimeline` reads them — the
  /// history the "already beat this" check searches. Empty = nothing has been
  /// logged, and no target is claimed as met.
  final List<PastSetRow> pastSets;

  /// Opens the workout that beat the typed target. Null = the sentence still
  /// reads, but is not tappable (a host with no route to the logs).
  /// Opens the workout that logged [PastSetRow]: the day under the target is
  /// a door, and the row carries both the workout and the exercise the
  /// caller needs to land the reader on (2026-10-20).
  final void Function(PastSetRow set)? onOpenWorkout;

  /// The form's contents, owned by the host so a dismissal does not take them
  /// (2026-10-19).
  final ExerciseTargetDraft draft;

  /// The composed target. Awaiting it lets the form hold its ADD while the
  /// write is in flight; the host decides what a success does (the add sheet
  /// pops) and what a failure says (it keeps this form up).
  final Future<void> Function(ExerciseTarget target) onAdd;

  /// Whether the form can be changed (2026-10-19). False renders it as a
  /// **reading**: the selector, the cells, the variation, the notes and the
  /// date stay exactly where they are and cannot be entered — the focused
  /// goal sheet's preview, which looks like the composer it edits without
  /// being one. The floor button stays drawn and stays disabled.
  final bool enabled;

  /// The floor button's verb — ADD on the creation sheet, SAVE on a goal.
  final String actionLabel;

  /// Decides whether the floor button may act, called on every rebuild so a
  /// host that enables it only for a real change sees the form's own
  /// keystrokes (the draft lives outside this State's setState). Null = the
  /// creation rule: an exercise has been picked.
  final bool Function()? actionEnabled;

  /// The name to show when the draft's exercise is not in [detailMap] — a
  /// goal whose exercise left the library, named by the label it kept. Null
  /// on the creation form, where a missing id is simply "pick one".
  final String? fallbackExerciseName;

  /// Opens the goal's deadline history — the time button drawn right of the
  /// date (2026-10-19). Null draws no button: the creation form has no history
  /// yet, and neither has a goal whose deadline never moved.
  final VoidCallback? onOpenTargetDateHistory;

  /// Whether the NOTES section is drawn at all. False is the record rule: a
  /// goal a completed review left nothing about gets no notes box, not even
  /// an empty one offering a prompt (2026-10-19).
  final bool showNotes;

  /// Whether the "you've already beat this" caption under the set row is
  /// drawn. True on the creation form, where it answers the target being
  /// composed; false on the focused goal sheet (2026-10-20). An existing goal
  /// does not need the question asked again — its completion is stated by
  /// [completedSet] under the deadline, where the goal's two dates live.
  final bool showAchievedNote;

  /// The set that met an existing goal, drawn as "Completed 13 Oct 2026"
  /// under the TARGET DATE field and tapping through to the workout it was
  /// logged in — the same door the creation form's caption offers
  /// (2026-10-20). Null on the creation form (nothing is stored yet) and on a
  /// goal still standing.
  final PastSetRow? completedSet;

  @override
  State<ExerciseTargetPicker> createState() => _ExerciseTargetPickerState();
}

class _ExerciseTargetPickerState extends State<ExerciseTargetPicker> {
  String _query = '';
  bool _adding = false;

  // The dropdown's machinery — the field, its anchor, and the popover in the
  // app's Overlay. The session selector's exact recipe, so the two read as the
  // same control (2026-10-19).
  final _fieldKey = GlobalKey();
  final _link = LayerLink();
  final _portal = OverlayPortalController();
  final _searchCtrl = TextEditingController();
  double _fieldWidth = 0;
  bool _open = false;

  @override
  void dispose() {
    // The typed values live in the host's draft and outlive this State — only
    // the popover's own search box is ours to put down.
    _searchCtrl.dispose();
    super.dispose();
  }

  void _close() {
    if (!_open) return;
    _portal.hide();
    // The search is the popover's own state: closing it forgets the query, so
    // reopening starts from the whole catalog rather than a stale narrowing.
    _searchCtrl.clear();
    setState(() {
      _open = false;
      _query = '';
    });
  }

  void _toggle() {
    if (!widget.enabled) return;
    if (_open) {
      _close();
      return;
    }
    final box = _fieldKey.currentContext?.findRenderObject() as RenderBox?;
    setState(() {
      _fieldWidth = box?.size.width ?? 0;
      _open = true;
    });
    _portal.show();
  }

  void _select(String exerciseId) {
    setState(() => widget.draft.exerciseId = exerciseId);
    _close();
  }

  List<MapEntry<String, String>> get _filtered {
    final detailMap = widget.detailMap;
    if (detailMap.isEmpty) return [];
    final results = detailMap.entries
        .where((e) {
          final name = e.value.name;
          return _query.isEmpty ||
              toProperCase(name).toLowerCase().contains(_query.toLowerCase());
        })
        .map((e) => MapEntry(e.key, toProperCase(e.value.name)))
        .toList();
    // Most recently used first, never-used last, names breaking ties — the
    // same recency order the add-exercise sheet and every variation picker
    // speak, so "what you did last" is always the first row (2026-10-19).
    results.sort((a, b) {
      final da = widget.lastUsed[a.key];
      final db = widget.lastUsed[b.key];
      if (da != null && db != null) {
        final byRecency = db.compareTo(da);
        if (byRecency != 0) return byRecency;
      } else if (da != null) {
        return -1;
      } else if (db != null) {
        return 1;
      }
      return a.value.toLowerCase().compareTo(b.value.toLowerCase());
    });
    return results;
  }

  /// ADD commits the whole form at once — nothing is written as it is typed,
  /// because a goal has no row to type into until it exists. On the focused
  /// sheet the same button is SAVE and the host owns the write; the form is
  /// only enterable there in edit mode, so a disabled floor means a disabled
  /// form.
  Future<void> _add() async {
    final id = widget.draft.exerciseId;
    if (!widget.enabled || id == null || _adding) return;
    final notes = widget.draft.notesCtrl.text.trim();
    final multi = widget.draft.multiSet;
    setState(() => _adding = true);
    try {
      await widget.onAdd(
        ExerciseTarget(
          exerciseId: id,
          exerciseName: _displayNameFor(id) ?? '',
          variationId: widget.draft.variationId,
          // A multi-set target has no single pair — its rungs are the target
          // (2026-10-26).
          weight: multi
              ? null
              : double.tryParse(widget.draft.weightCtrl.text.trim()),
          reps: multi ? null : int.tryParse(widget.draft.repsCtrl.text.trim()),
          targets: multi ? widget.draft.statedTargets : const [],
          notes: notes.isEmpty ? null : notes,
          targetDate: widget.draft.targetDate,
        ),
      );
    } finally {
      // A success may have popped the sheet, and this State is gone with it —
      // only a failure has a form to hand back.
      if (mounted) setState(() => _adding = false);
    }
  }

  /// The name to draw for a picked exercise: the live dim name, or the label
  /// a goal kept when its exercise left the library. Null when neither has
  /// anything to say — the creation form asking for a pick.
  String? _displayNameFor(String? id) {
    if (id == null) return widget.fallbackExerciseName;
    final detail = widget.detailMap[id];
    return detail == null
        ? widget.fallbackExerciseName
        : toProperCase(detail.name);
  }

  /// The newest thing the form asks a question of: has this exact target
  /// already been beaten? Scoped to the selected exercise × variation and
  /// judged by the one goal rule ([setReachesTarget]), so the sentence and the
  /// goals list's verdicts can never disagree. The day it names is the FIRST
  /// day the target was met — the day the goal would be completed on — not
  /// the day of the best set since (2026-10-20).
  ///
  /// Multi-set drafts answer the same question over the whole requirement
  /// list: the day named is the one the LAST rung was met, because the goal
  /// was not complete before then (2026-10-26). Null while the form is not
  /// yet a target — no exercise, or no numbers typed.
  PastSetRow? get _achievingSet {
    final exerciseId = widget.draft.exerciseId;
    if (exerciseId == null) return null;
    final List<GoalTargetSet> requirements;
    if (widget.draft.multiSet) {
      requirements = widget.draft.statedTargets;
    } else {
      final weight = double.tryParse(widget.draft.weightCtrl.text.trim());
      final reps = int.tryParse(widget.draft.repsCtrl.text.trim());
      if (weight == null && reps == null) return null;
      requirements = [GoalTargetSet(weight: weight, reps: reps)];
    }
    if (requirements.isEmpty) return null;
    final witnesses = goalWitnessSets(
      sets: widget.pastSets,
      exerciseId: exerciseId,
      variationId: widget.draft.variationId,
      requirements: requirements,
    );
    if (witnesses == null || witnesses.isEmpty) return null;
    // The completion set is the latest witness — the rung that finished it.
    var latest = witnesses.first;
    for (final set in witnesses.skip(1)) {
      final byDate = set.sessionCreatedDate.compareTo(
        latest.sessionCreatedDate,
      );
      if (byDate > 0 || (byDate == 0 && set.setNumber > latest.setNumber)) {
        latest = set;
      }
    }
    return latest;
  }

  /// Opens the app's own calendar under the sheet. A pick writes to the draft —
  /// still nothing on the goal, which does not exist yet. The clear × on the
  /// field is the way back to "no deadline".
  Future<void> _pickTargetDate() async {
    if (!widget.enabled) return;
    final now = DateTime.now();
    final picked = await showDatePickerSheet(
      context,
      initial: widget.draft.targetDate ?? now,
      firstDate: DateTime(now.year - 2, 1, 1),
      lastDate: DateTime(now.year + 5, 12, 31),
      title: 'TARGET DATE',
    );
    if (picked == null || !mounted) return;
    setState(() => widget.draft.targetDate = dateOnly(picked));
  }

  /// Options are rebuilt from the live variation list each build, so an
  /// archived variation simply stops being offered — a goal already naming one
  /// still reads, because its id is what was stored.
  ///
  /// Most recently used first, the way every variation picker in the app
  /// orders them (the set row's included): never-used names after it,
  /// alphabetically. "No variation" leads because it is the absence of a
  /// pick, not an entry competing on recency (2026-10-19).
  List<DropdownOption<String?>> get _variationOptions {
    final sorted = CustomVariation.sortByLastUsed([
      for (final v in widget.variations)
        // A variation already picked stays in the list even after it is
        // archived: the goal naming it must still read as its name, not as
        // "No variation". Everything else offers only what is live.
        if (!v.isArchived || v.variationId == widget.draft.variationId) v,
    ], widget.lastUsed);
    return [
      const DropdownOption(label: 'No variation', value: null),
      for (final v in sorted)
        DropdownOption(label: v.name, value: v.variationId),
    ];
  }

  @override
  Widget build(BuildContext context) {
    // Recomputed every build: the sentence below the row and the row's own
    // green answer must follow the numbers and the variation as they change.
    final achieved = _achievingSet;
    // A host's rule when it has one (the goal sheet enables SAVE only for a
    // change); the creation rule otherwise — an exercise has been picked.
    final canAct =
        widget.actionEnabled?.call() ?? (widget.draft.exerciseId != null);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _exerciseSelector(),
        const SizedBox(height: AppSpacing.md),
        // The shape is the user's to choose, and a reading keeps the one the
        // goal was written with — so the switch is only drawn where it can be
        // used (2026-10-26).
        if (widget.enabled) ...[
          _modeToggle(),
          const SizedBox(height: AppSpacing.md),
        ],
        _gridHeaders(),
        const SizedBox(height: 6),
        if (widget.draft.multiSet)
          _multiSetRows()
        else
          _setRow(achieved: achieved != null),
        if (achieved != null && widget.showAchievedNote) ...[
          const SizedBox(height: AppSpacing.sm),
          _achievedNote(achieved),
        ],
        // A record whose goal carried no notes gets no section at all — an
        // empty box under a NOTES header would promise a place to write
        // (2026-10-19).
        if (widget.showNotes) ...[
          const SizedBox(height: AppSpacing.lg),
          _sectionLabel('NOTES'),
          const SizedBox(height: AppSpacing.sm),
          LambdaInput(
            controller: widget.draft.notesCtrl,
            minLines: 2,
            maxLines: 4,
            // The sheet's ground is `surface` — the box steps up one tier, the
            // rule every text box follows (convention 11).
            elevated: true,
            enabled: widget.enabled,
            placeholder: 'Why this goal, or what to watch…',
            textCapitalization: TextCapitalization.sentences,
            // The host's dirty check reads the notes, so a keystroke asks this
            // form to rebuild even though it draws the text itself.
            onChanged: (_) => setState(() {}),
          ),
        ],
        // The date comes after the notes: what the goal is, then why it
        // matters, then when it should be done (2026-10-19).
        const SizedBox(height: AppSpacing.lg),
        _sectionLabel('TARGET DATE'),
        const SizedBox(height: AppSpacing.sm),
        _targetDateField(),
        // The stored goal's completion reads beneath the deadline it answered
        // (2026-10-20): the goal's two dates, one above the other, and the
        // completed one opens the workout that hit it — the creation form's
        // caption's own door, offered by the goal rather than by a draft.
        if (widget.completedSet != null) ...[
          const SizedBox(height: AppSpacing.sm),
          _completedNote(widget.completedSet!),
        ],
        const SizedBox(height: AppSpacing.xl),
        GlassButton(
          label: widget.actionLabel,
          solid: true,
          disabled: _adding || !canAct,
          onPressed: _add,
        ),
      ],
    );
  }

  Widget _sectionLabel(String text) => Text(
    text,
    style: AppFonts.mono(
      fontSize: AppTextStyles.xs,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.8,
      color: AppColors.primary,
    ),
  );

  /// The sentence under a green row: the day the typed target was already
  /// beaten, and — when the host has somewhere to go — a tap into that
  /// workout. The add sheet stays mounted under the pushed page, so coming
  /// back lands on this form with the draft untouched.
  Widget _achievedNote(PastSetRow set) => _successNote(
    key: const ValueKey('goal-already-achieved'),
    label: "You've already beat this on ${_dayOf(set)}",
    onTap: _openWorkoutFor(set),
  );

  /// The completed half of a stored goal, under the deadline it answered —
  /// the same row the creation form explains its target with, saying the day
  /// the goal was met instead (2026-10-20). Tapping it opens the workout,
  /// exactly like the creation form's caption: the date is a door, not a
  /// label.
  Widget _completedNote(PastSetRow set) => _successNote(
    key: const ValueKey('goal-completed-on'),
    label: 'Completed ${_dayOf(set)}',
    onTap: _openWorkoutFor(set),
  );

  String _dayOf(PastSetRow set) =>
      DateFormat('d MMM yyyy').format(set.sessionCreatedDate.toLocal());

  VoidCallback? _openWorkoutFor(PastSetRow set) {
    final open = widget.onOpenWorkout;
    return open == null ? null : () => open(set);
  }

  Widget _successNote({
    required Key key,
    required String label,
    required VoidCallback? onTap,
  }) => GestureDetector(
    key: key,
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      // The success tint without the outline the row above wears — this is
      // the row's caption, not a second card.
      decoration: BoxDecoration(
        color: AppColors.successBg,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.circleCheck, size: 14, color: AppColors.success),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: AppFonts.ui(
                fontSize: AppTextStyles.sm,
                fontWeight: FontWeight.w600,
                color: AppColors.success,
              ),
            ),
          ),
          if (onTap != null)
            Icon(LucideIcons.chevronRight, size: 16, color: AppColors.success),
        ],
      ),
    ),
  );

  /// The deadline field — the block editor's date field recipe (glass, the
  /// date or the ask, and a × back to none). Tapping opens the app's own
  /// calendar over the sheet; nothing is written until ADD. In a reading the
  /// tap and the × are gone with the edit it would start.
  ///
  /// The history button (a clock, right of the date) is the one control that
  /// survives the reading: looking at what the deadline used to be is reading
  /// too, so it stays where the host wired it whatever the mode (2026-10-19).
  Widget _targetDateField() {
    final date = widget.draft.targetDate;
    final enabled = widget.enabled;
    return GestureDetector(
      key: const ValueKey('goal-target-date'),
      onTap: enabled ? _pickTargetDate : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: glassBox(AppColors.primary),
        child: Row(
          children: [
            Icon(
              LucideIcons.calendar,
              size: 16,
              color: date == null ? AppColors.muted : AppColors.primary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                date == null
                    ? 'No target date'
                    : DateFormat('d MMM yyyy').format(date),
                style: AppFonts.ui(
                  fontSize: AppTextStyles.sm,
                  fontWeight: date == null ? FontWeight.w500 : FontWeight.w700,
                  color: date == null
                      ? AppColors.inkSecondary
                      : AppColors.primary,
                ),
              ),
            ),
            if (widget.onOpenTargetDateHistory != null) ...[
              const SizedBox(width: 12),
              GestureDetector(
                key: const ValueKey('goal-target-date-history'),
                onTap: widget.onOpenTargetDateHistory,
                behavior: HitTestBehavior.opaque,
                child: Icon(LucideIcons.history, size: 16, color: AppColors.muted),
              ),
            ],
            if (enabled && date != null)
              GestureDetector(
                key: const ValueKey('goal-target-date-clear'),
                onTap: () => setState(() => widget.draft.targetDate = null),
                child: Padding(
                  padding: const EdgeInsets.only(left: 10),
                  child: Icon(LucideIcons.x, size: 16, color: AppColors.muted),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// The exercise dropdown — the session selector's field and popover, minus
  /// the reorder arrows (there is only ever one exercise here).
  ///
  /// The field names the pick (or asks for one); the popover opens under it in
  /// the app's Overlay, so the catalog floats over the sheet instead of
  /// pushing the form down (2026-10-19).
  Widget _exerciseSelector() {
    final id = widget.draft.exerciseId;
    final name = _displayNameFor(id);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CompositedTransformTarget(
          link: _link,
          child: GestureDetector(
            key: const ValueKey('goal-exercise-selector'),
            onTap: widget.enabled ? _toggle : null,
            child: Container(
              key: _fieldKey,
              // The session selector's field chrome, exactly: glass compact,
              // radius md, the rotating chevron.
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: glassBox(AppColors.primary),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      name ?? 'Pick exercise',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppFonts.ui(
                        fontSize: AppTextStyles.sm,
                        fontWeight: FontWeight.w700,
                        color: name == null
                            ? AppColors.inkSecondary
                            : AppColors.primary,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  AnimatedRotation(
                    turns: _open ? 0.5 : 0,
                    duration: const Duration(milliseconds: 150),
                    child: Icon(
                      LucideIcons.chevronDown,
                      size: 16,
                      color: name == null ? AppColors.muted : AppColors.primary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        // Anchored under the field via the LayerLink — exact field width,
        // capped height, scrollable rows. The scrim takes the first tap
        // anywhere outside, so the popover dismisses without closing the
        // sheet under it.
        OverlayPortal(
          controller: _portal,
          overlayChildBuilder: (context) => _open
              ? Stack(
                  children: [
                    Positioned.fill(
                      child: GestureDetector(
                        onTap: _close,
                        child: Container(
                          color: Colors.black.withValues(alpha: 0.2),
                        ),
                      ),
                    ),
                    CompositedTransformFollower(
                      link: _link,
                      targetAnchor: Alignment.bottomLeft,
                      followerAnchor: Alignment.topLeft,
                      offset: const Offset(0, 4),
                      child: Container(
                        width: _fieldWidth,
                        constraints: const BoxConstraints(maxHeight: 260),
                        decoration: lambdaBox(
                          ContainerTone.surface,
                          radius: AppRadius.md,
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
                              child: LambdaSearchField(
                                controller: _searchCtrl,
                                autofocus: true,
                                showIcon: true,
                                // The panel's ground is `surface` — the search
                                // box steps up one tier (convention 11).
                                elevated: true,
                                hint: 'Search exercises…',
                                onChanged: (v) => setState(() => _query = v),
                              ),
                            ),
                            Flexible(child: _popoverRows()),
                          ],
                        ),
                      ),
                    ),
                  ],
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }

  /// The catalog inside the popover: most recently used first, filtered by
  /// the search, with the current pick highlighted. A miss says so rather
  /// than drawing an empty panel.
  Widget _popoverRows() {
    final results = _filtered;
    if (results.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Text(
          'No exercises found',
          textAlign: TextAlign.center,
          style: AppFonts.ui(
            fontSize: AppTextStyles.sm,
            color: AppColors.inkSecondary,
          ),
        ),
      );
    }
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
      children: [
        for (final entry in results)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: GestureDetector(
              onTap: () => _select(entry.key),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 9,
                ),
                // The current pick wears the selector's glass highlight; the
                // rest are bare rows, as in the session's popover.
                decoration: entry.key == widget.draft.exerciseId
                    ? glassBox(AppColors.primary)
                    : null,
                child: Text(
                  entry.value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppFonts.ui(
                    fontSize: AppTextStyles.sm,
                    fontWeight: entry.key == widget.draft.exerciseId
                        ? FontWeight.w700
                        : FontWeight.w500,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// The KG/REPS/VARIATION column labels — the session grid's own header, so
  /// the row under them reads as the same object (mono, spaced, muted).
  Widget _gridHeaders() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          Expanded(child: _colLabel('KG')),
          const SizedBox(width: 6),
          Expanded(child: _colLabel('REPS')),
          const SizedBox(width: 6),
          Expanded(flex: 2, child: _colLabel('VARIATION')),
        ],
      ),
    );
  }

  Widget _colLabel(String text) => Text(
    text,
    textAlign: TextAlign.center,
    style: AppFonts.mono(
      fontSize: 14,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.6,
      color: AppColors.primary,
    ),
  );

  /// One target or a list of them. The subtle treatment: this is a mode of the
  /// form, not the form's action (2026-10-26).
  Widget _modeToggle() => SegmentedControl<bool>(
    subtle: true,
    options: const [
      SegmentOption(label: 'Single set', value: false),
      SegmentOption(label: 'Multi-set', value: true),
    ],
    value: widget.draft.multiSet,
    onChange: (value) => setState(() => widget.draft.multiSet = value),
  );

  /// The multi-set form: one numbered row per requirement, an × on every row
  /// that can go, and the ADD SET under them. Every row draws the variation
  /// cell against the draft's one value — a goal names one variation, so the
  /// cell is shared rather than per row.
  Widget _multiSetRows() {
    final count = widget.draft.rowCount;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < count; i++) ...[
          if (i > 0) const SizedBox(height: 6),
          _multiRow(i),
        ],
        if (widget.enabled) ...[
          const SizedBox(height: AppSpacing.sm),
          Align(
            alignment: Alignment.centerLeft,
            child: GlassButton(
              label: 'Add set',
              icon: LucideIcons.plus,
              compact: true,
              onPressed: () => setState(widget.draft.addRow),
            ),
          ),
        ],
      ],
    );
  }

  /// One numbered requirement row — the set row's chrome, prefixed by its
  /// place in the list and followed by the × that drops it (2026-10-26).
  Widget _multiRow(int index) {
    final cells = widget.draft.rowAt(index);
    final removable = widget.enabled && widget.draft.rowCount > 1;
    return Container(
      key: ValueKey('goal-set-row-$index'),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 14,
            child: Text(
              '${index + 1}',
              textAlign: TextAlign.center,
              style: AppFonts.mono(
                fontSize: AppTextStyles.xs,
                fontWeight: FontWeight.w700,
                color: AppColors.inkSecondary,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: _cell(
              key: ValueKey('goal-kg-$index'),
              controller: cells.weight,
              decimal: true,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: _cell(
              key: ValueKey('goal-reps-$index'),
              controller: cells.reps,
              decimal: false,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(flex: 2, child: _variationCell()),
          if (removable) ...[
            const SizedBox(width: 4),
            GestureDetector(
              key: ValueKey('goal-set-remove-$index'),
              onTap: () => setState(() => widget.draft.removeRowAt(index)),
              behavior: HitTestBehavior.opaque,
              child: SizedBox(
                width: 40,
                height: 40,
                child: Icon(LucideIcons.x, size: 16, color: AppColors.muted),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// One set row, in the live set row's exact chrome — `surfaceHigh`, radius
  /// 8, a 0.5 hairline, 6px gaps. No number cell: a goal is one set to beat,
  /// so the row is only the target itself — KG · REPS · VARIATION.
  ///
  /// [achieved] swaps the chrome for [successBox]: the typed target is already
  /// in the user's history, and the row says so before the sentence under it
  /// is read (2026-10-19).
  Widget _setRow({required bool achieved}) {
    return Container(
      key: const ValueKey('goal-set-row'),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: achieved
          ? successBox()
          : BoxDecoration(
              color: AppColors.surfaceHigh,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: AppColors.border, width: 0.5),
            ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: _cell(
              key: const ValueKey('goal-kg'),
              controller: widget.draft.weightCtrl,
              decimal: true,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: _cell(
              key: const ValueKey('goal-reps'),
              controller: widget.draft.repsCtrl,
              decimal: false,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(flex: 2, child: _variationCell()),
        ],
      ),
    );
  }

  /// A reps/kg cell — mono, centred, on the page fill, numeric-only. The same
  /// field the live session shows, down to the dash hint.
  ///
  /// Every keystroke rebuilds the form: the achieved sentence is a verdict on
  /// what is typed, and a value that starts beating a logged set must turn the
  /// row green as it is entered. In a reading the cell keeps its value and
  /// drops its caret and keyboard.
  Widget _cell({
    Key? key,
    required TextEditingController controller,
    required bool decimal,
  }) {
    final enabled = widget.enabled;
    return SizedBox(
      height: 38,
      child: TextField(
        key: key,
        controller: controller,
        readOnly: !enabled,
        showCursor: enabled,
        enableInteractiveSelection: enabled,
        textAlign: TextAlign.center,
        keyboardType: TextInputType.numberWithOptions(decimal: decimal),
        inputFormatters: [
          if (decimal)
            FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*$'))
          else
            FilteringTextInputFormatter.digitsOnly,
        ],
        onChanged: (_) => setState(() {}),
        style: AppFonts.mono(
          fontSize: 15,
          fontWeight: FontWeight.w500,
          color: AppColors.primary,
        ),
        decoration: InputDecoration(
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 8),
          hintText: '—',
          hintStyle: AppFonts.mono(
            fontSize: 14,
            color: AppColors.muted.withValues(alpha: 0.6),
          ),
          filled: true,
          fillColor: AppColors.bg,
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: BorderSide(color: AppColors.border, width: 0.5),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: BorderSide(color: AppColors.primary, width: 1.5),
          ),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
        ),
      ),
    );
  }

  Widget _variationCell() {
    return Container(
      height: 38,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      // The picker opens a sheet of its own, so the reading is closed at the
      // pointer rather than by greying the value out.
      child: IgnorePointer(
        ignoring: !widget.enabled,
        // The same full-width cell as the session set row's variation field:
        // the dropdown's compact row is only as wide as its label and
        // chevron, so it is stretched to the box to make the whole field the
        // target (2026-10-25).
        child: SizedBox(
          width: double.infinity,
          child: DropdownSelect<String?>(
            options: _variationOptions,
            value: widget.draft.variationId,
            placeholder: 'No Variation',
            compact: true,
            valueColor: AppColors.primary,
            onChange: (v) => setState(() => widget.draft.variationId = v),
          ),
        ),
      ),
    );
  }
}

/// A goal's one-line target description: "Bench — 5 × 100 kg".
///
/// Shared so the goal list, the goal sheet and the review sheet describe a
/// target identically — the same reason [ExerciseTargetPicker] exists.
String goalTargetLabel(String exerciseName, num? weight, int? reps) {
  final target = goalTargetValue(weight, reps);
  return target.isEmpty ? exerciseName : '$exerciseName — $target';
}

/// A multi-set goal's line: the exercise and every rung, "Bench — 100 kg × 5 ·
/// 110 kg × 3" (2026-10-26). The plural of [goalTargetLabel].
String goalTargetsLabel(String exerciseName, List<GoalTargetSet> targets) {
  final target = goalRequirementsValue(targets);
  return target.isEmpty ? exerciseName : '$exerciseName — $target';
}

/// A requirement list as one target value — "100 kg × 5 · 110 kg × 3".
///
/// The one reading of the multi-set shape's numbers, shared by the goal card,
/// the review rows and the summary tiles. A single requirement renders exactly
/// as [goalTargetValue] does, so the lists describe a goal the same way
/// whichever storage shape holds it (2026-10-26). Empty when no requirement
/// states a number.
String goalRequirementsValue(List<GoalTargetSet> targets) {
  final parts = <String>[];
  for (final target in targets) {
    final value = goalTargetValue(target.weight, target.reps);
    if (value.isNotEmpty) parts.add(value);
  }
  return parts.join(' · ');
}

/// The target alone — "100 kg × 5", empty when neither number was recorded —
/// without the exercise's name.
///
/// Weight first, then reps (2026-10-22): the set grid is read KG · REPS, and
/// every surface that names a set says it the same way — the PR row's
/// "100kg × 5", the log's line, this target. The order is shared by every
/// surface that names a target, so none of them can read the pair backwards.
/// Beside a weight the reps read bare — "100 kg × 5", the way a lifter writes
/// it down; alone they keep their noun, because a bare "5" with nothing next
/// to it would state a number and no meaning.
///
/// For the surfaces that draw the name and the target as two elements rather
/// than glue them into one string with a dash: the review pickers' rows align
/// the values in their own column (2026-10-10).
String goalTargetValue(num? weight, int? reps) {
  final parts = <String>[];
  if (weight != null) parts.add('${goalNumberText(weight)} kg');
  if (reps != null) {
    parts.add(weight == null ? '$reps rep${reps == 1 ? '' : 's'}' : '$reps');
  }
  return parts.join(' × ');
}

/// A goal's number as text — "100", never "100.0". Shared by the target label
/// and the form's seeded cells, so a stored target reads back exactly as it
/// was written.
String goalNumberText(num n) =>
    n == n.roundToDouble() ? n.toInt().toString() : '$n';
