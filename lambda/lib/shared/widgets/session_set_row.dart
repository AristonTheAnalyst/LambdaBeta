import 'package:flutter/material.dart';

import 'package:flutter/services.dart';
import '../../core/styles/app_colors.dart';
import '../../core/styles/app_fonts.dart';
import '../../core/styles/app_radius.dart';
import '../../core/utils/planned_target.dart';
import './container_styles.dart';
import '../../data/models/planned_session_exercise_set.dart';
import '../../data/models/program_content.dart';
import '../../features/session/view/notes_modal.dart';
import '../utils/pop_dialog.dart';
import 'dropdown_select.dart';
import 'swipe_actions.dart';
import 'user_name_text.dart';
import 'variation_name_dialog.dart';

/// Which kind of set data this row edits — the one shared row for the live
/// session, the planner, and the past-session viewer. The mode derives all
/// per-context behavior (input formatter, cell tint, draft materialization,
/// duplicate guard, container styling) so the three screens can never drift.
enum SetRowMode {
  /// Logged live set — numeric input, ghost planned-target overlay.
  live,

  /// Planned target set — free-text range input ("8-15", "60-70"),
  /// planned styling (the field itself IS the plan, so no ghost).
  planned,

  /// Logged set in the past-session viewer — numeric input; read-only
  /// cells in view mode.
  history,
}

/// A set drawn as a **record** — a completed review's snapshot of it, or the
/// pass's Compare flip reading it back. Read only, and structurally so: the
/// swipe drawer is not drawn at all, and `readOnly` keeps every callback from
/// firing, which is why the inert closures below are the whole plumbing.
///
/// One builder, two readers (the Compare flip in `plan_session_screen.dart`,
/// the record's workout screen). A read-only row that drifts from the other
/// read-only row is exactly the kind of copy this shared file exists to
/// prevent.
///
/// The variation lists are the **caller's**, because they are the library's: a
/// record stores an id, and the label drawn here comes from the live names.
SessionSetRow recordSetRow({
  required ContentSet set,
  required int index,
  required String exerciseId,
  required Map<String, String> variationNames,
  required List<DropdownOption<String?>> variationOptions,
  required List<({String id, String name})> allVariations,
}) => SessionSetRow(
  key: ValueKey(set.plannedSetId),
  mode: SetRowMode.planned,
  // The row's own plumbing, unused by a read-only row — a record's exercise
  // may have no id at all (a free tab), and the column would be empty then.
  exerciseId: exerciseId,
  displayIndex: index + 1,
  isDraft: false,
  initialWeightText: set.targetWeight ?? '',
  initialRepsText: set.targetReps ?? '',
  initialVariationId: set.variationId,
  initialVariationName: variationNames[set.variationId],
  initialNotes: set.targetNotes,
  hasNotes: set.targetNotes?.isNotEmpty ?? false,
  readOnly: true,
  onCommit: (isDraft, values, {bool immediate = false}) async {},
  onVariationChanged: (_) {},
  onNotesSave: (_) {},
  onDelete: () async {},
  onDuplicate: (_) {},
  variationOptions: variationOptions,
  allVariations: allVariations,
  findSimilarVariations: (_) => const [],
  submitNewVariation: (name, {required exerciseId, useExistingId}) async =>
      null,
);

/// Normalized commit payload — raw trimmed text; null means empty/cleared.
/// The screen's closure parses to its VM's own types (double/num vs String).
class SetRowFieldValues {
  const SetRowFieldValues({
    this.weight,
    this.reps,
    this.variationId,
    this.notes,
  });

  final String? weight;
  final String? reps;
  final String? variationId;
  final String? notes;
}

/// One row of the exercise card's set grid — either an already-persisted set
/// (editable in place) or an unsaved draft row. The shared implementation
/// behind the live session, the planner, and the past-session viewer; all
/// VM-specific work happens in the screen-provided callbacks.
class SessionSetRow extends StatefulWidget {
  const SessionSetRow({
    super.key,
    required this.mode,
    required this.exerciseId,
    required this.displayIndex,
    required this.isDraft,
    this.dragIndex,
    // Value seeds (screens compute, incl. live's numeric-planned-weight
    // prefill and the snapshot variation name for read-only display):
    required this.initialWeightText,
    required this.initialRepsText,
    required this.initialVariationId,
    this.initialVariationName,
    this.initialNotes,
    required this.hasNotes,
    // Ghost target (live only; null elsewhere):
    this.plannedTarget,
    // Orthogonal state:
    this.isPr = false,
    this.isGoal = false,
    this.readOnly = false,
    this.deleted = false,
    // ── History-edit gate (the history viewer's tap-to-edit confirm) ──
    // A non-null [onEditConfirm] puts the row in gate mode: it renders
    // read-only until [editConfirmed] turns true, and any tap on a field
    // (reps/kg/variation/notes) first shows the one-time "you're about to
    // edit past data" dialog. Gate-mode rows never expose swipe actions —
    // the history viewer edits values, it doesn't delete past sets.
    this.editConfirmed = false,
    this.onEditConfirm,
    // ── Pending-edit flush (live only) ──
    // The row registers its commit closure so the screen's VM can flush
    // in-flight edits on lifecycle pause / tab switch / session end —
    // commit is otherwise blur-only and typed values would be lost.
    this.onRegisterCommit,
    this.onUnregisterCommit,
    // ── Bridge callbacks (screen closures over its VM) ──
    required this.onCommit,
    required this.onVariationChanged,
    required this.onNotesSave,
    required this.onDelete,
    required this.onDuplicate,
    // ── Variation create-new flow (the row owns exact-match + the
    // did-you-mean dialog — one copy) ──
    required this.variationOptions,
    required this.allVariations,
    required this.findSimilarVariations,
    required this.submitNewVariation,
  });

