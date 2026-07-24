import 'package:flutter/material.dart';
import '../../../../core/styles/app_colors.dart';
import '../../../../core/styles/app_spacing.dart';
import '../../../../core/styles/app_text_styles.dart';
import '../../../../core/utils/workout_format.dart';
import '../../../../data/models/workout_set.dart';
import '../../../../shared/widgets/dropdown_select.dart';
import '../../../../shared/widgets/glass_button.dart';
import '../../../../shared/widgets/lambda_button.dart';
import '../../../../shared/widgets/lambda_input.dart';
import '../../../../shared/widgets/page_header.dart';
import '../../../../shared/widgets/segmented_control.dart';
import '../../../../shared/widgets/set_form_sheet.dart';
import '../../../../shared/widgets/slide_pages.dart';
import '../../../../shared/widgets/slide_up_modal.dart';
import '../../../../shared/widgets/workout_sets_list.dart';
import '../viewmodel/session_viewmodel.dart';

class SessionScreen extends StatefulWidget {
  const SessionScreen({super.key});

  @override
  State<SessionScreen> createState() => _SessionScreenState();
}

class _SessionScreenState extends State<SessionScreen> {
  late final SessionViewModel _vm;

  // Text controllers — reused across modal opens
  final _startNotesCtrl  = TextEditingController();
  final _endNotesCtrl    = TextEditingController();
  final _logWeightCtrl   = TextEditingController();
  final _logRepsCtrl     = TextEditingController();
  final _logNotesCtrl    = TextEditingController();
  final _editWeightCtrl  = TextEditingController();
  final _editRepsCtrl    = TextEditingController();
  final _editNotesCtrl   = TextEditingController();
  final _newExNameCtrl   = TextEditingController();
  final _newVarNameCtrl  = TextEditingController();

  static const _volumeOptions = [
    SegmentOption(label: 'Reps',     value: 'reps'),
    SegmentOption(label: 'Duration', value: 'duration'),
  ];

  @override
  void initState() {
    super.initState();
    _vm = SessionViewModel();
    _vm.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _vm.dispose();
    _startNotesCtrl.dispose();
    _endNotesCtrl.dispose();
    _logWeightCtrl.dispose();
    _logRepsCtrl.dispose();
    _logNotesCtrl.dispose();
    _editWeightCtrl.dispose();
    _editRepsCtrl.dispose();
    _editNotesCtrl.dispose();
    _newExNameCtrl.dispose();
    _newVarNameCtrl.dispose();
    super.dispose();
  }

  // ── Modals ─────────────────────────────────────────────────────────────────

  void _openEndWorkoutModal() {
    if (_vm.sets.isEmpty) {
      _showNoSetsDialog();
      return;
    }
    _endNotesCtrl.clear();
    _vm.endNotes = '';
    showLambdaModal(
      context,
      fitContent: true,
      keyboardAware: true,
      child: _EndWorkoutModal(vm: _vm, notesCtrl: _endNotesCtrl),
    );
  }

