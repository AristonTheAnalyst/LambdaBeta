import 'package:flutter/material.dart';
import '../../../core/styles/app_colors.dart';
import '../../../core/styles/app_fonts.dart';
import '../../../core/styles/app_radius.dart';
import '../../../core/utils/workout_format.dart';
import '../../../data/models/exercise_detail.dart';
import '../../../data/models/planned_set.dart';
import '../../../data/models/workout_set.dart';
import '../../../shared/widgets/dropdown_select.dart';
import '../model/session_local_state.dart' as local;
import '../viewmodel/session_viewmodel.dart';
import 'notes_modal.dart';

/// One row of the exercise card's set grid — either an already-logged
/// [WorkoutSet] (editable in place) or an unsaved draft row (promoted to a
/// real set the moment reps are entered and the field loses focus).
class SessionSetRow extends StatefulWidget {
  const SessionSetRow({
    super.key,
    required this.vm,
    required this.exerciseId,
    required this.displayIndex,
    required this.detail,
    this.set,
    this.draftId,
    this.plannedTarget,
  }) : assert(set != null || draftId != null);

  final SessionViewModel vm;
  final String exerciseId;
  final int displayIndex;
  final ExerciseDetail? detail;
  final WorkoutSet? set;
  final int? draftId;
  final PlannedSet? plannedTarget;

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

  bool get _isDraft => widget.set == null;

  @override
  void initState() {
    super.initState();
    final set = widget.set;
    _weightCtrl = TextEditingController(text: set?.weight != null ? _fmtNum(set!.weight!) : '');
    _repsCtrl = TextEditingController(
        text: set != null && set.reps.isNotEmpty ? _fmtNum(set.reps.first) : '');
    _weightFocus.addListener(() {
      if (!_weightFocus.hasFocus) _commit();
    });
    _repsFocus.addListener(() {
      if (!_repsFocus.hasFocus) _commit();
    });
  }

  @override
  void dispose() {
    _weightCtrl.dispose();
    _repsCtrl.dispose();
    _weightFocus.dispose();
    _repsFocus.dispose();
    super.dispose();
  }

  static String _fmtNum(num n) => n == n.roundToDouble() ? n.toInt().toString() : n.toString();

  Future<void> _commit() async {
    final weightText = _weightCtrl.text.trim();
    final repsText = _repsCtrl.text.trim();
    final weight = weightText.isEmpty ? null : double.tryParse(weightText);
    final reps = repsText.isEmpty ? null : num.tryParse(repsText);

    if (_isDraft) {
      if (reps == null) return; // stays a draft until reps is entered
      await widget.vm.commitDraftSet(
        widget.exerciseId,
        widget.draftId!,
        variationId: _draftVariationId,
        weight: weight,
        reps: [reps],
        duration: const [],
        notes: _draftNotes?.trim().isEmpty == true ? null : _draftNotes?.trim(),
      );
      return;
    }

    final set = widget.set!;
    final currentWeight = set.weight;
    final currentReps = set.reps.isNotEmpty ? set.reps.first : null;
    if (weight == currentWeight && reps == currentReps) return;
    await widget.vm.updateSetField(
      set,
      weight: weight,
      clearWeight: weight == null,
      reps: reps != null ? [reps] : null,
    );
  }

  void _openNotes() {
    showNotesModal(
      context,
      setIndex: widget.displayIndex,
      initialValue: _isDraft ? (_draftNotes ?? '') : (widget.set!.notes ?? ''),
      plannedNote: widget.plannedTarget?.targetNotes,
      onSave: (value) {
        if (_isDraft) {
          setState(() => _draftNotes = value);
        } else {
          widget.vm.updateSetField(widget.set!,
              notes: value.trim().isEmpty ? null : value.trim(),
              clearNotes: value.trim().isEmpty);
        }
      },
    );
  }

  void _delete() {
    if (_isDraft) {
      widget.vm.removeDraftSet(widget.exerciseId, widget.draftId!);
    } else {
      widget.vm.deleteSetById(widget.set!.setId);
    }
  }