  final SetRowMode mode;
  final String exerciseId;
  final int displayIndex;
  final bool isDraft;

  /// The row's index in the card's reorderable list — non-null makes the
  /// number cell the hold-and-drag handle. Null on rows that cannot move:
  /// drafts (no id to key a move on) and every read-only surface.
  final int? dragIndex;

  final String initialWeightText;
  final String initialRepsText;
  final String? initialVariationId;
  final String? initialVariationName;
  final String? initialNotes;
  final bool hasNotes;

  final PlannedSessionExerciseSet? plannedTarget;
  final bool isPr;

  /// The set that achieved a goal (2026-10-20): the container fills
  /// [AppColors.successBg] with a [AppColors.success] outline, and the
  /// number cell reads `G` instead of the set's number — the exact shape
  /// [isPr] draws in accent.
  ///
  /// A set can be both a goal's achieving set and a PR. The goal treatment
  /// is what is DRAWN (it outranks the PR's, and the row shows `G`, not
  /// `PR`), while the PR itself still counts everywhere PRs are counted —
  /// the stats tile and the PR modal. Visually a goal set, schematically
  /// both.
  final bool isGoal;
  final bool readOnly;

  /// A soft-deleted row (flag `is_deleted`) in the past-session viewer: the
  /// container and its text draw in [AppColors.danger] on [AppColors.dangerBg],
  /// and the row is read-only whatever the mode — the deletion is a fact
  /// being shown, and the restore happens at the exercise's own button
  /// (2026-10-14). Outranks the PR and planned treatments.
  final bool deleted;

  /// See the constructor doc — gate mode is the history viewer's
  /// tap-to-edit confirm; a non-null [onEditConfirm] enables it.
  final VoidCallback? onEditConfirm;
  final bool editConfirmed;

  final void Function(Future<void> Function())? onRegisterCommit;
  final void Function(Future<void> Function())? onUnregisterCommit;

  /// Commit: `(isDraft, values, {immediate})`. Draft commits also carry the
  /// row-local variation and notes; real-set commits carry weight/reps only
  /// (variation/notes go through [onVariationChanged]/[onNotesSave]).
  ///
  /// [immediate] separates the two commit classes (2026-10-13): keystroke
  /// commits (`immediate: false`) are debounce-eligible — the caller merges
  /// them into one write per settle. Blur and the registered flush handle
  /// commit with `immediate: true`, which must write now, so navigation and
  /// lifecycle can never lose a typed value. A caller with no debounce
  /// (the planner) simply ignores the flag.
  final Future<void> Function(
    bool isDraft,
    SetRowFieldValues values, {
    bool immediate,
  })
  onCommit;

  /// Variation dropdown change on a REAL set — the screen maps null to
  /// clearVariation. Drafts keep the variation row-locally.
  final void Function(String? variationId) onVariationChanged;

  /// Notes modal save on a REAL set. Drafts keep notes row-locally.
  final void Function(String notes) onNotesSave;

  final Future<void> Function() onDelete;

  /// Duplicate, carrying the row's CURRENT weight/reps text — the copy must
  /// carry what is on screen, not the seed values a debounced write may not
  /// have settled yet (2026-10-13).
  final void Function(SetRowFieldValues values) onDuplicate;

  /// 'No Variation' first, then all the user's variations.
  final List<DropdownOption<String?>> variationOptions;

  /// Every known variation — the exact-match check reuses an existing id.
  final List<({String id, String name})> allVariations;

  final List<({String id, String name, int exerciseCount})> Function(
    String name,
  )
  findSimilarVariations;

  final Future<String?> Function(
    String name, {
    required String exerciseId,
    String? useExistingId,
  })
  submitNewVariation;

  @override
  State<SessionSetRow> createState() => _SessionSetRowState();
}

class _SessionSetRowState extends State<SessionSetRow> {
  late final TextEditingController _weightCtrl;
  late final TextEditingController _repsCtrl;
  final _weightFocus = FocusNode();
  final _repsFocus = FocusNode();
  String? _draftVariationId;
  String? _draftNotes;

