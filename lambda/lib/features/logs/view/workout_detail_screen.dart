import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../../core/styles/app_colors.dart';
import '../../../../core/styles/app_spacing.dart';
import '../../../../core/styles/app_text_styles.dart';
import '../../../../core/utils/workout_format.dart';
import '../../../../data/models/workout_set.dart';
import '../../../../shared/widgets/dropdown_select.dart';
import '../../../../shared/widgets/glass_button.dart';
import '../../../../shared/widgets/lambda_input.dart';
import '../../../../shared/widgets/page_header.dart';
import '../../../../shared/widgets/set_form_sheet.dart';
import '../../../../shared/widgets/slide_up_modal.dart';
import '../../../../shared/widgets/workout_sets_list.dart';
import '../viewmodel/workout_detail_viewmodel.dart';

class WorkoutDetailScreen extends StatefulWidget {
  const WorkoutDetailScreen({super.key, required this.workoutId});
  final String workoutId;

  @override
  State<WorkoutDetailScreen> createState() =>
      _WorkoutDetailScreenState();
}

class _WorkoutDetailScreenState extends State<WorkoutDetailScreen> {
  late final WorkoutDetailViewModel _vm;

  final _preNotesController  = TextEditingController();
  final _postNotesController = TextEditingController();
  final _logWeightController = TextEditingController();
  final _logRepsController   = TextEditingController();
  final _logNotesController  = TextEditingController();
  final _editWeightController = TextEditingController();
  final _editRepsController   = TextEditingController();
  final _editNotesController  = TextEditingController();

  @override
  void initState() {
    super.initState();
    _vm = WorkoutDetailViewModel();
    _vm.load(widget.workoutId);
  }

  @override
  void dispose() {
    _vm.dispose();
    _preNotesController.dispose();
    _postNotesController.dispose();
    _logWeightController.dispose();
    _logRepsController.dispose();
    _logNotesController.dispose();
    _editWeightController.dispose();
    _editRepsController.dispose();
    _editNotesController.dispose();
    super.dispose();
  }

  static String _formatDate(DateTime dt) =>
      DateFormat('EEEE, d MMMM yyyy', 'en_GB').format(dt);

  void _openLogSet() {
    _logWeightController.clear();
    _logRepsController.clear();
    _logNotesController.clear();
    _vm.openLogSet();
    showLambdaModal(
      context,
      fitContent: true,
      keyboardAware: true,
      child: ValueListenableBuilder<WorkoutDetailState>(
        valueListenable: _vm.state,
        builder: (ctx, state, _) {
          final detail = state.selectedExDetail;
          return SetFormSheet(
            title: 'Log Set',
            exerciseOptions: state.exerciseDetailMap.values
                .map((d) => DropdownOption(
                    label: toProperCase(d.name), value: d.exerciseId))
                .toList(),
            selectedExerciseId: state.selectedExId,
            onExerciseChanged: _vm.selectExercise,
            variationOptions: [
              const DropdownOption<String?>(label: 'None', value: null),
              ...(detail?.assignedVariations ?? []).map((v) => DropdownOption(
                  label: toProperCase(v.name), value: v.variationId)),
            ],
            selectedVariationId: state.selectedVarId,
            onVariationChanged: _vm.selectVariation,
            volumeType: detail?.volumeType,
            weightCtrl: _logWeightController,
            repsCtrl: _logRepsController,
            notesCtrl: _logNotesController,
            onWeightChanged: _vm.setLogWeight,
            onRepsChanged: _vm.setLogReps,
            onNotesChanged: _vm.setLogNotes,
            submitLabel: 'Log Set',
            submitLoading: state.logLoading,
            onSubmit: () => _vm.submitLogSet(widget.workoutId),
          );
        },
      ),
    ).then((_) => _vm.closeLogSet());
  }

