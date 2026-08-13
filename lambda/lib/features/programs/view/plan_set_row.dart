import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/styles/app_colors.dart';
import '../../../core/styles/app_fonts.dart';
import '../../../core/styles/app_radius.dart';
import '../../../core/utils/session_format.dart';
import '../../../data/models/custom_variation.dart';
import '../../../data/models/exercise_detail.dart';
import '../../../data/models/planned_session_set.dart';
import '../../../shared/utils/pop_dialog.dart';
import '../../../shared/widgets/dropdown_select.dart';
import '../../../shared/widgets/swipe_actions.dart';
import '../../../shared/widgets/variation_name_dialog.dart';
import '../../session/view/notes_modal.dart';
import '../viewmodel/program_detail_viewmodel.dart';

/// One row of the plan-workout screen's target-set grid — either an
/// already-saved [PlannedSessionSet] (editable in place) or an unsaved draft row
/// (promoted to a real planned set the moment a target is entered and the
/// field loses focus). Mirrors `lib/features/session/view/session_set_row.dart`'s
/// `SessionSetRow` exactly (same cell shapes, swipe drawer, "did you mean?"
/// variation flow) but bound to a target set instead of a logged one — no
/// PR badge, no ghost-value overlay, since the field itself *is* the plan.
class PlanSetRow extends StatefulWidget {
  const PlanSetRow({
    super.key,
    required this.viewModel,
    required this.exerciseId,
    required this.exerciseSequenceOrder,
    required this.displayIndex,
    required this.detail,
    this.set,
    this.draftId,
  }) : assert(set != null || draftId != null);

  final ProgramDetailViewModel viewModel;
  final String exerciseId;
  final int exerciseSequenceOrder;
  final int displayIndex;
  final ExerciseDetail? detail;
  final PlannedSessionSet? set;
  final int? draftId;

  @override
  State<PlanSetRow> createState() => _PlanSetRowState();
}