  /// A keystroke since the seeds last moved has queued a debounced write.
  /// Reverting to the seed text within the settle window must supersede that
  /// write, or the stale value lands while the field shows the seed.
  bool _hasPendingCommit = false;

  bool get _isDraft => widget.isDraft;

  /// Gate mode (the history viewer): the row renders read-only until the
  /// screen's one-time "you're about to edit past data" confirm flips
  /// [SessionSetRow.editConfirmed].
  bool get _gated => widget.onEditConfirm != null && !widget.editConfirmed;

  bool get _effectiveReadOnly => widget.readOnly || _gated || widget.deleted;

  /// Real (non-draft) rows commit on every keystroke — the value is
  /// recognized as it's being typed, so navigating away (back, switching
  /// exercises, ending) can never lose it. Keystroke commits are
  /// debounce-eligible (`immediate: false`) — the caller merges them into
  /// one write per settle — while blur and the flush handle commit now, so
  /// the safety net is unchanged. Drafts stay blur/flush committed: a
  /// keystroke must not materialize a draft mid-typing (that would replace
  /// the row and drop the field's focus).
  bool get _commitOnChange => !_effectiveReadOnly && !_isDraft;

  /// Planned styling applies to planner rows always (the fields ARE the
  /// targets), and to live rows while the row still FOLLOWS the plan
  /// (2026-10-23): a real value that contradicts a parseable target retires
  /// the tint, a value that meets it keeps it. Empty cells don't deviate;
  /// non-numeric targets ("AMRAP", "3 RIR") constrain nothing; the variation
  /// counts as planned when it is null or the plan's. Notes are a remark, not
  /// a value — they never retire the tint. Controllers are read because they
  /// track keystrokes before the commit reload lands. (Only evaluated inside
  /// build(), so the late controllers are initialized.)
  bool get _isPlannedRow {
    if (widget.mode == SetRowMode.planned) return true;
    if (widget.mode != SetRowMode.live || widget.plannedTarget == null) {
      return false;
    }
    final target = widget.plannedTarget!;
    final variationPlanned = _isDraft
        ? _draftVariationId == null
        : (widget.initialVariationId == null ||
              widget.initialVariationId == target.variationId);
    return variationPlanned &&
        weightInPlan(
          target.targetWeight,
          num.tryParse(_weightCtrl.text.trim()),
        ) &&
        repsInPlan(target.targetReps, num.tryParse(_repsCtrl.text.trim()));
  }

  @override
  void initState() {
    super.initState();
    _weightCtrl = TextEditingController(text: widget.initialWeightText);
    _repsCtrl = TextEditingController(text: widget.initialRepsText);
    // Drafts keep their variation row-local until commit; the planned
    // variation is a hint on the ghost target, never a preset value.
    if (_isDraft && widget.mode == SetRowMode.live) {
      _draftVariationId = widget.plannedTarget?.variationId;
    }
    if (!widget.readOnly) {
      _weightFocus.addListener(() {
        if (!_weightFocus.hasFocus) _commit(immediate: true);
      });
      _repsFocus.addListener(() {
        if (!_repsFocus.hasFocus) _commit(immediate: true);
      });
    }
    widget.onRegisterCommit?.call(_flushHandle);
  }

  @override
  void didUpdateWidget(SessionSetRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The element can be reused across VM reloads (same ValueKey). When the
    // seeds change externally — a commit reload, a re-paired ghost — re-seed
    // non-focused cells so stale controller text can't re-commit old values
    // into the row.
    if (!_weightFocus.hasFocus &&
        widget.initialWeightText != oldWidget.initialWeightText) {
      _weightCtrl.text = widget.initialWeightText;
      _hasPendingCommit = false;
    }
    if (!_repsFocus.hasFocus &&
        widget.initialRepsText != oldWidget.initialRepsText) {
      _repsCtrl.text = widget.initialRepsText;
      _hasPendingCommit = false;
    }
    if (_isDraft &&
        widget.plannedTarget?.variationId !=
            oldWidget.plannedTarget?.variationId) {
      _draftVariationId = widget.plannedTarget?.variationId;
    }
  }

  @override
  void dispose() {
    widget.onUnregisterCommit?.call(_flushHandle);
    _weightCtrl.dispose();
    _repsCtrl.dispose();
    _weightFocus.dispose();
    _repsFocus.dispose();
    super.dispose();
  }

  /// The registered commit handle — a method (not a closure) so register
  /// and unregister match by identity: a `() => _commit(immediate: true)`
  /// wrapper would be a different tear-off every call, while a method
  /// tear-off of the same instance is stable. Flush = commit now: tab
  /// switches, page changes, lifecycle pause and session end all flush
  /// through this, and a debounce timer must not outlive them.
  Future<void> _flushHandle() => _commit(immediate: true);