  void _openEditSet(WorkoutSet s) {
    _editWeightController.text =
        _vm.state.value.editWeight;
    _editRepsController.text =
        _vm.state.value.editRepsOrDuration;
    _editNotesController.text =
        _vm.state.value.editNotes;
    showLambdaModal(
      context,
      fitContent: true,
      keyboardAware: true,
      child: ValueListenableBuilder<WorkoutDetailState>(
        valueListenable: _vm.state,
        builder: (ctx, state, _) {
          final detail = state.editExDetail;
          return SetFormSheet(
            title: 'Edit Set',
            exerciseOptions: state.exerciseDetailMap.values
                .map((d) => DropdownOption(
                    label: toProperCase(d.name), value: d.exerciseId))
                .toList(),
            selectedExerciseId: state.editExId,
            onExerciseChanged: _vm.setEditExId,
            variationOptions: [
              const DropdownOption<String?>(label: 'None', value: null),
              ...(detail?.assignedVariations ?? []).map((v) => DropdownOption(
                  label: toProperCase(v.name), value: v.variationId)),
            ],
            selectedVariationId: state.editVarId,
            onVariationChanged: _vm.setEditVarId,
            volumeType: detail?.volumeType,
            weightCtrl: _editWeightController,
            repsCtrl: _editRepsController,
            notesCtrl: _editNotesController,
            onWeightChanged: _vm.setEditWeight,
            onRepsChanged: _vm.setEditReps,
            onNotesChanged: _vm.setEditNotes,
            submitLabel: 'Save',
            submitLoading: state.editLoading,
            onSubmit: () => _vm.submitEditSet(widget.workoutId),
            onDelete: () => _confirmDeleteSet(s.setId),
          );
        },
      ),
    ).then((_) => _vm.closeEditSet());
  }

  void _confirmDeleteSet(String setId) {
    Navigator.of(context, rootNavigator: true).pop();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Delete Set',
            style: TextStyle(color: AppColors.primary)),
        content: Text('Remove this set?',
            style: TextStyle(color: AppColors.muted)),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text('Cancel',
                  style: TextStyle(color: AppColors.muted))),
          TextButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                _vm.deleteSet(setId, widget.workoutId);
              },
              child: Text('Delete',
                  style: TextStyle(
                      color: AppColors.danger,
                      fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }

  void _openNotesModal(String target) {
    final s = _vm.state.value;
    _preNotesController.text  = s.preNotesDraft;
    _postNotesController.text = s.postNotesDraft;
    showLambdaModal(
      context,
      fitContent: true,
      keyboardAware: true,
      child: _NotesModal(
        target: target,
        preCtrl: _preNotesController,
        postCtrl: _postNotesController,
        onPre: _vm.setPreNotesDraft,
        onPost: _vm.setPostNotesDraft,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: ValueListenableBuilder<WorkoutDetailState>(
        valueListenable: _vm.state,
        builder: (context, state, _) {
          return Column(
            children: [
              PageHeader(
                title: state.isEditing ? 'Edit Session' : 'Past Session',
                left: state.isEditing
                    ? GlassButton(
                        label: 'Cancel',
                        color: AppColors.danger,
                        compact: true,
                        onPressed: _vm.cancelEditing)
                    : GestureDetector(
                        onTap: () => context.pop(),
                        child: Icon(Icons.arrow_back_ios_new,
                            size: 18, color: AppColors.accent)),
                right: state.isEditing
                    ? GlassButton(
                        label: 'Save',
                        compact: true,
                        loading: state.isSaving,
                        disabled: state.isSaving,
                        onPressed: () => _vm.saveNotes(widget.workoutId))
                    : GlassButton(
                        label: 'Edit',
                        compact: true,
                        onPressed: _vm.startEditing),
              ),
              if (state.isLoading)
                Expanded(
                  child: Center(
                    child: CircularProgressIndicator(
                        color: AppColors.accent),
                  ),
                )
              else
                Expanded(
                  child: state.isEditing
                      ? _EditingView(
                          state: state,
                          onToggleViewMode: _vm.toggleViewMode,
                          onEditSet: (s) {
                            _vm.openEditSet(s);
                            _openEditSet(s);
                          },
                          onReorderSets: (reordered, ids) => _vm.reorderSets(
                              widget.workoutId,
                              List<WorkoutSet>.from(reordered),
                              List<String>.from(ids)),
                          onLogSet: _openLogSet,
                          onNotesPress: _openNotesModal,
                        )
                      : _ReadonlyView(
                          state: state,
                          onToggleViewMode: _vm.toggleViewMode,
                          formatDate: _formatDate,
                        ),
                ),
            ],
          );
        },
      ),
    );
  }
}

// ── Readonly view ───────────────────────────────────────────────────────────────

class _ReadonlyView extends StatelessWidget {
  const _ReadonlyView({
    required this.state,
    required this.onToggleViewMode,
    required this.formatDate,
  });

  final WorkoutDetailState state;
  final VoidCallback onToggleViewMode;
  final String Function(DateTime) formatDate;

  @override
  Widget build(BuildContext context) {
    final workout = state.workout;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (workout != null)
            Text(
              formatDate(workout.createdDate),
              style: TextStyle(
                  fontSize: AppTextStyles.sm,
                  fontWeight: FontWeight.w700,
                  color: AppColors.muted),
            ),
          const SizedBox(height: AppSpacing.md),

          // Pre-workout notes
          Text('Pre-workout notes',
              style: TextStyle(
                  fontSize: AppTextStyles.xs, color: AppColors.muted)),
          const SizedBox(height: AppSpacing.xs),
          Text(
            workout?.preNotes?.isNotEmpty == true
                ? '"${workout!.preNotes}"'
                : 'No pre-workout notes',
            style: TextStyle(
                fontSize: AppTextStyles.sm,
                color: workout?.preNotes?.isNotEmpty == true
                    ? AppColors.primary
                    : AppColors.muted,
                fontStyle: workout?.preNotes?.isNotEmpty == true
                    ? FontStyle.italic
                    : FontStyle.normal),
          ),
          const SizedBox(height: AppSpacing.md),
          Divider(color: AppColors.border),
          const SizedBox(height: AppSpacing.md),

          WorkoutSetsList(
            sets: state.sets,
            exerciseDetailMap: state.exerciseDetailMap,
            setsLoading: state.isLoading,
            viewMode: state.viewMode,
            onToggleViewMode: onToggleViewMode,
            emptyHint: 'No sets recorded.',
          ),

          Divider(color: AppColors.border),
          const SizedBox(height: AppSpacing.md),

          // Post-workout notes
          Text('Post-workout notes',
              style: TextStyle(
                  fontSize: AppTextStyles.xs, color: AppColors.muted)),
          const SizedBox(height: AppSpacing.xs),
          Text(
            workout?.postNotes?.isNotEmpty == true
                ? '"${workout!.postNotes}"'
                : 'No post-workout notes',
            style: TextStyle(
                fontSize: AppTextStyles.sm,
                color: workout?.postNotes?.isNotEmpty == true
                    ? AppColors.primary
                    : AppColors.muted,
                fontStyle: workout?.postNotes?.isNotEmpty == true
                    ? FontStyle.italic
                    : FontStyle.normal),
          ),
          const SizedBox(height: AppSpacing.xxl),
        ],
      ),
    );
  }
}