  void _duplicate() {
    if (_isDraft) return; // nothing persisted yet to copy
    widget.vm.duplicateSet(widget.set!);
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
    final exact = widget.vm.allVariations
        .where((v) => v.name.trim().toLowerCase() == trimmed.toLowerCase())
        .firstOrNull;

    String? useExistingId = exact?.variationId;
    if (exact == null) {
      final similar = widget.vm.findSimilarVariations(trimmed);
      if (similar.isNotEmpty) {
        final choice = await _showDidYouMeanDialog(trimmed, similar);
        if (choice == null || !mounted) return; // cancelled
        if (!choice.createNew) useExistingId = choice.existingId;
      }
    }

    final id = await widget.vm.submitNewVariation(trimmed, exerciseId: widget.exerciseId, useExistingId: useExistingId);
    if (id == null || !mounted) return;
    if (_isDraft) {
      setState(() => _draftVariationId = id);
    } else {
      widget.vm.updateSetField(widget.set!, variationId: id);
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
        title: Text('Did you mean?', style: TextStyle(color: AppColors.primary)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final s in similar)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: GestureDetector(
                  onTap: () => Navigator.of(ctx).pop((createNew: false, existingId: s.id)),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceHigh,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(s.name,
                              style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w600)),
                        ),
                        Text('${s.exerciseCount} exercise${s.exerciseCount == 1 ? '' : 's'}',
                            style: TextStyle(color: AppColors.muted, fontSize: 12)),
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
              child: Text('Cancel', style: TextStyle(color: AppColors.muted))),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop((createNew: true, existingId: null)),
            child: Text('Create "$typedName" anyway',
                style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Future<String?> _promptForVariationName() {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('New Variation', style: TextStyle(color: AppColors.primary)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          style: TextStyle(color: AppColors.primary),
          decoration: InputDecoration(hintText: 'Variation name', hintStyle: TextStyle(color: AppColors.muted)),
          onSubmitted: (v) => Navigator.of(ctx).pop(v),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text('Cancel', style: TextStyle(color: AppColors.muted))),
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(ctrl.text),
              child: Text('Create', style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final vm = widget.vm;
    final set = widget.set;
    final bestEver = vm.prevBestFor(widget.exerciseId);
    final pr = set != null && local.isPr(set, bestEver);
    final hasNotes = _isDraft ? (_draftNotes?.trim().isNotEmpty ?? false) : (set!.notes?.isNotEmpty ?? false);
    final plannedWeight = widget.plannedTarget?.targetWeight;
    final plannedReps = widget.plannedTarget?.targetReps.isNotEmpty == true
        ? widget.plannedTarget!.targetReps.first
        : null;

    final variationId = _isDraft ? _draftVariationId : set!.variationId;
    final variationOptions = [
      const DropdownOption<String?>(label: '—', value: null),
      ...(widget.detail?.assignedVariations ?? [])
          .map((v) => DropdownOption<String?>(label: toProperCase(v.name), value: v.variationId)),
    ];

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: _SwipeActions(
        actions: [
          if (!_isDraft)
            _SwipeAction(
              icon: Icons.copy_rounded,
              label: 'Duplicate',
              color: AppColors.accent,
              onTap: _duplicate,
            ),
          _SwipeAction(
            icon: Icons.delete_outline,
            label: 'Delete',
            color: AppColors.danger,
            onTap: _delete,
          ),
        ],
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: pr
                ? AppColors.accentBg
                : widget.plannedTarget != null
                    ? AppColors.successBg
                    : AppColors.surfaceHigh,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(
              color: pr
                  ? AppColors.accent
                  : widget.plannedTarget != null
                      ? AppColors.success.withValues(alpha: 0.35)
                      : AppColors.border,
              width: pr ? 1.2 : 0.5,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: 26,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (pr)
                      Text('PR',
                          style: AppFonts.mono(
                              fontSize: 8, fontWeight: FontWeight.w800, color: AppColors.accent))
                    else
                      Text('${widget.displayIndex}',
                          style: AppFonts.mono(fontSize: 11, color: AppColors.muted)),
                    if (hasNotes)
                      Container(
                        margin: const EdgeInsets.only(top: 2),
                        width: 5,
                        height: 5,
                        decoration: BoxDecoration(color: AppColors.accent, shape: BoxShape.circle),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _cell(
                  controller: _weightCtrl,
                  focusNode: _weightFocus,
                  hint: plannedWeight != null ? _fmtNum(plannedWeight) : '—',
                  ghost: plannedWeight != null,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _cell(
                  controller: _repsCtrl,
                  focusNode: _repsFocus,
                  hint: plannedReps != null ? _fmtNum(plannedReps) : '—',
                  ghost: plannedReps != null,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Container(
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.bg,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppColors.border, width: 0.5),
                  ),
                  child: DropdownSelect<String?>(
                    options: variationOptions,
                    value: variationId,
                    compact: true,
                    createNewLabel: 'New Variation',
                    onCreateNew: _handleCreateVariation,
                    onChange: (id) {
                      if (_isDraft) {
                        setState(() => _draftVariationId = id);
                      } else {
                        widget.vm.updateSetField(set!, variationId: id, clearVariation: id == null);
                      }
                    },
                  ),
                ),
              ),
              const SizedBox(width: 6),
              _iconButton(
                icon: Icons.sticky_note_2_outlined,
                active: hasNotes,
                onTap: _openNotes,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _cell({
    required TextEditingController controller,
    required FocusNode focusNode,
    required String hint,
    required bool ghost,
  }) {
    return SizedBox(
      height: 34,
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        textAlign: TextAlign.center,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        style: AppFonts.mono(fontSize: 15, fontWeight: FontWeight.w500, color: AppColors.primary),
        decoration: InputDecoration(
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 8),
          hintText: hint,
          hintStyle: AppFonts.mono(
              fontSize: 14, color: ghost ? AppColors.success : AppColors.muted.withValues(alpha: 0.6)),
          filled: true,
          fillColor: ghost ? AppColors.successBg : AppColors.bg,
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: BorderSide(
                color: ghost ? AppColors.success.withValues(alpha: 0.5) : AppColors.border, width: 0.5),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: BorderSide(color: AppColors.accent, width: 1.5),
          ),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
        ),
      ),
    );
  }

  Widget _iconButton({
    required IconData icon,
    required bool active,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? AppColors.accentBg : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: active ? AppColors.accent.withValues(alpha: 0.4) : AppColors.border),
        ),
        child: Icon(icon, size: 15, color: active ? AppColors.accent : AppColors.muted),
      ),
    );
  }
}

