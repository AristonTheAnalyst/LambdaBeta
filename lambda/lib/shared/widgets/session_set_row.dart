import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/styles/app_colors.dart';
import '../../core/styles/app_fonts.dart';
import '../../core/styles/app_radius.dart';
import './container_styles.dart';
import '../../data/models/planned_session_exercise_set.dart';
import '../../features/session/view/notes_modal.dart';
import '../utils/pop_dialog.dart';
import 'dropdown_select.dart';
import 'swipe_actions.dart';
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
    this.readOnly = false,
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

  final String initialWeightText;
  final String initialRepsText;
  final String? initialVariationId;
  final String? initialVariationName;
  final String? initialNotes;
  final bool hasNotes;

  final PlannedSessionExerciseSet? plannedTarget;
  final bool isPr;
  final bool readOnly;

  /// See the constructor doc — gate mode is the history viewer's
  /// tap-to-edit confirm; a non-null [onEditConfirm] enables it.
  final VoidCallback? onEditConfirm;
  final bool editConfirmed;

  final void Function(Future<void> Function())? onRegisterCommit;
  final void Function(Future<void> Function())? onUnregisterCommit;

  /// Commit on blur: `(isDraft, values)`. Draft commits also carry the
  /// row-local variation and notes; real-set commits carry weight/reps only
  /// (variation/notes go through [onVariationChanged]/[onNotesSave]).
  final Future<void> Function(bool isDraft, SetRowFieldValues values)
      onCommit;

  /// Variation dropdown change on a REAL set — the screen maps null to
  /// clearVariation. Drafts keep the variation row-locally.
  final void Function(String? variationId) onVariationChanged;

  /// Notes modal save on a REAL set. Drafts keep notes row-locally.
  final void Function(String notes) onNotesSave;

  final Future<void> Function() onDelete;
  final VoidCallback onDuplicate;

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

  bool get _isDraft => widget.isDraft;

  /// Gate mode (the history viewer): the row renders read-only until the
  /// screen's one-time "you're about to edit past data" confirm flips
  /// [SessionSetRow.editConfirmed].
  bool get _gated => widget.onEditConfirm != null && !widget.editConfirmed;

  bool get _effectiveReadOnly => widget.readOnly || _gated;

  /// Real (non-draft) rows commit on every keystroke — the value is
  /// recognized as it's being typed, so navigating away (back, switching
  /// exercises, ending) can never lose it. Drafts stay blur/ flush
  /// committed: a keystroke must not materialize a draft mid-typing
  /// (that would replace the row and drop the field's focus).
  bool get _commitOnChange => !_effectiveReadOnly && !_isDraft;

  /// Planned styling applies to planner rows always (the fields ARE the
  /// targets), and to live rows only while the row is still untouched —
  /// blue means "planned value pending", so any actual value (weight,
  /// reps, or note) retires the tint. Variation is planned when it's
  /// "No Variation" or matches the plan's variation. Controllers are read
  /// because they track keystrokes before the commit reload lands. (Only
  /// evaluated inside build(), so the late controllers are initialized.)
  bool get _isPlannedRow {
    if (widget.mode == SetRowMode.planned) return true;
    if (widget.mode != SetRowMode.live || widget.plannedTarget == null) {
      return false;
    }
    final weightEmpty = _weightCtrl.text.trim().isEmpty;
    final repsEmpty = _repsCtrl.text.trim().isEmpty;
    // Variation counts as still-planned when it's "No Variation" (null) or
    // when it matches the plan's variation — the plan is satisfied, not
    // deviated from. A different pick retires the tint like any other
    // entered value.
    final variationPlanned = _isDraft
        ? _draftVariationId == null
        : (widget.initialVariationId == null ||
            widget.initialVariationId == widget.plannedTarget?.variationId);
    final notesEmpty = _isDraft
        ? (_draftNotes?.trim().isEmpty ?? true)
        : !widget.hasNotes;
    return weightEmpty && repsEmpty && variationPlanned && notesEmpty;
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
        if (!_weightFocus.hasFocus) _commit();
      });
      _repsFocus.addListener(() {
        if (!_repsFocus.hasFocus) _commit();
      });
    }
    widget.onRegisterCommit?.call(_commit);
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
    }
    if (!_repsFocus.hasFocus &&
        widget.initialRepsText != oldWidget.initialRepsText) {
      _repsCtrl.text = widget.initialRepsText;
    }
    if (_isDraft &&
        widget.plannedTarget?.variationId !=
            oldWidget.plannedTarget?.variationId) {
      _draftVariationId = widget.plannedTarget?.variationId;
    }
  }

  @override
  void dispose() {
    widget.onUnregisterCommit?.call(_commit);
    _weightCtrl.dispose();
    _repsCtrl.dispose();
    _weightFocus.dispose();
    _repsFocus.dispose();
    super.dispose();
  }

  Future<void> _commit() async {
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
          final weight = weightText.isEmpty ? null : double.tryParse(weightText);
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
          notes: _draftNotes?.trim().isEmpty == true ? null : _draftNotes?.trim(),
        ),
      );
      return;
    }

    // Real set: skip when the text is unchanged from the seeds (a cosmetic
    // re-format like "100" → "100.0" still commits — the VM write is a
    // harmless no-op).
    if (weightText == widget.initialWeightText &&
        repsText == widget.initialRepsText) {
      return;
    }
    await widget.onCommit(
      false,
      SetRowFieldValues(
        weight: weightText.isEmpty ? null : weightText,
        reps: repsText.isEmpty ? null : repsText,
      ),
    );
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
          style: TextStyle(color: AppColors.muted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Cancel', style: TextStyle(color: AppColors.muted)),
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

  void _duplicate() {
    if (_isDraft) return; // nothing persisted yet to copy
    // Live-only guard: an empty placeholder set can't be duplicated.
    if (widget.mode == SetRowMode.live && widget.initialRepsText.isEmpty) {
      return;
    }
    widget.onDuplicate();
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
                    decoration: lambdaBox(ContainerTone.ghost, radius: AppRadius.md),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
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
                            color: AppColors.muted,
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
            child: Text('Cancel', style: TextStyle(color: AppColors.muted)),
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
    final variationId = _isDraft ? _draftVariationId : widget.initialVariationId;

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

    // Live rows ghost the planned variation the way the kg/reps cells ghost
    // their targets — the planned name in planned color until the row has
    // an actual variation of its own.
    final ghostVariationName = !_isDraft &&
            widget.mode == SetRowMode.live &&
            variationId == null &&
            widget.plannedTarget?.variationName != null
        ? widget.plannedTarget!.variationName
        : null;

    // Planned targets are raw text — ranges ("8-15", "60-70") show as-is.
    final plannedWeight = widget.plannedTarget?.targetWeight;
    final plannedReps = widget.plannedTarget?.targetReps;

    // The container's edge styling — PR rows get the accent treatment, and
    // planned rows the planned tint.
    final borderColor = widget.isPr
        ? AppColors.accent
        : _isPlannedRow
        ? AppColors.planned.withValues(alpha: 0.35)
        : AppColors.border;
    final borderWidth = widget.isPr ? 1.2 : 0.5;

    Widget row = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
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
          SizedBox(
            width: 26,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.isPr)
                  Text(
                    'PR',
                    style: AppFonts.mono(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: AppColors.accent,
                    ),
                  )
                else
                  Text(
                    '${widget.displayIndex}',
                    style: AppFonts.mono(
                      fontSize: 13,
                      color: AppColors.muted,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: _cell(
              // Stable per-row cell keys so driver/tooling can target an
              // exact row's field (mode prefix keeps them unique across the
              // live/planned/history surfaces).
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
              onTap: _gated ? () => _requestGateEdit(focus: _repsFocus) : null,
              onChanged: _commitOnChange ? (_) => _commit() : null,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: _cell(
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
              onTap: _gated ? () => _requestGateEdit(focus: _weightFocus) : null,
              onChanged: _commitOnChange ? (_) => _commit() : null,
            ),
          ),
          const SizedBox(width: 6),
          // Tooltip so long variation names stay visible even though the
          // cell truncates them. Twice the reps/kg width — number cells
          // only need ~4 digits, variation names need the room.
          Expanded(
            flex: 2,
            child: _effectiveReadOnly
                ? GestureDetector(
                    // Gated rows gate on tap — the variation field is a
                    // field like any other in the history viewer.
                    onTap: _gated ? () => _requestGateEdit() : null,
                    child: Tooltip(
                      message: variationId != null
                          ? (widget.initialVariationName ?? '')
                          : '',
                      child: Text(
                        variationId != null
                            ? (widget.initialVariationName ?? '')
                            : '—',
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppFonts.ui(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.muted,
                        ),
                      ),
                    ),
                  )
                : Tooltip(
                    message: variationLabel,
                    child: Container(
                      height: 38,
                      alignment: Alignment.center,
                      // Neutral chrome — planned-ness lives on the row
                      // container, never inside the fields.
                      decoration: BoxDecoration(
                        color: AppColors.bg,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: AppColors.border, width: 0.5),
                      ),
                      child: DropdownSelect<String?>(
                        options: widget.variationOptions,
                        value: variationId,
                        placeholder: ghostVariationName ?? 'No Variation',
                        placeholderColor: ghostVariationName != null
                            ? AppColors.planned
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
                color: AppColors.primary,
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
            label: 'Note',
            color: AppColors.primary,
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
              label: 'Duplicate',
              color: AppColors.accent,
              onTap: _duplicate,
            ),
          SwipeAction(
            icon: Icons.sticky_note_2_outlined,
            label: 'Note',
            color: AppColors.primary,
            onTap: _openNotes,
          ),
          SwipeAction(
            icon: Icons.delete_outline,
            label: 'Delete',
            color: AppColors.danger,
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
            label: 'Note',
            color: AppColors.primary,
            onTap: _openNotes,
          ),
        ],
        child: row,
      );
    }

    return Padding(padding: const EdgeInsets.only(bottom: 6), child: row);
  }

  /// The reps/kg cell. Ghost = live's planned-target overlay — the planned
  /// hint TEXT in planned color; the cell chrome itself stays neutral
  /// (planned-ness lives on the row container, never inside the fields).
  /// History view mode is a transparent read-only TextField.
  Widget _cell({
    Key? key,
    required TextEditingController controller,
    required FocusNode focusNode,
    required bool ghost,
    required String hint,
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
            ? const TextInputType.numberWithOptions(
                decimal: true,
                signed: true,
              )
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
          color: AppColors.primary,
        ),
        decoration: InputDecoration(
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 8),
          hintText: hint,
          hintStyle: AppFonts.mono(
            fontSize: 14,
            color: ghost
                ? AppColors.planned
                : AppColors.muted.withValues(alpha: 0.6),
          ),
          filled: true,
          fillColor: _effectiveReadOnly
              ? Colors.transparent
              : AppColors.bg,
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: BorderSide(
              color: _effectiveReadOnly
                  ? Colors.transparent
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