// ── Editing view ────────────────────────────────────────────────────────────────

class _EditingView extends StatelessWidget {
  const _EditingView({
    required this.state,
    required this.onToggleViewMode,
    required this.onEditSet,
    required this.onReorderSets,
    required this.onLogSet,
    required this.onNotesPress,
  });

  final WorkoutDetailState state;
  final VoidCallback onToggleViewMode;
  final ValueChanged onEditSet;
  final void Function(List, List<String>) onReorderSets;
  final VoidCallback onLogSet;
  final ValueChanged<String> onNotesPress;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: WorkoutSetsList(
              sets: state.sets,
              exerciseDetailMap: state.exerciseDetailMap,
              viewMode: state.viewMode,
              onToggleViewMode: onToggleViewMode,
              interactive: true,
              onEditSet: onEditSet,
              onReorderSets: onReorderSets,
              emptyHint: 'Log your first set below.',
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg, vertical: AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.surface,
            border: Border(
                top: BorderSide(color: AppColors.border, width: 0.5)),
          ),
          child: Row(
            children: [
              Expanded(
                child: GlassButton(
                  label: 'Log Set',
                  icon: Icons.add,
                  onPressed: onLogSet,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              GlassButton(
                label: 'Notes',
                icon: Icons.notes_outlined,
                onPressed: () => onNotesPress('pre'),
                compact: true,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Notes modal ──────────────────────────────────────────────────────────────────

class _NotesModal extends StatelessWidget {
  const _NotesModal({
    required this.target,
    required this.preCtrl,
    required this.postCtrl,
    required this.onPre,
    required this.onPost,
  });

  final String target;
  final TextEditingController preCtrl;
  final TextEditingController postCtrl;
  final ValueChanged<String> onPre;
  final ValueChanged<String> onPost;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              target == 'pre' ? 'Pre-Workout Notes' : 'Post-Workout Notes',
              style: TextStyle(
                  fontSize: AppTextStyles.lg,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary),
            ),
            const SizedBox(height: AppSpacing.md),
            LambdaInput(
              controller: target == 'pre' ? preCtrl : postCtrl,
              placeholder: 'Notes…',
              onChanged:
                  target == 'pre' ? onPre : onPost,
            ),
            const SizedBox(height: AppSpacing.md),
            GlassButton(
              label: 'Done',
              onPressed: () =>
                  Navigator.of(context, rootNavigator: true).pop(),
            ),
          ],
        ),
      ),
    );
  }
}

