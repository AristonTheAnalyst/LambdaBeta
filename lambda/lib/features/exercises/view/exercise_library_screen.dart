import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/styles/app_colors.dart';
import '../../../../core/styles/app_fonts.dart';
import '../../../../core/styles/app_radius.dart';
import '../../../../core/styles/app_spacing.dart';
import '../../../../core/styles/app_text_styles.dart';
import '../../../../shared/widgets/app_card.dart';
import '../../../../core/utils/workout_format.dart';
import '../../../../data/models/custom_exercise.dart';
import '../../../../data/models/custom_variation.dart';
import '../../../../data/models/exercise_usage.dart';
import '../../../../shared/widgets/glass_button.dart';
import '../../../../shared/widgets/lambda_button.dart';
import '../../../../shared/widgets/lambda_input.dart';
import '../../../../shared/widgets/multi_select_sheet.dart';
import '../../../../shared/widgets/page_header.dart';
import '../../../../shared/widgets/slide_tab_bar.dart';
import '../../../../shared/widgets/slide_tab_view.dart';
import '../../../../shared/widgets/slide_up_modal.dart';
import '../viewmodel/exercise_viewmodel.dart';

class ExerciseLibraryScreen extends StatefulWidget {
  const ExerciseLibraryScreen({super.key});

  @override
  State<ExerciseLibraryScreen> createState() => _ExerciseLibraryScreenState();
}

class _ExerciseLibraryScreenState extends State<ExerciseLibraryScreen> {
  final _viewModel    = ExerciseViewModel();
  final _tabController = SlideTabController();
  final _exSearchController  = TextEditingController();
  final _varSearchController = TextEditingController();
  final _createExController  = TextEditingController();
  final _editExController    = TextEditingController();
  final _createVarController = TextEditingController();
  final _editVarController   = TextEditingController();

  @override
  void initState() {
    super.initState();
    _viewModel.fetchAll();
    _exSearchController.addListener(
        () => _viewModel.setExSearch(_exSearchController.text));
    _varSearchController.addListener(
        () => _viewModel.setVarSearch(_varSearchController.text));
  }

  @override
  void dispose() {
    _viewModel.dispose();
    _tabController.dispose();
    _exSearchController.dispose();
    _varSearchController.dispose();
    _createExController.dispose();
    _editExController.dispose();
    _createVarController.dispose();
    _editVarController.dispose();
    super.dispose();
  }

  // ── Create Exercise ──────────────────────────────────────────────────────────

  void _openCreateExercise() {
    _createExController.clear();
    _viewModel.openCreateExercise();
    showLambdaModal(
      context,
      fitContent: true,
      keyboardAware: true,
      child: _CreateExerciseModal(
        controller: _createExController,
        viewModel: _viewModel,
      ),
    );
  }

  // ── Create Variation ─────────────────────────────────────────────────────────

  void _openCreateVariation() {
    _createVarController.clear();
    _viewModel.openCreateVariation();
    showLambdaModal(
      context,
      fitContent: true,
      keyboardAware: true,
      child: _CreateVariationModal(
        controller: _createVarController,
        viewModel: _viewModel,
      ),
    );
  }

  // ── Edit Exercise ────────────────────────────────────────────────────────────

  void _openEditExercise(CustomExercise ex) {
    _editExController.text = ex.name;
    _viewModel.openEditExercise(ex);
    showLambdaModal(
      context,
      fitContent: true,
      keyboardAware: true,
      child: _EditExerciseModal(
        controller: _editExController,
        viewModel: _viewModel,
        onAddVariations: _openAddVariationsToExercise,
        onCreateNewVariation: _openCreateVariationFromEditEx,
        onDelete: _confirmDeleteExercise,
      ),
    );
  }

  Future<void> _openAddVariationsToExercise() async {
    final s = _viewModel.state.value;
    final options = s.editExAvailableVars
        .map((v) => MultiSelectOption(
            label: toProperCase(v.name), value: v.variationId))
        .toList();

    final selected = await showMultiSelectSheet<String>(
      context,
      options: options,
      selected: [],
      title: 'Add Variations',
      searchable: true,
      confirmLabel: 'Add',
      onCreateNew: _openCreateVariationFromEditEx,
      createNewLabel: 'New variation',
    );
    if (selected != null && selected.isNotEmpty) {
      _viewModel.addEditExVarIds(selected);
    }
  }