class _PlanSetRowState extends State<PlanSetRow> {
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
    _weightCtrl =
        TextEditingController(text: set?.targetWeight != null ? _fmtNum(set!.targetWeight!) : '');
    _repsCtrl = TextEditingController(
        text: set != null && set.targetReps.isNotEmpty ? _fmtNum(set.targetReps.first) : '');
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
      // Commit even with no targets — an empty planned set is valid (it shows
      // as a blank row to fill during the session).
      await widget.viewModel.quickCreatePlannedSessionSet(
        exerciseId: widget.exerciseId,
        exerciseSequenceOrder: widget.exerciseSequenceOrder,
        draftId: widget.draftId!,
        variationId: _draftVariationId,
        weight: weight,
        reps: reps != null ? [reps] : const [],
        notes: _draftNotes?.trim().isEmpty == true ? null : _draftNotes?.trim(),
      );
      return;
    }

    final set = widget.set!;
    final currentWeight = set.targetWeight;
    final currentReps = set.targetReps.isNotEmpty ? set.targetReps.first : null;
    if (weight == currentWeight && reps == currentReps) return;
    await widget.viewModel.quickUpdatePlannedSessionSet(
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
      initialValue: _isDraft ? (_draftNotes ?? '') : (widget.set!.targetNotes ?? ''),
      onSave: (value) {
        if (_isDraft) {
          setState(() => _draftNotes = value);
        } else {
          widget.viewModel.quickUpdatePlannedSessionSet(widget.set!,
              notes: value.trim().isEmpty ? null : value.trim(),
              clearNotes: value.trim().isEmpty);
        }
      },
    );
  }

  void _delete() {
    if (_isDraft) {
      widget.viewModel.removeDraftPlannedSessionSet(widget.exerciseSequenceOrder, widget.draftId!);
    } else {
      widget.viewModel.deletePlannedSessionSet(widget.set!.setId);
    }
  }

  void _duplicate() {
    if (_isDraft) return; // nothing persisted yet to copy
    widget.viewModel.duplicatePlannedSessionSet(widget.set!);
  }

  Future<void> _handleCreateVariation(String query) async {
    final typed = query.trim();
    final name = typed.isNotEmpty ? typed : await _promptForVariationName();
    if (name == null || name.trim().isEmpty || !mounted) return;
    final trimmed = name.trim();

    final exact = widget.viewModel.state.value.allVariations
        .where((v) => v.name.trim().toLowerCase() == trimmed.toLowerCase())
        .firstOrNull;

    String? useExistingId = exact?.variationId;
    if (exact == null) {
      final similar = widget.viewModel.findSimilarVariations(trimmed);
      if (similar.isNotEmpty) {
        final choice = await _showDidYouMeanDialog(trimmed, similar);
        if (choice == null || !mounted) return; // cancelled
        if (!choice.createNew) useExistingId = choice.existingId;
      }
    }

    final id = await widget.viewModel
        .submitNewVariation(trimmed, exerciseId: widget.exerciseId, useExistingId: useExistingId);
    if (id == null || !mounted) return;
    if (_isDraft) {
      setState(() => _draftVariationId = id);
    } else {
      widget.viewModel.quickUpdatePlannedSessionSet(widget.set!, variationId: id);
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
                  onTap: () => popDialog(ctx, (createNew: false, existingId: s.id)),
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
            onPressed: () => popDialog(ctx, (createNew: true, existingId: null)),
            child: Text('Create "$typedName" anyway',
                style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w600)),
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
    final set = widget.set;
    final hasNotes = _isDraft ? (_draftNotes?.trim().isNotEmpty ?? false) : (set!.targetNotes?.isNotEmpty ?? false);
    final variationId = _isDraft ? _draftVariationId : set!.variationId;
    final List<CustomVariation> assigned = [...(widget.detail?.assignedVariations ?? const <CustomVariation>[])]
      ..sort(CustomVariation.byRecency);
    final variationOptions = [
      const DropdownOption<String?>(label: '—', value: null),
      ...assigned
          .map((v) => DropdownOption<String?>(label: toProperCase(v.name), value: v.variationId)),
    ];

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: SwipeActions(
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
            icon: Icons.delete_outline,
            label: 'Delete',
            color: AppColors.danger,
            onTap: _delete,
          ),
        ],
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.plannedBg,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(
                color: AppColors.planned.withValues(alpha: 0.4), width: 0.5),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: 26,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('${widget.displayIndex}',
                        style: AppFonts.mono(fontSize: 11, color: AppColors.muted)),
                    if (hasNotes)
                      Container(
                        margin: const EdgeInsets.only(top: 2),
                        width: 5,
                        height: 5,
                        decoration: BoxDecoration(color: AppColors.planned, shape: BoxShape.circle),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Expanded(child: _cell(
                  controller: _weightCtrl,
                  focusNode: _weightFocus,
                  highlighted: _weightCtrl.text.trim().isNotEmpty)),
              const SizedBox(width: 6),
              Expanded(child: _cell(
                  controller: _repsCtrl,
                  focusNode: _repsFocus,
                  highlighted: _repsCtrl.text.trim().isNotEmpty)),
              const SizedBox(width: 6),
              Expanded(
                child: Container(
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: variationId != null
                        ? AppColors.plannedBg
                        : AppColors.bg,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                        color: variationId != null
                            ? AppColors.planned.withValues(alpha: 0.4)
                            : AppColors.border,
                        width: 0.5),
                  ),
                  child: DropdownSelect<String?>(
                    options: variationOptions,
                    value: variationId,
                    compact: true,
                    valueColor: AppColors.planned,
                    createNewLabel: 'New Variation',
                    onCreateNew: _handleCreateVariation,
                    onChange: (id) {
                      if (_isDraft) {
                        setState(() => _draftVariationId = id);
                      } else {
                        widget.viewModel.quickUpdatePlannedSessionSet(set!, variationId: id, clearVariation: id == null);
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
    required bool highlighted,
  }) {
    return SizedBox(
      height: 34,
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        textAlign: TextAlign.center,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*$'))],
        style: AppFonts.mono(fontSize: 15, fontWeight: FontWeight.w500, color: AppColors.primary),
        decoration: InputDecoration(
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 8),
          hintText: '—',
          hintStyle: AppFonts.mono(
              fontSize: 14,
              color: highlighted
                  ? AppColors.planned.withValues(alpha: 0.7)
                  : AppColors.muted.withValues(alpha: 0.6)),
          filled: true,
          fillColor: highlighted ? AppColors.plannedBg : AppColors.bg,
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: BorderSide(
                color: highlighted
                    ? AppColors.planned.withValues(alpha: 0.4)
                    : AppColors.border,
                width: 0.5),
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

  Widget _iconButton({required IconData icon, required bool active, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? AppColors.plannedBg : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
              color: active
                  ? AppColors.planned.withValues(alpha: 0.4)
                  : AppColors.border),
        ),
        child: Icon(icon,
            size: 15, color: active ? AppColors.planned : AppColors.muted),
      ),
    );
  }
}