  Future<void> _commit({bool immediate = false}) async {
    // A gated row's fields are read-only until the confirm flips — nothing
    // can be pending, so never write.
    if (_effectiveReadOnly) return;
    final weightText = _weightCtrl.text.trim();
    final repsText = _repsCtrl.text.trim();

    if (_isDraft) {
      // The mode's materialization rule — what makes a draft real:
      switch (widget.mode) {
        case SetRowMode.live:
          // Weight, reps, or a variation present (a reps-only planned row
          // stays a ghost).
          final weight = weightText.isEmpty
              ? null
              : double.tryParse(weightText);
          final reps = repsText.isEmpty ? null : num.tryParse(repsText);
          if (weight == null && reps == null && _draftVariationId == null) {
            return;
          }
        case SetRowMode.history:
          // Reps required.
          if (repsText.isEmpty) return;
        case SetRowMode.planned:
          // Commits only when the user entered something — a fully empty
          // draft stays a draft (blurring an untouched row used to persist
          // junk target rows with no values).
          if (weightText.isEmpty &&
              repsText.isEmpty &&
              _draftVariationId == null &&
              (_draftNotes?.trim().isNotEmpty ?? false) == false) {
            return;
          }
          break;
      }
      await widget.onCommit(
        true,
        SetRowFieldValues(
          weight: weightText.isEmpty ? null : weightText,
          reps: repsText.isEmpty ? null : repsText,
          variationId: _draftVariationId,
          notes: _draftNotes?.trim().isEmpty == true
              ? null
              : _draftNotes?.trim(),
        ),
        immediate: immediate,
      );
      return;
    }

    // Real set: the text is back where it started. Plain focus/blur with no
    // edit writes nothing — but if a keystroke already queued a debounced
    // write, this submit supersedes it: reverting 65 → 60 within the settle
    // window must leave 60 stored, not let the stale 65 land behind a field
    // that reads 60 (2026-10-23). A cosmetic re-format ("100" → "100.0")
    // still commits; the VM write is a harmless no-op.
    final atSeed =
        weightText == widget.initialWeightText &&
        repsText == widget.initialRepsText;
    if (atSeed && !_hasPendingCommit) return;
    _hasPendingCommit = !atSeed;
    await widget.onCommit(
      false,
      SetRowFieldValues(
        weight: weightText.isEmpty ? null : weightText,
        reps: repsText.isEmpty ? null : repsText,
      ),
      immediate: immediate,
    );
  }

  /// A keystroke repaints before it commits: the chip and the row tint are
  /// read off the controllers in build(), so the value's planned styling has
  /// to flip on the keystroke rather than whenever the row reloads — the
  /// commit itself settles on the debounce.
  void _onCellChanged(String _) {
    setState(() {});
    _commit();
  }