  void _showNoSetsDialog() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('No Sets Logged',
            style: TextStyle(color: AppColors.primary)),
        content: Text(
            "You haven't logged any sets yet. Log at least one set before ending, or cancel the workout instead.",
            style: TextStyle(color: AppColors.muted)),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text('Got It',
                  style: TextStyle(
                      color: AppColors.accent,
                      fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }

  void _openLogSetModal() {
    _logWeightCtrl.clear();
    _logRepsCtrl.clear();
    _logNotesCtrl.clear();
    showLambdaModal(
      context,
      fitContent: true,
      keyboardAware: true,
      child: ListenableBuilder(
        listenable: _vm,
        builder: (ctx, _) {
          final detail = _vm.selectedExDetail;
          return SetFormSheet(
            title: 'Log Set',
            exerciseOptions: _vm.exercises
                .map((d) => DropdownOption(
                    label: toProperCase(d.name), value: d.exerciseId))
                .toList(),
            selectedExerciseId: _vm.selectedExId,
            onExerciseChanged: _vm.selectExercise,
            variationOptions: [
              const DropdownOption<String?>(label: 'None', value: null),
              ...(detail?.assignedVariations ?? []).map((v) => DropdownOption(
                  label: toProperCase(v.name), value: v.variationId)),
            ],
            selectedVariationId: _vm.selectedVarId,
            onVariationChanged: _vm.selectVariation,
            volumeType: detail?.volumeType,
            weightCtrl: _logWeightCtrl,
            repsCtrl: _logRepsCtrl,
            notesCtrl: _logNotesCtrl,
            onWeightChanged: (v) => _vm.logWeight = v,
            onRepsChanged: (v) => _vm.logRepsOrDuration = v,
            onNotesChanged: (v) => _vm.logNotes = v,
            submitLabel: 'Log Set',
            submitLoading: _vm.logLoading,
            onSubmit: _vm.submitLogSet,
            onNewExercise: () {
              Navigator.of(context, rootNavigator: true).pop();
              // submitNewExercise() already selects the new exercise for the
              // log form, so just reopen it directly.
              _openNewExerciseModal(forLog: true, onDone: _openLogSetModal);
            },
            onNewVariation: () {
              Navigator.of(context, rootNavigator: true).pop();
              _openNewVariationModal(forLog: true, onDone: _openLogSetModal);
            },
          );
        },
      ),
    );
  }

  void _openEditSetModal(WorkoutSet s) {
    _vm.openEditSet(s);
    _editWeightCtrl.text = _vm.editWeight;
    _editRepsCtrl.text   = _vm.editRepsOrDuration;
    _editNotesCtrl.text  = _vm.editNotes;
    _showEditSetModal(s);
  }

  // Re-shown after creating a new exercise/variation mid-edit, without
  // resetting the edit form fields (which _openEditSetModal would do).
  void _showEditSetModal(WorkoutSet s) {
    showLambdaModal(
      context,
      fitContent: true,
      keyboardAware: true,
      child: ListenableBuilder(
        listenable: _vm,
        builder: (ctx, _) {
          final detail = _vm.editExDetail;
          return SetFormSheet(
            title: 'Edit Set',
            exerciseOptions: _vm.exercises
                .map((d) => DropdownOption(
                    label: toProperCase(d.name), value: d.exerciseId))
                .toList(),
            selectedExerciseId: _vm.editExId,
            onExerciseChanged: _vm.setEditExId,
            variationOptions: [
              const DropdownOption<String?>(label: 'None', value: null),
              ...(detail?.assignedVariations ?? []).map((v) => DropdownOption(
                  label: toProperCase(v.name), value: v.variationId)),
            ],
            selectedVariationId: _vm.editVarId,
            onVariationChanged: _vm.setEditVarId,
            volumeType: detail?.volumeType,
            weightCtrl: _editWeightCtrl,
            repsCtrl: _editRepsCtrl,
            notesCtrl: _editNotesCtrl,
            onWeightChanged: (v) => _vm.editWeight = v,
            onRepsChanged: (v) => _vm.editRepsOrDuration = v,
            onNotesChanged: (v) => _vm.editNotes = v,
            submitLabel: 'Save',
            submitLoading: _vm.editLoading,
            onSubmit: _vm.submitEditSet,
            onDelete: () {
              Navigator.of(context, rootNavigator: true).pop();
              _confirmDeleteSet(s.setId);
            },
            onNewExercise: () {
              Navigator.of(context, rootNavigator: true).pop();
              // submitNewExercise() already selects the new exercise for the
              // edit form, so just restore the edit state and reopen it.
              _openNewExerciseModal(
                forLog: false,
                onDone: () {
                  _restoreEditState(s);
                  _showEditSetModal(s);
                },
              );
            },
            onNewVariation: () {
              Navigator.of(context, rootNavigator: true).pop();
              _openNewVariationModal(
                forLog: false,
                onDone: () {
                  _restoreEditState(s);
                  _showEditSetModal(s);
                },
              );
            },
          );
        },
      ),
    ).then((_) => _vm.clearEditSet());
  }

  // Popping the Edit Set sheet above (to step into New Exercise/Variation
  // creation) fires the .then(clearEditSet) above immediately, since that
  // fires on ANY close of the sheet, not just a deliberate Cancel. editExId/
  // editVarId get reassigned correctly by submitNewExercise/submitNewVariation
  // regardless, but editingSet and the text fields need restoring by hand.
  void _restoreEditState(WorkoutSet s) {
    _vm.editingSet = s;
    _vm.editWeight = _editWeightCtrl.text;
    _vm.editRepsOrDuration = _editRepsCtrl.text;
    _vm.editNotes = _editNotesCtrl.text;
  }

  void _confirmDeleteSet(String setId) {
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
                _vm.deleteSet(setId);
              },
              child: Text('Delete',
                  style: TextStyle(
                      color: AppColors.danger,
                      fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }

  void _openNewExerciseModal({required bool forLog, required VoidCallback onDone}) {
    _vm.prepareNewExercise(forLog: forLog);
    _newExNameCtrl.clear();
    showLambdaModal(
      context,
      fitContent: true,
      keyboardAware: true,
      child: _NewExerciseModal(
          vm: _vm,
          nameCtrl: _newExNameCtrl,
          volumeOptions: _volumeOptions,
          onCreated: onDone),
    );
  }

  void _openNewVariationModal({required bool forLog, required VoidCallback onDone}) {
    _vm.prepareNewVariation(forLog: forLog);
    _newVarNameCtrl.clear();
    showLambdaModal(
      context,
      fitContent: true,
      keyboardAware: true,
      child: _NewVariationModal(
          vm: _vm, nameCtrl: _newVarNameCtrl, onCreated: onDone),
    );
  }

  void _confirmCancelWorkout() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Cancel Workout',
            style: TextStyle(color: AppColors.danger)),
        content: Text(
            'Discard this workout and all logged sets?',
            style: TextStyle(color: AppColors.muted)),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text('Keep Going',
                  style: TextStyle(color: AppColors.muted))),
          TextButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                _vm.cancelWorkout();
              },
              child: Text('Discard',
                  style: TextStyle(
                      color: AppColors.danger,
                      fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Column(
        children: [
          PageHeader(
            title: _vm.hasActiveWorkout
                ? 'Training Session'
                : 'Mental Prep and Planning',
            left: _vm.hasActiveWorkout
                ? GlassButton(
                    label: 'Cancel',
                    color: AppColors.danger,
                    compact: true,
                    onPressed: _confirmCancelWorkout)
                : null,
            right: _vm.hasActiveWorkout
                ? GlassButton(
                    label: 'End',
                    compact: true,
                    onPressed: _openEndWorkoutModal)
                : null,
          ),
          if (_vm.error != null)
            GestureDetector(
              onTap: _vm.clearError,
              child: Container(
                width: double.infinity,
                color: AppColors.dangerBg,
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
                child: Text(_vm.error!,
                    style: TextStyle(
                        color: AppColors.danger,
                        fontSize: AppTextStyles.sm)),
              ),
            ),
          Expanded(
            child: SlidePages(
              controller: _vm.slidePagesController,
              children: [
                _StartPage(
                  vm: _vm,
                  startNotesCtrl: _startNotesCtrl,
                ),
                _ActivePage(
                  vm: _vm,
                  onLogSet: _openLogSetModal,
                  onEditSet: _openEditSetModal,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Page 0: Start ──────────────────────────────────────────────────────────────

class _StartPage extends StatelessWidget {
  const _StartPage({required this.vm, required this.startNotesCtrl});

  final SessionViewModel vm;
  final TextEditingController startNotesCtrl;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              if (vm.exercises.isEmpty && !vm.catalogLoading)
                Container(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    children: [
                      Text('No exercises set up yet',
                          style: TextStyle(
                              fontSize: AppTextStyles.md,
                              fontWeight: FontWeight.w600,
                              color: AppColors.primary),
                          textAlign: TextAlign.center),
                      SizedBox(height: AppSpacing.sm),
                      Text(
                          'Go to Exercises → Library to create your first exercise before logging a workout.',
                          style: TextStyle(
                              fontSize: AppTextStyles.sm,
                              color: AppColors.muted),
                          textAlign: TextAlign.center),
                    ],
                  ),
                ),
              if (vm.exercises.isNotEmpty) ...[
                // Session feeling picker
                Text('How do you expect to perform?',
                    style: TextStyle(
                        fontSize: AppTextStyles.sm,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary)),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: List.generate(5, (i) {
                    final n = i + 1;
                    final selected = vm.sessionFeeling == n;
                    return GestureDetector(
                      onTap: () => vm.setSessionFeeling(n),
                      child: Container(
                        width: 52,
                        height: 52,
                        margin:
                            const EdgeInsets.only(right: AppSpacing.sm),
                        decoration: BoxDecoration(
                          color: selected
                              ? AppColors.accent
                              : AppColors.surface,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: selected
                                  ? AppColors.accent
                                  : AppColors.border),
                        ),
                        child: Center(
                          child: Text('$n',
                              style: TextStyle(
                                  fontSize: AppTextStyles.lg,
                                  fontWeight: FontWeight.w700,
                                  color: selected
                                      ? AppColors.accentText
                                      : AppColors.primary)),
                        ),
                      ),
                    );
                  }),
                ),
                const SizedBox(height: AppSpacing.lg),
                LambdaInput(
                  controller: startNotesCtrl,
                  label: 'Pre-workout notes (optional)',
                  placeholder: 'Sleep and eat well?\nHydrated?\nGoals today?',
                  onChanged: (v) => vm.startNotes = v,
                ),
              ],
            ],
          ),
        ),
        if (vm.exercises.isNotEmpty)
          Container(
            padding: EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg,
                AppSpacing.lg, bottomInset + AppSpacing.lg),
            decoration: BoxDecoration(
              border: Border(
                  top: BorderSide(color: AppColors.border, width: 0.5)),
            ),
            child: LambdaButton(
              label: 'Start Workout',
              onPressed: vm.startWorkout,
              loading: vm.startLoading,
              disabled: vm.startLoading,
            ),
          ),
      ],
    );
  }
}