class _SwipeAction {
  const _SwipeAction({required this.icon, required this.label, required this.color, required this.onTap});

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
}

const _swipeButtonWidth = 64.0;

/// Swipe-left-to-reveal action drawer (delete, duplicate, …) tucked behind
/// [child] — snaps fully open or closed on release rather than resting
/// part-way.
class _SwipeActions extends StatefulWidget {
  const _SwipeActions({required this.child, required this.actions});

  final Widget child;
  final List<_SwipeAction> actions;

  @override
  State<_SwipeActions> createState() => _SwipeActionsState();
}

class _SwipeActionsState extends State<_SwipeActions> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 200), value: 0);

  double get _drawerWidth => widget.actions.length * _swipeButtonWidth;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _close() => _ctrl.animateTo(0, curve: Curves.easeOut);

  void _handleDragUpdate(DragUpdateDetails details) {
    if (widget.actions.isEmpty) return;
    _ctrl.value = (_ctrl.value - details.delta.dx / _drawerWidth).clamp(0.0, 1.0);
  }

  void _handleDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    if (velocity < -300) {
      _ctrl.animateTo(1, curve: Curves.easeOut);
    } else if (velocity > 300) {
      _close();
    } else if (_ctrl.value > 0.5) {
      _ctrl.animateTo(1, curve: Curves.easeOut);
    } else {
      _close();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.actions.isEmpty) return widget.child;
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              Positioned.fill(
                child: Row(
                  children: [
                    const Spacer(),
                    ...widget.actions.map((a) => SizedBox(
                          width: _swipeButtonWidth,
                          child: GestureDetector(
                            onTap: () {
                              _close();
                              a.onTap();
                            },
                            child: Container(
                              color: a.color,
                              alignment: Alignment.center,
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(a.icon, size: 16, color: Colors.white),
                                  const SizedBox(height: 2),
                                  Text(a.label,
                                      style: AppFonts.ui(
                                          fontSize: 9, fontWeight: FontWeight.w700, color: Colors.white)),
                                ],
                              ),
                            ),
                          ),
                        )),
                  ],
                ),
              ),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onHorizontalDragUpdate: _handleDragUpdate,
                onHorizontalDragEnd: _handleDragEnd,
                onTap: _ctrl.value > 0 ? _close : null,
                child: Transform.translate(
                  offset: Offset(-_ctrl.value * _drawerWidth, 0),
                  child: widget.child,
                ),
              ),
              // Deliberate swipe-hint accent (top edge only) — replaces the
              // stray bottom-right sliver that used to leak through the
              // row's rounded corner from the drawer behind it.
              Positioned(
                top: 0,
                right: 0,
                child: IgnorePointer(
                  child: Container(
                    width: 16,
                    height: 3,
                    decoration: BoxDecoration(
                      color: AppColors.accent,
                      borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(3)),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