  void _openCreateVariationFromEditEx() {
    _createVarController.clear();
    _viewModel.openCreateVariation();
    showLambdaModal(
      context,
      fitContent: true,
      keyboardAware: true,
      child: _CreateVariationModal(
        controller: _createVarController,
        viewModel: _viewModel,
        onCreated: (id) => _viewModel.addEditExVarIds([id]),
      ),
    );
  }

  void _confirmDeleteExercise(String exerciseId, String name) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Delete Exercise',
            style: AppFonts.ui(fontWeight: FontWeight.w800, color: AppColors.danger)),
        content: Text('Remove "$name"? This will unassign it from all sets.',
            style: AppFonts.ui(color: AppColors.muted)),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text('Cancel',
                  style: AppFonts.ui(color: AppColors.muted))),
          TextButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                Navigator.of(context, rootNavigator: true).pop();
                _viewModel.deleteExercise(exerciseId);
              },
              child: Text('Delete',
                  style: AppFonts.ui(
                      color: AppColors.danger,
                      fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }

  // ── Edit Variation ───────────────────────────────────────────────────────────

  void _openEditVariation(CustomVariation v) {
    _editVarController.text = v.name;
    _viewModel.openEditVariation(v);
    showLambdaModal(
      context,
      fitContent: true,
      keyboardAware: true,
      child: _EditVariationModal(
        controller: _editVarController,
        viewModel: _viewModel,
        onAddExercises: _openAddExercisesToVariation,
        onCreateNewExercise: _openCreateExerciseFromEditVar,
        onDelete: _confirmDeleteVariation,
      ),
    );
  }

  Future<void> _openAddExercisesToVariation() async {
    final s = _viewModel.state.value;
    final options = s.editVarAvailableExs
        .map((e) => MultiSelectOption(
            label: toProperCase(e.name), value: e.exerciseId))
        .toList();

    final selected = await showMultiSelectSheet<String>(
      context,
      options: options,
      selected: [],
      title: 'Add Exercises',
      searchable: true,
      confirmLabel: 'Add',
      onCreateNew: _openCreateExerciseFromEditVar,
      createNewLabel: 'New exercise',
    );
    if (selected != null && selected.isNotEmpty) {
      _viewModel.addEditVarExIds(selected);
    }
  }

  void _openCreateExerciseFromEditVar() {
    _createExController.clear();
    _viewModel.openCreateExercise();
    showLambdaModal(
      context,
      fitContent: true,
      keyboardAware: true,
      child: _CreateExerciseModal(
        controller: _createExController,
        viewModel: _viewModel,
        onCreated: (id) => _viewModel.addEditVarExIds([id]),
      ),
    );
  }

  void _confirmDeleteVariation(String variationId, String name) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Delete Variation',
            style: AppFonts.ui(fontWeight: FontWeight.w800, color: AppColors.danger)),
        content: Text('Remove "$name"?',
            style: AppFonts.ui(color: AppColors.muted)),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text('Cancel',
                  style: AppFonts.ui(color: AppColors.muted))),
          TextButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                Navigator.of(context, rootNavigator: true).pop();
                _viewModel.deleteVariation(variationId);
              },
              child: Text('Delete',
                  style: AppFonts.ui(
                      color: AppColors.danger,
                      fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: ValueListenableBuilder<ExerciseState>(
        valueListenable: _viewModel.state,
        builder: (context, state, _) {
          return Column(
            children: [
              PageHeader(
                title: 'Exercises & Variations',
                left: GestureDetector(
                  onTap: () => context.pop(),
                  child: Icon(Icons.arrow_back_ios_new,
                      size: 18, color: AppColors.accent),
                ),
              ),
              SlideTabBar(
                tabs: ['Exercises', 'Variations'],
                activeIndex: state.activeTab,
                onTap: (i) {
                  _viewModel.setTab(i);
                  _tabController.jumpTo(i);
                },
              ),
              if (state.error != null)
                Container(
                  width: double.infinity,
                  color: AppColors.dangerBg,
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
                  child: Text(state.error!,
                      style: AppFonts.ui(
                          color: AppColors.danger,
                          fontSize: AppTextStyles.sm)),
                ),
              SlideTabView(
                tabs: [
                  _ExercisesPanel(
                    state: state,
                    searchController: _exSearchController,
                    onAdd: _openCreateExercise,
                    onEdit: _openEditExercise,
                    onPrev: _viewModel.prevExPage,
                    onNext: _viewModel.nextExPage,
                  ),
                  _VariationsPanel(
                    state: state,
                    searchController: _varSearchController,
                    onAdd: _openCreateVariation,
                    onEdit: _openEditVariation,
                    onPrev: _viewModel.prevVarPage,
                    onNext: _viewModel.nextVarPage,
                  ),
                ],
                controller: _tabController,
                onPageChanged: _viewModel.setTab,
              ),
            ],
          );
        },
      ),
    );
  }
}