// ── Page 1: Active workout ─────────────────────────────────────────────────────

class _ActivePage extends StatelessWidget {
  const _ActivePage({
    required this.vm,
    required this.onLogSet,
    required this.onEditSet,
  });

  final SessionViewModel vm;
  final VoidCallback onLogSet;
  final ValueChanged<WorkoutSet> onEditSet;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: WorkoutSetsList(
              sets: vm.sets,
              exerciseDetailMap: vm.exerciseDetailMap,
              setsLoading: vm.setsLoading,
              viewMode: vm.viewMode,
              onToggleViewMode: vm.toggleViewMode,
              interactive: true,
              onEditSet: onEditSet,
              onReorderSets: (reordered, ids) =>
                  vm.reorderSets(reordered, ids),
              emptyHint: 'Tap "Log Set" below to record your first set.',
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
          child: SizedBox(
            width: double.infinity,
            child: GlassButton(
              label: 'Log Set',
              icon: Icons.add,
              onPressed: onLogSet,
            ),
          ),
        ),
      ],
    );
  }
}

// ── End Workout Modal ──────────────────────────────────────────────────────────

class _EndWorkoutModal extends StatelessWidget {
  const _EndWorkoutModal({required this.vm, required this.notesCtrl});

  final SessionViewModel vm;
  final TextEditingController notesCtrl;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('End Workout',
                style: TextStyle(
                    fontSize: AppTextStyles.lg,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary)),
            const SizedBox(height: AppSpacing.md),
            LambdaInput(
              controller: notesCtrl,
              label: 'Post-workout notes (optional)',
              placeholder: 'Notes…',
              onChanged: (v) => vm.endNotes = v,
            ),
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                Expanded(
                  child: GlassButton(
                    label: 'Cancel',
                    color: AppColors.danger,
                    compact: true,
                    onPressed: () =>
                        Navigator.of(context, rootNavigator: true).pop(),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: GlassButton(
                    label: 'End Workout',
                    compact: true,
                    loading: vm.endLoading,
                    disabled: vm.endLoading,
                    onPressed: () async {
                      Navigator.of(context, rootNavigator: true).pop();
                      await vm.endWorkout();
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── New Exercise Modal ──────────────────────────────────────────────────────────

class _NewExerciseModal extends StatelessWidget {
  const _NewExerciseModal({
    required this.vm,
    required this.nameCtrl,
    required this.volumeOptions,
    required this.onCreated,
  });

  final SessionViewModel vm;
  final TextEditingController nameCtrl;
  final List<SegmentOption<String>> volumeOptions;
  final VoidCallback onCreated;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: vm,
      builder: (ctx, _) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('New Exercise',
                  style: TextStyle(
                      fontSize: AppTextStyles.lg,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary)),
              const SizedBox(height: AppSpacing.md),
              LambdaInput(
                controller: nameCtrl,
                placeholder: 'Exercise name',
                textCapitalization: TextCapitalization.words,
                enabled: !vm.newExCreating,
                onChanged: (v) => vm.newExName = v,
              ),
              const SizedBox(height: AppSpacing.md),
              Text('Volume type',
                  style: TextStyle(
                      fontSize: AppTextStyles.sm,
                      fontWeight: FontWeight.w500,
                      color: AppColors.primary)),
              const SizedBox(height: AppSpacing.xs),
              SegmentedControl<String>(
                options: volumeOptions,
                value: vm.newExVolumeType,
                onChange: vm.setNewExVolumeType,
              ),
              const SizedBox(height: AppSpacing.lg),
              Row(
                children: [
                  Expanded(
                    child: GlassButton(
                      label: 'Cancel',
                      color: AppColors.danger,
                      compact: true,
                      onPressed: () =>
                          Navigator.of(ctx, rootNavigator: true).pop(),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: GlassButton(
                      label: 'Create',
                      compact: true,
                      loading: vm.newExCreating,
                      disabled: vm.newExCreating,
                      onPressed: () async {
                        final id = await vm.submitNewExercise();
                        if (id != null && ctx.mounted) {
                          Navigator.of(ctx, rootNavigator: true).pop();
                          onCreated();
                        }
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── New Variation Modal ─────────────────────────────────────────────────────────

class _NewVariationModal extends StatelessWidget {
  const _NewVariationModal({
    required this.vm,
    required this.nameCtrl,
    required this.onCreated,
  });

  final SessionViewModel vm;
  final TextEditingController nameCtrl;
  final VoidCallback onCreated;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: vm,
      builder: (ctx, _) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('New Variation',
                  style: TextStyle(
                      fontSize: AppTextStyles.lg,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary)),
              const SizedBox(height: AppSpacing.md),
              LambdaInput(
                controller: nameCtrl,
                placeholder: 'Variation name',
                textCapitalization: TextCapitalization.words,
                enabled: !vm.newVarCreating,
                onChanged: (v) => vm.newVarName = v,
              ),
              const SizedBox(height: AppSpacing.lg),
              Row(
                children: [
                  Expanded(
                    child: GlassButton(
                      label: 'Cancel',
                      color: AppColors.danger,
                      compact: true,
                      onPressed: () =>
                          Navigator.of(ctx, rootNavigator: true).pop(),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: GlassButton(
                      label: 'Create',
                      compact: true,
                      loading: vm.newVarCreating,
                      disabled: vm.newVarCreating,
                      onPressed: () async {
                        final id = await vm.submitNewVariation();
                        if (id != null && ctx.mounted) {
                          Navigator.of(ctx, rootNavigator: true).pop();
                          onCreated();
                        }
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
