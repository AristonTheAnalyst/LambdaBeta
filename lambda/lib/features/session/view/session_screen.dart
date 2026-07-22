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
    _endNotesCtrl.clear();
    _vm.endNotes = '';
    showLambdaModal(
      context,
      fitContent: true,
      keyboardAware: true,
      child: _EndWorkoutModal(vm: _vm, notesCtrl: _endNotesCtrl),
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
      child: _LogSetModal(
        vm: _vm,
        weightCtrl: _logWeightCtrl,
        repsCtrl: _logRepsCtrl,
        notesCtrl: _logNotesCtrl,
        onNewExercise: () {
          Navigator.of(context, rootNavigator: true).pop();
          _openNewExerciseModal(forLog: true);
        },
        onNewVariation: () {
          Navigator.of(context, rootNavigator: true).pop();
          _openNewVariationModal(forLog: true);
        },
      ),
    );
  }

  void _openEditSetModal(WorkoutSet s) {
    _vm.openEditSet(s);
    _editWeightCtrl.text = _vm.editWeight;
    _editRepsCtrl.text   = _vm.editRepsOrDuration;
    _editNotesCtrl.text  = _vm.editNotes;
    showLambdaModal(
      context,
      fitContent: true,
      keyboardAware: true,
      child: _EditSetModal(
        vm: _vm,
        weightCtrl: _editWeightCtrl,
        repsCtrl: _editRepsCtrl,
        notesCtrl: _editNotesCtrl,
        onDelete: () {
          Navigator.of(context, rootNavigator: true).pop();
          _confirmDeleteSet(s.setId);
        },
        onNewExercise: () {
          Navigator.of(context, rootNavigator: true).pop();
          _openNewExerciseModal(forLog: false);
        },
        onNewVariation: () {
          Navigator.of(context, rootNavigator: true).pop();
          _openNewVariationModal(forLog: false);
        },
      ),
    ).then((_) => _vm.clearEditSet());
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

  void _openNewExerciseModal({required bool forLog}) {
    _vm.prepareNewExercise(forLog: forLog);
    _newExNameCtrl.clear();
    showLambdaModal(
      context,
      fitContent: true,
      keyboardAware: true,
      child: _NewExerciseModal(
          vm: _vm, nameCtrl: _newExNameCtrl, volumeOptions: _volumeOptions),
    );
  }

  void _openNewVariationModal({required bool forLog}) {
    _vm.prepareNewVariation(forLog: forLog);
    _newVarNameCtrl.clear();
    showLambdaModal(
      context,
      fitContent: true,
      keyboardAware: true,
      child: _NewVariationModal(vm: _vm, nameCtrl: _newVarNameCtrl),
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

// ── Log Set Modal ──────────────────────────────────────────────────────────────

class _LogSetModal extends StatelessWidget {
  const _LogSetModal({
    required this.vm,
    required this.weightCtrl,
    required this.repsCtrl,
    required this.notesCtrl,
    required this.onNewExercise,
    required this.onNewVariation,
  });

  final SessionViewModel vm;
  final TextEditingController weightCtrl;
  final TextEditingController repsCtrl;
  final TextEditingController notesCtrl;
  final VoidCallback onNewExercise;
  final VoidCallback onNewVariation;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: vm,
      builder: (ctx, _) {
        final detail = vm.selectedExDetail;
        final exOptions = vm.exercises
            .map((d) => DropdownOption(
                label: toProperCase(d.name), value: d.exerciseId))
            .toList();
        final varOptions = [
          const DropdownOption<String?>(label: 'None', value: null),
          ...(detail?.assignedVariations ?? []).map((v) => DropdownOption(
              label: toProperCase(v.name), value: v.variationId)),
        ];

        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Log Set',
                    style: TextStyle(
                        fontSize: AppTextStyles.lg,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary)),
                const SizedBox(height: AppSpacing.md),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      flex: 3,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Exercise',
                              style: TextStyle(
                                  fontSize: AppTextStyles.sm,
                                  fontWeight: FontWeight.w500,
                                  color: AppColors.primary)),
                          const SizedBox(height: AppSpacing.xs),
                          DropdownSelect<String>(
                            options: exOptions,
                            value: vm.selectedExId,
                            onChange: vm.selectExercise,
                            placeholder: 'Select exercise…',
                            searchable: true,
                            onCreateNew: onNewExercise,
                            createNewLabel: 'New Exercise',
                          ),
                        ],
                      ),
                    ),
                    if (detail != null) ...[
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        flex: 2,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Variation',
                                style: TextStyle(
                                    fontSize: AppTextStyles.sm,
                                    fontWeight: FontWeight.w500,
                                    color: AppColors.primary)),
                            const SizedBox(height: AppSpacing.xs),
                            DropdownSelect<String?>(
                              options: varOptions,
                              value: vm.selectedVarId,
                              onChange: vm.selectVariation,
                              placeholder: 'None',
                              onCreateNew: onNewVariation,
                              createNewLabel: 'New Variation',
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
                if (detail != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  LambdaInput(
                    controller: weightCtrl,
                    label: 'Weight (optional)',
                    placeholder: 'kg',
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true),
                    onChanged: (v) => vm.logWeight = v,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  LambdaInput(
                    controller: repsCtrl,
                    label: detail.volumeType == 'reps'
                        ? 'Reps'
                        : 'Duration (seconds)',
                    placeholder: detail.volumeType == 'reps'
                        ? 'e.g. 10,8,6'
                        : 'e.g. 60,45',
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: false),
                    onChanged: (v) => vm.logRepsOrDuration = v,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  LambdaInput(
                    controller: notesCtrl,
                    label: 'Set notes (optional)',
                    placeholder: 'Notes…',
                    onChanged: (v) => vm.logNotes = v,
                  ),
                ],
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
                        label: 'Log Set',
                        compact: true,
                        loading: vm.logLoading,
                        disabled: vm.logLoading,
                        onPressed: () async {
                          final ok = await vm.submitLogSet();
                          if (ok && ctx.mounted) {
                            Navigator.of(ctx, rootNavigator: true).pop();
                          }
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xxl),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ── Edit Set Modal ─────────────────────────────────────────────────────────────

class _EditSetModal extends StatelessWidget {
  const _EditSetModal({
    required this.vm,
    required this.weightCtrl,
    required this.repsCtrl,
    required this.notesCtrl,
    required this.onDelete,
    required this.onNewExercise,
    required this.onNewVariation,
  });

  final SessionViewModel vm;
  final TextEditingController weightCtrl;
  final TextEditingController repsCtrl;
  final TextEditingController notesCtrl;
  final VoidCallback onDelete;
  final VoidCallback onNewExercise;
  final VoidCallback onNewVariation;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: vm,
      builder: (ctx, _) {
        final detail = vm.editExDetail;
        final exOptions = vm.exercises
            .map((d) => DropdownOption(
                label: toProperCase(d.name), value: d.exerciseId))
            .toList();
        final varOptions = [
          const DropdownOption<String?>(label: 'None', value: null),
          ...(detail?.assignedVariations ?? []).map((v) => DropdownOption(
              label: toProperCase(v.name), value: v.variationId)),
        ];

        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text('Edit Set',
                          style: TextStyle(
                              fontSize: AppTextStyles.lg,
                              fontWeight: FontWeight.w700,
                              color: AppColors.primary)),
                    ),
                    GlassButton(
                      label: '',
                      icon: Icons.delete_outline,
                      color: AppColors.danger,
                      compact: true,
                      onPressed: onDelete,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      flex: 3,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Exercise',
                              style: TextStyle(
                                  fontSize: AppTextStyles.sm,
                                  fontWeight: FontWeight.w500,
                                  color: AppColors.primary)),
                          const SizedBox(height: AppSpacing.xs),
                          DropdownSelect<String>(
                            options: exOptions,
                            value: vm.editExId,
                            onChange: vm.setEditExId,
                            placeholder: 'Select exercise…',
                            searchable: true,
                            onCreateNew: onNewExercise,
                            createNewLabel: 'New Exercise',
                          ),
                        ],
                      ),
                    ),
                    if (detail != null) ...[
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        flex: 2,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Variation',
                                style: TextStyle(
                                    fontSize: AppTextStyles.sm,
                                    fontWeight: FontWeight.w500,
                                    color: AppColors.primary)),
                            const SizedBox(height: AppSpacing.xs),
                            DropdownSelect<String?>(
                              options: varOptions,
                              value: vm.editVarId,
                              onChange: vm.setEditVarId,
                              placeholder: 'None',
                              onCreateNew: onNewVariation,
                              createNewLabel: 'New Variation',
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
                if (detail != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  LambdaInput(
                    controller: weightCtrl,
                    label: 'Weight (optional)',
                    placeholder: 'kg',
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true),
                    onChanged: (v) => vm.editWeight = v,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  LambdaInput(
                    controller: repsCtrl,
                    label: detail.volumeType == 'reps'
                        ? 'Reps'
                        : 'Duration (seconds)',
                    placeholder: detail.volumeType == 'reps'
                        ? 'e.g. 10,8,6'
                        : 'e.g. 60,45',
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: false),
                    onChanged: (v) => vm.editRepsOrDuration = v,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  LambdaInput(
                    controller: notesCtrl,
                    label: 'Set notes (optional)',
                    placeholder: 'Notes…',
                    onChanged: (v) => vm.editNotes = v,
                  ),
                ],
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
                        label: 'Save',
                        compact: true,
                        loading: vm.editLoading,
                        disabled: vm.editLoading,
                        onPressed: () async {
                          final ok = await vm.submitEditSet();
                          if (ok && ctx.mounted) {
                            Navigator.of(ctx, rootNavigator: true).pop();
                          }
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xxl),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ── New Exercise Modal ──────────────────────────────────────────────────────────

class _NewExerciseModal extends StatelessWidget {
  const _NewExerciseModal({
    required this.vm,
    required this.nameCtrl,
    required this.volumeOptions,
  });

  final SessionViewModel vm;
  final TextEditingController nameCtrl;
  final List<SegmentOption<String>> volumeOptions;

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
  const _NewVariationModal({required this.vm, required this.nameCtrl});

  final SessionViewModel vm;
  final TextEditingController nameCtrl;

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