// ── Panels ─────────────────────────────────────────────────────────────────────

class _ExercisesPanel extends StatelessWidget {
  const _ExercisesPanel({
    required this.state,
    required this.searchController,
    required this.onAdd,
    required this.onEdit,
    required this.onPrev,
    required this.onNext,
  });

  final ExerciseState state;
  final TextEditingController searchController;
  final VoidCallback onAdd;
  final ValueChanged<CustomExercise> onEdit;
  final VoidCallback onPrev;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return state.isLoading
        ? Center(
            child: CircularProgressIndicator(color: AppColors.accent))
        : ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text('All Exercises',
                        style: AppFonts.ui(
                            fontSize: AppTextStyles.lg,
                            fontWeight: FontWeight.w800,
                            color: AppColors.primary)),
                  ),
                  if (state.exercises.isNotEmpty)
                    Expanded(
                      child: TextField(
                        controller: searchController,
                        style: AppFonts.ui(
                            fontSize: AppTextStyles.sm,
                            color: AppColors.primary),
                        decoration: InputDecoration(
                          hintText: 'Search…',
                          hintStyle:
                              AppFonts.ui(color: AppColors.muted),
                          filled: true,
                          fillColor: AppColors.surface,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(
                                AppRadius.md),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 8),
                          isDense: true,
                        ),
                      ),
                    ),
                  const SizedBox(width: AppSpacing.sm),
                  GlassButton(
                      label: '',
                      icon: Icons.add,
                      onPressed: onAdd,
                      compact: true),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              if (state.exercises.isEmpty)
                Center(
                  child: Padding(
                    padding:
                        const EdgeInsets.only(top: AppSpacing.xxl),
                    child: Column(
                      children: [
                        Text('No exercises yet',
                            style: AppFonts.ui(
                                fontSize: AppTextStyles.md,
                                fontWeight: FontWeight.w600,
                                color: AppColors.primary)),
                        SizedBox(height: AppSpacing.sm),
                        Text('Tap + to create your first exercise.',
                            style: AppFonts.ui(
                                fontSize: AppTextStyles.sm,
                                color: AppColors.muted)),
                      ],
                    ),
                  ),
                )
              else if (state.pagedExercises.isEmpty)
                Text('No results.',
                    style: AppFonts.ui(
                        color: AppColors.muted,
                        fontSize: AppTextStyles.sm))
              else ...[
                ...state.pagedExercises.map((ex) => Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: AppCard(
                        onTap: () => onEdit(ex),
                        padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.md, vertical: AppSpacing.sm),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(toProperCase(ex.name),
                                      style: AppFonts.ui(
                                          fontSize: AppTextStyles.md,
                                          fontWeight: FontWeight.w600,
                                          color: AppColors.primary)),
                                  if (state.usage[ex.exerciseId] != null)
                                    Text(_usageLine(state.usage[ex.exerciseId]!, isExercise: true),
                                        style: AppFonts.ui(
                                            fontSize: AppTextStyles.xs,
                                            color: AppColors.muted)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    )),
                if (state.exTotal > _pageSize)
                  _PaginationBar(
                    shown: state.pagedExercises.length,
                    total: state.exTotal,
                    page: state.exPage,
                    canPrev: state.canPrevEx,
                    canNext: state.canNextEx,
                    onPrev: onPrev,
                    onNext: onNext,
                  ),
              ],
            ],
          );
  }
}

class _VariationsPanel extends StatelessWidget {
  const _VariationsPanel({
    required this.state,
    required this.searchController,
    required this.onAdd,
    required this.onEdit,
    required this.onPrev,
    required this.onNext,
  });