  /// The history viewer's tap-to-edit gate: while gated, any field tap
  /// shows the one-time "you're about to edit past data" confirm. On
  /// continue the screen's [SessionSetRow.onEditConfirm] flips the gate,
  /// the row rebuilds editable, and [focus] receives focus — or [after]
  /// runs post-frame (once the row has rebuilt editable — e.g. the notes
  /// modal, which must open in editable mode).
  Future<void> _requestGateEdit({FocusNode? focus, VoidCallback? after}) async {
    if (!_gated) {
      focus?.requestFocus();
      after?.call();
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(
          'Edit past data?',
          style: TextStyle(color: AppColors.primary),
        ),
        content: Text(
          "You're about to update past data — this changes your historical record for this workout, including any PRs based on it.",
          style: TextStyle(color: AppColors.inkSecondary, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              'Cancel',
              style: TextStyle(color: AppColors.inkSecondary),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              'Continue',
              style: TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    widget.onEditConfirm!();
    if (focus != null) {
      focus.requestFocus();
    } else if (after != null) {
      // Wait for the confirm rebuild so the row (and any modal it opens)
      // is in editable mode.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) after();
      });
    }
  }

  void _openNotes() {
    // The planned note is a pending hint — show it only while no actual
    // note exists (drafts track their note row-locally).
    final hasActualNote = _isDraft
        ? (_draftNotes?.trim().isNotEmpty ?? false)
        : widget.hasNotes;
    showNotesModal(
      context,
      setIndex: widget.displayIndex,
      initialValue: (_isDraft ? _draftNotes : widget.initialNotes) ?? '',
      plannedNote: widget.mode == SetRowMode.live && !hasActualNote
          ? widget.plannedTarget?.targetNotes
          : null,
      readOnly: _effectiveReadOnly,
      onSave: (value) {
        if (_isDraft) {
          setState(() => _draftNotes = value);
        } else {
          widget.onNotesSave(value);
        }
      },
    );
  }

  Future<void> _delete() => widget.onDelete();

  Future<void> _duplicate() async {
    if (_isDraft) return; // nothing persisted yet to copy
    // A duplicate of an empty row is a deliberate act — the user tapped the
    // button on THAT row. Empty rows are valid (user-added rows persist even
    // unfilled), and the old "empty placeholder can't be duplicated" guard
    // made the button silently do nothing on planned/materialized ghost rows
    // (2026-10-13). The copy carries whatever the row shows, nothing more.
    // Persist the on-screen text first — the copy must carry what the user
    // just typed, not the stale seed values — then hand the same text to
    // the caller for the copied row.
    await _commit(immediate: true);
    if (!mounted) return;
    widget.onDuplicate(
      SetRowFieldValues(
        weight: _weightCtrl.text.trim().isEmpty
            ? null
            : _weightCtrl.text.trim(),
        reps: _repsCtrl.text.trim().isEmpty ? null : _repsCtrl.text.trim(),
      ),
    );
  }

  /// Wired as the variation dropdown's create-new handler. [query] is
  /// whatever the user had typed in the picker's search box — empty if they
  /// tapped "New Variation" without typing, in which case a small dialog
  /// collects the name instead.
  Future<void> _handleCreateVariation(String query) async {
    final typed = query.trim();
    final name = typed.isNotEmpty ? typed : await _promptForVariationName();
    if (name == null || name.trim().isEmpty || !mounted) return;
    final trimmed = name.trim();

    // An exact-name match is reused and silently bridged to this exercise —
    // variations are shared across exercises, so this is not a duplicate.
    final exact = widget.allVariations
        .where((v) => v.name.trim().toLowerCase() == trimmed.toLowerCase())
        .firstOrNull;

    String? useExistingId = exact?.id;
    if (exact == null) {
      final similar = widget.findSimilarVariations(trimmed);
      if (similar.isNotEmpty) {
        final choice = await _showDidYouMeanDialog(trimmed, similar);
        if (choice == null || !mounted) return; // cancelled
        if (!choice.createNew) useExistingId = choice.existingId;
      }
    }

    final id = await widget.submitNewVariation(
      trimmed,
      exerciseId: widget.exerciseId,
      useExistingId: useExistingId,
    );
    if (id == null || !mounted) return;
    if (_isDraft) {
      setState(() => _draftVariationId = id);
    } else {
      widget.onVariationChanged(id);
    }
  }

  Future<({bool createNew, String? existingId})?> _showDidYouMeanDialog(
    String typedName,
    List<({String id, String name, int exerciseCount})> similar,
  ) {
    return showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(
          'Did you mean?',
          style: TextStyle(color: AppColors.primary),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final s in similar)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: GestureDetector(
                  onTap: () =>
                      popDialog(ctx, (createNew: false, existingId: s.id)),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: lambdaBox(
                      ContainerTone.ghost,
                      radius: AppRadius.md,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: UserNameText(
                            s.name,
                            style: TextStyle(
                              color: AppColors.accent,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Text(
                          '${s.exerciseCount} exercise${s.exerciseCount == 1 ? '' : 's'}',
                          style: TextStyle(
                            color: AppColors.inkSecondary,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              'Cancel',
              style: TextStyle(color: AppColors.inkSecondary),
            ),
          ),
          TextButton(
            onPressed: () =>
                popDialog(ctx, (createNew: true, existingId: null)),
            child: Text(
              'Create "$typedName" anyway',
              style: TextStyle(
                color: AppColors.accent,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<String?> _promptForVariationName() {
    return showDialog<String>(
      context: context,
      builder: (_) => const VariationNameDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final variationId = _isDraft
        ? _draftVariationId
        : widget.initialVariationId;

    // Drafts track notes row-locally; real sets report through [hasNotes].
    final hasNotes = _isDraft
        ? (_draftNotes?.trim().isNotEmpty ?? false)
        : widget.hasNotes;

    final variationLabel = widget.variationOptions
        .firstWhere(
          (o) => o.value == variationId,
          orElse: () => widget.variationOptions.first,
        )
        .label;

    // The read-only variation cell's label: the row's own snapshot name
    // where it has one, so a variation archived since the session is still
    // readable on the record; "No Variation" is the live cell's own word
    // for the empty pick.
    final readOnlyVariationLabel = variationId != null
        ? (widget.initialVariationName ?? '')
        : 'No Variation';

    // The planned variation is a REAL VALUE, never a guide (2026-10-23): a
    // variation is categorical — the plan names the one the set is performed
    // with, and the row's first commit adopts it (live_exercise_card's
    // `onCommit`). Until that write lands the cell still shows the plan's
    // name, in real-value ink — not the blue guide the kg/reps targets wear.
    final plannedVariationName =
        !_isDraft &&
            widget.mode == SetRowMode.live &&
            variationId == null &&
            widget.plannedTarget?.variationName != null
        ? widget.plannedTarget!.variationName
        : null;

    // A deleted row never took the plan's variation: the cell still names it
    // as a guide, so what the set was meant to do survives the deletion
    // (2026-10-23).
    final deletedVariationGuide =
        widget.deleted && plannedVariationName != null
        ? plannedVariationName
        : null;

    // Planned targets are raw text — ranges ("8-15", "60-70") show as-is.
    final plannedWeight = widget.plannedTarget?.targetWeight;
    final plannedReps = widget.plannedTarget?.targetReps;

    // The container's edge styling — a goal set wears the shared achieved
    // chrome (successBox, the same green the New Goal form turns when history
    // already beats the target — 2026-10-19), which outranks a PR's accent:
    // the row can be both, and the goal is the rarer fact (2026-10-20). Then
    // PR rows get the accent, then planned rows the planned tint; deleted
    // rows wear the shared danger recipe instead (deletedBox, the same chrome
    // the exercise selector's deleted name draws — 2026-10-14).
    final borderColor = widget.isPr
        ? AppColors.accent
        : _isPlannedRow
        ? AppColors.planned.withValues(alpha: 0.35)
        : AppColors.border;
    final borderWidth = widget.isPr ? 1.2 : 0.5;

    Widget row = Container(
      // Stable chrome key so tests can read the row's tint/edges.
      key: ValueKey(
        'session-set-row-${widget.mode.name}-'
        '${widget.isDraft ? 'draft' : 'set'}-${widget.displayIndex}',
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: widget.deleted
          ? deletedBox()
          : widget.isGoal
          ? successBox()
          : BoxDecoration(
              color: widget.isPr
                  ? AppColors.accentBg
                  : _isPlannedRow
                  ? AppColors.plannedBg
                  : AppColors.surfaceHigh,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: borderColor, width: borderWidth),
            ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _numberCell(),
          const SizedBox(width: 6),
          // The grid reads KG · REPS · VARIATION — weight first, then reps,
          // the way every PR, goal and log line in the app names a set
          // ("100 kg × 5"). The order was REPS-first once; it is flipped
          // everywhere at once so no surface can read the pair backwards
          // (2026-10-22).
          Expanded(
            child: _cell(
              // Stable per-row cell keys so driver/tooling can target an
              // exact row's field (mode prefix keeps them unique across the
              // live/planned/history surfaces).
              key: ValueKey(
                '${widget.mode.name}-${widget.isDraft ? 'draft' : 'set'}-${widget.displayIndex}-kg',
              ),
              controller: _weightCtrl,
              focusNode: _weightFocus,
              ghost:
                  widget.mode == SetRowMode.live &&
                  plannedWeight != null &&
                  _weightCtrl.text.trim().isEmpty,
              hint: plannedWeight ?? '—',
              // The chip: a real weight equal to a single planned number.
              // A weight range is a guide and never chips.
              planValue:
                  widget.mode == SetRowMode.live &&
                  weightIsPlan(
                    plannedWeight,
                    num.tryParse(_weightCtrl.text.trim()),
                  ),
              onTap: _gated
                  ? () => _requestGateEdit(focus: _weightFocus)
                  : null,
              onChanged: _commitOnChange ? _onCellChanged : null,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: _cell(
              key: ValueKey(
                '${widget.mode.name}-${widget.isDraft ? 'draft' : 'set'}-${widget.displayIndex}-reps',
              ),
              controller: _repsCtrl,
              focusNode: _repsFocus,
              ghost:
                  widget.mode == SetRowMode.live &&
                  plannedReps != null &&
                  _repsCtrl.text.trim().isEmpty,
              hint: plannedReps ?? '—',
              // The chip: a typed rep count equal to the planned number or
              // inside its inclusive range. Reps are never adopted, so this
              // always reads the user's own entry.
              planValue:
                  widget.mode == SetRowMode.live &&
                  repsMatchPlan(
                    plannedReps,
                    num.tryParse(_repsCtrl.text.trim()),
                  ),
              onTap: _gated ? () => _requestGateEdit(focus: _repsFocus) : null,
              onChanged: _commitOnChange ? _onCellChanged : null,
            ),
          ),
          const SizedBox(width: 6),
          // Tooltip so long variation names stay visible even though the
          // cell truncates them. Twice the kg/reps width — number cells
          // only need ~4 digits, variation names need the room.
          Expanded(
            flex: 2,
            child: _effectiveReadOnly
                ? GestureDetector(
                    // Gated rows gate on tap — the variation field is a
                    // field like any other in the history viewer.
                    onTap: _gated ? () => _requestGateEdit() : null,
                    child: Tooltip(
                      message: readOnlyVariationLabel,
                      child: widget.deleted
                          // A deleted row is red and inert as ONE surface —
                          // no inner boxes inside its danger fill. The plan's
                          // variation still shows as a blue guide when the
                          // row never took one.
                          ? Center(
                              child: Text(
                                deletedVariationGuide ?? readOnlyVariationLabel,
                                textAlign: TextAlign.center,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppFonts.ui(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color: deletedVariationGuide != null
                                      ? AppColors.planned
                                      : AppColors.danger,
                                ),
                              ),
                            )
                          // The live cell's box, drawn without its picker:
                          // a past session's row and a live one read as the
                          // same grid (2026-10-22). Same label, same ink,
                          // same chevron as DropdownSelect's compact row.
                          : _variationBox(
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Flexible(
                                    child: UserNameText(
                                      readOnlyVariationLabel,
                                      style: AppFonts.ui(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                        color: variationId != null
                                            ? AppColors.primary
                                            : AppColors.inkSecondary,
                                      ),
                                    ),
                                  ),
                                  Icon(
                                    Icons.keyboard_arrow_down,
                                    size: 14,
                                    color: AppColors.muted,
                                  ),
                                ],
                              ),
                            ),
                    ),
                  )
                : Tooltip(
                    // The tooltip names what the cell DRAWS — the plan's
                    // variation while the row has none of its own.
                    message: plannedVariationName ?? variationLabel,
                    child: _variationBox(
                      DropdownSelect<String?>(
                        options: widget.variationOptions,
                        value: variationId,
                        placeholder: plannedVariationName ?? 'No Variation',
                        // Real-value ink: a planned variation IS the row's
                        // value, not a target to reach (2026-10-23). The
                        // dropdown's own placeholder grey stays for the
                        // genuine "No Variation" case.
                        placeholderColor: plannedVariationName != null
                            ? AppColors.primary
                            : null,
                        compact: true,
                        valueColor: AppColors.primary,
                        createNewLabel: 'New Variation',
                        onCreateNew: _handleCreateVariation,
                        onChange: (id) {
                          if (_isDraft) {
                            setState(() => _draftVariationId = id);
                          } else {
                            widget.onVariationChanged(id);
                          }
                        },
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );

    // The note indicator — a white vertical line at the right edge of the
    // row's background. The note itself opens from the swipe actions.
    if (hasNotes) {
      row = Stack(
        children: [
          row,
          Positioned(
            right: 2,
            top: 7,
            bottom: 7,
            child: Container(
              width: 3,
              decoration: BoxDecoration(
                color: widget.deleted ? AppColors.danger : AppColors.primary,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ],
      );
    }

    if (widget.onEditConfirm != null) {
      // The history viewer's rows: swipe reveals ONLY Note — past data can't
      // be duplicated or deleted, but notes stay editable through the same
      // one-time confirm gate as the field edits.
      row = SwipeActions(
        borderRadius: AppRadius.md,
        actions: [
          SwipeAction(
            icon: Icons.sticky_note_2_outlined,

            color: AppColors.primary,
            foreground: AppColors.bg,
            onTap: _gated
                ? () => _requestGateEdit(after: _openNotes)
                : _openNotes,
          ),
        ],
        child: row,
      );
    } else if (!_effectiveReadOnly) {
      row = SwipeActions(
        borderRadius: AppRadius.md,
        actions: [
          if (!_isDraft)
            SwipeAction(
              icon: Icons.copy_rounded,

              color: AppColors.accent,
              foreground: AppColors.accentText,
              onTap: _duplicate,
            ),
          SwipeAction(
            icon: Icons.sticky_note_2_outlined,

            color: AppColors.primary,
            foreground: AppColors.bg,
            onTap: _openNotes,
          ),
          SwipeAction(
            icon: Icons.delete_outline,

            color: AppColors.danger,
            foreground: AppColors.dangerText,
            onTap: _delete,
          ),
        ],
        child: row,
      );
    } else {
      // Plain read-only rows (the past-session viewer's view mode, the
      // training-page preview): swipe reveals ONLY Note, every row — the
      // modal renders read-only too.
      row = SwipeActions(
        borderRadius: AppRadius.md,
        actions: [
          SwipeAction(
            icon: Icons.sticky_note_2_outlined,

            color: AppColors.primary,
            foreground: AppColors.bg,
            onTap: _openNotes,
          ),
        ],
        child: row,
      );
    }

    return Padding(padding: const EdgeInsets.only(bottom: 6), child: row);
  }

  /// The set number — and, when [SessionSetRow.dragIndex] is set, the handle
  /// for reordering: hold it to lift the row, drag, drop.
  ///
  /// The label rolls on change, because a drop renumbers every row between
  /// the lifted row's old and new slot at once and a bare text swap would read
  /// as the grid flickering rather than as the sets resequencing.
  ///
  /// Both numbers travel the same way — the arriving one up into place, the
  /// one it replaces carrying on up and out — so the column turns like an
  /// odometer, and neither number is ever seen standing still beside the
  /// other. The walk is paced to be followed by eye: quick enough to still
  /// read as the tail end of the drop, slow enough not to flicker.
  Widget _numberCell() {
    // A goal set reads `G`, a PR `PR` — and a set that is both reads `G`:
    // the badge says which chrome the row wears, and the goal's is the one
    // drawn. The PR still counts in the stats and the PR modal, so nothing
    // is lost by the number cell speaking the goal (2026-10-20).
    final badge = widget.deleted
        ? null
        : widget.isGoal
        ? 'G'
        : widget.isPr
        ? 'PR'
        : null;
    final ValueKey<String> numberKey = badge == 'G'
        ? const ValueKey('goal')
        : badge == 'PR'
        ? const ValueKey('pr')
        : ValueKey('set-${widget.displayIndex}');

    Widget label = AnimatedSwitcher(
      duration: const Duration(milliseconds: 260),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        // The child on its way out runs this same animation backwards, so its
        // tween is the mirror of the incoming one: same direction of travel,
        // leaving where the next one comes from.
        final bool arriving = child.key == numberKey;
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: Offset(0, arriving ? 0.5 : -0.5),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          ),
        );
      },
      child: badge != null
          ? Text(
              badge,
              key: numberKey,
              style: AppFonts.mono(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: badge == 'G' ? AppColors.success : AppColors.accent,
              ),
            )
          : Text(
              '${widget.displayIndex}',
              key: numberKey,
              style: AppFonts.mono(
                fontSize: 13,
                color: widget.deleted
                    ? AppColors.danger
                    : AppColors.inkSecondary,
              ),
            ),
    );

    // The cell is as tall as the input cells beside it, so the hold target is
    // the whole number column rather than the digits. The fill is what makes
    // it one: `ReorderableDelayedDragStartListener` wraps a bare Listener,
    // which hit-tests only where something painted.
    Widget cell = Container(
      width: 26,
      height: 38,
      color: Colors.transparent,
      alignment: Alignment.center,
      child: label,
    );

    if (widget.dragIndex == null) return cell;

    return ReorderableDelayedDragStartListener(
      index: widget.dragIndex!,
      child: cell,
    );
  }

  /// The variation cell's box — one chrome recipe for the picker and its
  /// read-only twin, so a past session's row and a live one read as the same
  /// grid (2026-10-22). Neutral chrome: a planned variation is a REAL value
  /// shown in `primary` (2026-10-23), and only the two numeric cells carry
  /// the value chip.
  Widget _variationBox(Widget child) => Container(
    height: 38,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: AppColors.bg,
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: AppColors.border, width: 0.5),
    ),
    child: child,
  );

  /// The reps/kg cell. Ghost = live's planned-target overlay — the planned
  /// hint TEXT in planned color, the plan as a **guide only**.
  ///
  /// [planValue] is the other half of the grammar (2026-10-23): a REAL value
  /// that is what was planned — white ink on the solid plannedFill chip. A
  /// real value off the plan stays neutral with primary ink. A deleted row is
  /// one red surface and never chips.
  ///
  /// A read-only cell keeps the box (2026-10-22): the past-session viewer is
  /// the live grid, not a bare-number list. Only a deleted row drops the
  /// inner chrome, because the whole row is one red surface.
  Widget _cell({
    Key? key,
    required TextEditingController controller,
    required FocusNode focusNode,
    required bool ghost,
    required String hint,
    bool planValue = false,
    VoidCallback? onTap,
    ValueChanged<String>? onChanged,
  }) {
    return SizedBox(
      height: 38,
      child: TextField(
        key: key,
        controller: controller,
        onChanged: onChanged,
        focusNode: focusNode,
        readOnly: _effectiveReadOnly,
        onTap: onTap,
        textAlign: TextAlign.center,
        keyboardType: widget.mode == SetRowMode.planned
            // Free text — planned targets can be ranges ("8-15", "60-70").
            ? const TextInputType.numberWithOptions(decimal: true, signed: true)
            : const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [
          FilteringTextInputFormatter.allow(
            RegExp(
              widget.mode == SetRowMode.planned
                  ? r'^[0-9.\-\s]*$'
                  : r'^\d*\.?\d*$',
            ),
          ),
        ],
        style: AppFonts.mono(
          fontSize: 15,
          fontWeight: FontWeight.w500,
          // A deleted row's values read red — the deletion is the row's
          // whole surface, text included. A planned chip's ink is plannedText
          // (white everywhere, AA on every plannedFill).
          color: widget.deleted
              ? AppColors.danger
              : planValue
              ? AppColors.plannedText
              : AppColors.primary,
        ),
        decoration: InputDecoration(
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 8),
          hintText: hint,
          hintStyle: AppFonts.mono(
            fontSize: 14,
            color: ghost
                ? AppColors.planned
                : widget.deleted
                ? AppColors.danger.withValues(alpha: 0.6)
                : AppColors.muted.withValues(alpha: 0.6),
          ),
          filled: true,
          fillColor: widget.deleted
              ? Colors.transparent
              : planValue
              ? AppColors.plannedFill
              : AppColors.bg,
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: BorderSide(
              // The chip's edge is `planned`, not its own fill: the lighter
              // signal clears 3:1 against the planned row ground in every
              // palette, while the fill stays deep enough to carry white ink.
              color: widget.deleted
                  ? Colors.transparent
                  : planValue
                  ? AppColors.planned
                  : AppColors.border,
              width: 0.5,
            ),
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
}