  final ExerciseState state;
  final TextEditingController searchController;
  final VoidCallback onAdd;
  final ValueChanged<CustomVariation> onEdit;
  final VoidCallback onPrev;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return state.isLoading
        ? Center(
            child: CircularProgressIndicator(color: AppColors.accent))
        : ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text('All Variations',
                        style: AppFonts.ui(
                            fontSize: AppTextStyles.lg,
                            fontWeight: FontWeight.w800,
                            color: AppColors.primary)),
                  ),
                  if (state.variations.isNotEmpty)
                    Expanded(
                      child: TextField(
                        controller: searchController,
                        style: AppFonts.ui(
                            fontSize: AppTextStyles.sm,
                            color: AppColors.primary),
                        decoration: InputDecoration(
                          hintText: 'Search…',
                          hintStyle:
                              AppFonts.ui(color: AppColors.muted),
                          filled: true,
                          fillColor: AppColors.surface,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(
                                AppRadius.md),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 8),
                          isDense: true,
                        ),
                      ),
                    ),
                  const SizedBox(width: AppSpacing.sm),
                  GlassButton(
                      label: '',
                      icon: Icons.add,
                      onPressed: onAdd,
                      compact: true),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              if (state.variations.isEmpty)
                Center(
                  child: Padding(
                    padding:
                        const EdgeInsets.only(top: AppSpacing.xxl),
                    child: Column(
                      children: [
                        Text('No variations yet',
                            style: AppFonts.ui(
                                fontSize: AppTextStyles.md,
                                fontWeight: FontWeight.w600,
                                color: AppColors.primary)),
                        SizedBox(height: AppSpacing.sm),
                        Text('Tap + to create your first variation.',
                            style: AppFonts.ui(
                                fontSize: AppTextStyles.sm,
                                color: AppColors.muted)),
                      ],
                    ),
                  ),
                )
              else if (state.pagedVariations.isEmpty)
                Text('No results.',
                    style: AppFonts.ui(
                        color: AppColors.muted,
                        fontSize: AppTextStyles.sm))
              else ...[
                ...state.pagedVariations.map((v) => Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: AppCard(
                        onTap: () => onEdit(v),
                        padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.md, vertical: AppSpacing.sm),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(toProperCase(v.name),
                                      style: AppFonts.ui(
                                          fontSize: AppTextStyles.md,
                                          fontWeight: FontWeight.w600,
                                          color: AppColors.primary)),
                                  if (state.usage[v.variationId] != null)
                                    Text(_usageLine(state.usage[v.variationId]!, isExercise: false),
                                        style: AppFonts.ui(
                                            fontSize: AppTextStyles.xs,
                                            color: AppColors.muted)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    )),
                if (state.varTotal > _pageSize)
                  _PaginationBar(
                    shown: state.pagedVariations.length,
                    total: state.varTotal,
                    page: state.varPage,
                    canPrev: state.canPrevVar,
                    canNext: state.canNextVar,
                    onPrev: onPrev,
                    onNext: onNext,
                  ),
              ],
            ],
          );
  }
}

// ── Library helpers ─────────────────────────────────────────────────────────────

const _pageSize = 10;

/// Builds the muted usage line under an exercise/variation name — just the
/// last-used label (workout/set counts intentionally not shown).
String _usageLine(ExerciseUsage u, {required bool isExercise}) => u.lastUsedLabel;

class _PaginationBar extends StatelessWidget {
  const _PaginationBar({
    required this.shown,
    required this.total,
    required this.page,
    required this.canPrev,
    required this.canNext,
    required this.onPrev,
    required this.onNext,
  });

  final int shown;
  final int total;
  final int page;
  final bool canPrev;
  final bool canNext;
  final VoidCallback onPrev;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm, bottom: AppSpacing.md),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          GestureDetector(
            onTap: canPrev ? onPrev : null,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: canPrev ? AppColors.accentBg : AppColors.surfaceHigh,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(
                    color: canPrev ? AppColors.accent.withValues(alpha: 0.35) : AppColors.border),
              ),
              child: Icon(Icons.chevron_left,
                  size: 16, color: canPrev ? AppColors.accent : AppColors.muted),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Text('$shown of $total',
              style: AppFonts.mono(fontSize: 11, color: AppColors.muted)),
          const SizedBox(width: AppSpacing.md),
          GestureDetector(
            onTap: canNext ? onNext : null,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: canNext ? AppColors.accentBg : AppColors.surfaceHigh,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(
                    color: canNext ? AppColors.accent.withValues(alpha: 0.35) : AppColors.border),
              ),
              child: Icon(Icons.chevron_right,
                  size: 16, color: canNext ? AppColors.accent : AppColors.muted),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Create Exercise Modal ───────────────────────────────────────────────────────

class _CreateExerciseModal extends StatelessWidget {
  const _CreateExerciseModal({
    required this.controller,
    required this.viewModel,
    this.onCreated,
  });

  final TextEditingController controller;
  final ExerciseViewModel viewModel;
  final ValueChanged<String>? onCreated;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ExerciseState>(
      valueListenable: viewModel.state,
      builder: (context, state, _) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('New Exercise',
                    style: AppFonts.ui(
                        fontSize: AppTextStyles.lg,
                        fontWeight: FontWeight.w800,
                        color: AppColors.primary)),
                const SizedBox(height: AppSpacing.md),
                LambdaInput(
                  controller: controller,
                  placeholder: 'Exercise name',
                  enabled: !state.isCreatingEx,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.done,
                  onChanged: viewModel.setCreateExName,
                ),
                const SizedBox(height: AppSpacing.lg),
                Row(
                  children: [
                    Expanded(
                      child: LambdaButton(
                        label: 'Cancel',
                        variant: ButtonVariant.ghost,
                        onPressed: () {
                          Navigator.of(context, rootNavigator: true).pop();
                          viewModel.closeCreateExercise();
                        },
                        disabled: state.isCreatingEx,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: LambdaButton(
                        label: 'Create',
                        onPressed: () async {
                          final id = await viewModel.submitCreateExercise();
                          if (id != null && context.mounted) {
                            Navigator.of(context, rootNavigator: true).pop();
                            onCreated?.call(id);
                          }
                        },
                        loading: state.isCreatingEx,
                        disabled: state.isCreatingEx,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ── Create Variation Modal ──────────────────────────────────────────────────────

class _CreateVariationModal extends StatelessWidget {
  const _CreateVariationModal({
    required this.controller,
    required this.viewModel,
    this.onCreated,
  });

  final TextEditingController controller;
  final ExerciseViewModel viewModel;
  final ValueChanged<String>? onCreated;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ExerciseState>(
      valueListenable: viewModel.state,
      builder: (context, state, _) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('New Variation',
                    style: AppFonts.ui(
                        fontSize: AppTextStyles.lg,
                        fontWeight: FontWeight.w800,
                        color: AppColors.primary)),
                const SizedBox(height: AppSpacing.md),
                LambdaInput(
                  controller: controller,
                  placeholder: 'Variation name',
                  enabled: !state.isCreatingVar,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.done,
                  onChanged: viewModel.setCreateVarName,
                ),
                const SizedBox(height: AppSpacing.lg),
                Row(
                  children: [
                    Expanded(
                      child: LambdaButton(
                        label: 'Cancel',
                        variant: ButtonVariant.ghost,
                        onPressed: () {
                          Navigator.of(context, rootNavigator: true).pop();
                          viewModel.closeCreateVariation();
                        },
                        disabled: state.isCreatingVar,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: LambdaButton(
                        label: 'Create',
                        onPressed: () async {
                          final id = await viewModel.submitCreateVariation();
                          if (id != null && context.mounted) {
                            Navigator.of(context, rootNavigator: true).pop();
                            onCreated?.call(id);
                          }
                        },
                        loading: state.isCreatingVar,
                        disabled: state.isCreatingVar,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ── Edit Exercise Modal ─────────────────────────────────────────────────────────

class _EditExerciseModal extends StatelessWidget {
  const _EditExerciseModal({
    required this.controller,
    required this.viewModel,
    required this.onAddVariations,
    required this.onCreateNewVariation,
    required this.onDelete,
  });

  final TextEditingController controller;
  final ExerciseViewModel viewModel;
  final VoidCallback onAddVariations;
  final VoidCallback onCreateNewVariation;
  final void Function(String id, String name) onDelete;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ExerciseState>(
      valueListenable: viewModel.state,
      builder: (context, state, _) {
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text('Edit Exercise',
                          style: AppFonts.ui(
                              fontSize: AppTextStyles.lg,
                              fontWeight: FontWeight.w800,
                              color: AppColors.primary)),
                    ),
                    GlassButton(
                      label: '',
                      icon: Icons.delete_outline,
                      color: AppColors.danger,
                      compact: true,
                      onPressed: () => onDelete(
                          state.editExercise!.exerciseId,
                          state.editExName),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                LambdaInput(
                  controller: controller,
                  placeholder: 'Exercise name',
                  enabled: !state.isSaving,
                  textCapitalization: TextCapitalization.words,
                  onChanged: viewModel.setEditExName,
                ),
                const SizedBox(height: AppSpacing.lg),
                Divider(color: AppColors.border),
                const SizedBox(height: AppSpacing.sm),
                Text('Assigned Variations',
                    style: AppFonts.ui(
                        fontSize: AppTextStyles.md,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary)),
                const SizedBox(height: AppSpacing.sm),
                if (state.editExLoadingVars)
                  Center(
                      child: CircularProgressIndicator(
                          color: AppColors.accent))
                else if (state.editExAssignedVars.isEmpty)
                  Text('No variations assigned yet.',
                      style: AppFonts.ui(
                          color: AppColors.muted,
                          fontSize: AppTextStyles.sm))
                else
                  ...state.editExAssignedVars.asMap().entries.map((e) {
                    final v = e.value;
                    return Container(
                      padding: const EdgeInsets.symmetric(
                          vertical: AppSpacing.sm),
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            color: e.key <
                                    state.editExAssignedVars.length - 1
                                ? AppColors.border
                                : Colors.transparent,
                            width: 0.5,
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(toProperCase(v.name),
                                style: AppFonts.ui(
                                    fontSize: AppTextStyles.md,
                                    color: AppColors.primary)),
                          ),
                          GlassButton(
                            label: '',
                            icon: Icons.delete_outline,
                            color: AppColors.danger,
                            compact: true,
                            onPressed: () =>
                                viewModel.removeEditExVarId(v.variationId),
                          ),
                        ],
                      ),
                    );
                  }),
                const SizedBox(height: AppSpacing.sm),
                GlassButton(
                  label: 'Add Variations',
                  icon: Icons.add,
                  onPressed: onAddVariations,
                ),
                const SizedBox(height: AppSpacing.lg),
                Row(
                  children: [
                    Expanded(
                      child: LambdaButton(
                        label: 'Cancel',
                        variant: ButtonVariant.ghost,
                        onPressed: () {
                          Navigator.of(context, rootNavigator: true).pop();
                          viewModel.closeEditExercise();
                        },
                        disabled: state.isSaving,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: LambdaButton(
                        label: 'Save',
                        onPressed: () async {
                          // Rename guardrail: renames only affect future sets —
                          // past sets keep the name as logged (name snapshots).
                          final original = state.editExercise!.name;
                          final renamed = state.editExName.trim() != original;
                          if (renamed) {
                            final ok = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                backgroundColor: AppColors.surface,
                                title: Text('Rename "$original"?',
                                    style: AppFonts.ui(
                                        fontWeight: FontWeight.w800, color: AppColors.primary)),
                                content: Text(
                                    'Past sets keep the name as logged; only future sets use the new name.',
                                    style: AppFonts.ui(color: AppColors.muted)),
                                actions: [
                                  TextButton(
                                      onPressed: () => Navigator.of(ctx).pop(false),
                                      child: Text('Cancel',
                                          style: AppFonts.ui(color: AppColors.muted))),
                                  TextButton(
                                      onPressed: () => Navigator.of(ctx).pop(true),
                                      child: Text('Rename',
                                          style: AppFonts.ui(
                                              color: AppColors.accent,
                                              fontWeight: FontWeight.w600))),
                                ],
                              ),
                            );
                            if (ok != true || !context.mounted) return;
                          }
                          await viewModel.saveEditExercise();
                          if (context.mounted) {
                            Navigator.of(context, rootNavigator: true).pop();
                          }
                        },
                        loading: state.isSaving,
                        disabled: state.isSaving,
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

// ── Edit Variation Modal ────────────────────────────────────────────────────────

class _EditVariationModal extends StatelessWidget {
  const _EditVariationModal({
    required this.controller,
    required this.viewModel,
    required this.onAddExercises,
    required this.onCreateNewExercise,
    required this.onDelete,
  });

  final TextEditingController controller;
  final ExerciseViewModel viewModel;
  final VoidCallback onAddExercises;
  final VoidCallback onCreateNewExercise;
  final void Function(String id, String name) onDelete;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ExerciseState>(
      valueListenable: viewModel.state,
      builder: (context, state, _) {
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text('Edit Variation',
                          style: AppFonts.ui(
                              fontSize: AppTextStyles.lg,
                              fontWeight: FontWeight.w800,
                              color: AppColors.primary)),
                    ),
                    GlassButton(
                      label: '',
                      icon: Icons.delete_outline,
                      color: AppColors.danger,
                      compact: true,
                      onPressed: () => onDelete(
                          state.editVariation!.variationId,
                          state.editVarName),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                LambdaInput(
                  controller: controller,
                  placeholder: 'Variation name',
                  enabled: !state.isSaving,
                  textCapitalization: TextCapitalization.words,
                  onChanged: viewModel.setEditVarName,
                ),
                const SizedBox(height: AppSpacing.lg),
                Divider(color: AppColors.border),
                const SizedBox(height: AppSpacing.sm),
                Text('Assigned Exercises',
                    style: AppFonts.ui(
                        fontSize: AppTextStyles.md,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary)),
                const SizedBox(height: AppSpacing.sm),
                if (state.editVarLoadingExs)
                  Center(
                      child: CircularProgressIndicator(
                          color: AppColors.accent))
                else if (state.editVarAssignedExs.isEmpty)
                  Text('No exercises assigned yet.',
                      style: AppFonts.ui(
                          color: AppColors.muted,
                          fontSize: AppTextStyles.sm))
                else
                  ...state.editVarAssignedExs.asMap().entries.map((e) {
                    final ex = e.value;
                    return Container(
                      padding: const EdgeInsets.symmetric(
                          vertical: AppSpacing.sm),
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            color: e.key <
                                    state.editVarAssignedExs.length - 1
                                ? AppColors.border
                                : Colors.transparent,
                            width: 0.5,
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(toProperCase(ex.name),
                                style: AppFonts.ui(
                                    fontSize: AppTextStyles.md,
                                    color: AppColors.primary)),
                          ),
                          GlassButton(
                            label: '',
                            icon: Icons.delete_outline,
                            color: AppColors.danger,
                            compact: true,
                            onPressed: () =>
                                viewModel.removeEditVarExId(ex.exerciseId),
                          ),
                        ],
                      ),
                    );
                  }),
                const SizedBox(height: AppSpacing.sm),
                GlassButton(
                  label: 'Add Exercises',
                  icon: Icons.add,
                  onPressed: onAddExercises,
                ),
                const SizedBox(height: AppSpacing.lg),
                Row(
                  children: [
                    Expanded(
                      child: LambdaButton(
                        label: 'Cancel',
                        variant: ButtonVariant.ghost,
                        onPressed: () {
                          Navigator.of(context, rootNavigator: true).pop();
                          viewModel.closeEditVariation();
                        },
                        disabled: state.isSaving,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: LambdaButton(
                        label: 'Save',
                        onPressed: () async {
                          final original = state.editVariation!.name;
                          final renamed = state.editVarName.trim() != original;
                          if (renamed) {
                            final ok = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                backgroundColor: AppColors.surface,
                                title: Text('Rename "$original"?',
                                    style: AppFonts.ui(
                                        fontWeight: FontWeight.w800, color: AppColors.primary)),
                                content: Text(
                                    'Past sets keep the name as logged; only future sets use the new name.',
                                    style: AppFonts.ui(color: AppColors.muted)),
                                actions: [
                                  TextButton(
                                      onPressed: () => Navigator.of(ctx).pop(false),
                                      child: Text('Cancel',
                                          style: AppFonts.ui(color: AppColors.muted))),
                                  TextButton(
                                      onPressed: () => Navigator.of(ctx).pop(true),
                                      child: Text('Rename',
                                          style: AppFonts.ui(
                                              color: AppColors.accent,
                                              fontWeight: FontWeight.w600))),
                                ],
                              ),
                            );
                            if (ok != true || !context.mounted) return;
                          }
                          await viewModel.saveEditVariation();
                          if (context.mounted) {
                            Navigator.of(context, rootNavigator: true).pop();
                          }
                        },
                        loading: state.isSaving,
                        disabled: state.isSaving,
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
