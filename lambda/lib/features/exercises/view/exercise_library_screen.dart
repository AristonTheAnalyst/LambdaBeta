import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/styles/app_colors.dart';
import '../../../../core/styles/app_fonts.dart';
import '../../../../core/styles/app_radius.dart';
import '../../../../core/styles/app_spacing.dart';
import '../../../../core/styles/app_text_styles.dart';
import '../../../../shared/widgets/app_card.dart';
import '../../../../shared/widgets/archived_sheet.dart';
import '../../../../shared/widgets/container_styles.dart';
import '../../../../core/utils/name_limit.dart';
import '../../../../core/utils/session_format.dart';
import '../../../../data/models/custom_exercise.dart';
import '../../../../data/models/custom_variation.dart';
import '../../../../data/models/exercise_usage.dart';
import '../../../../shared/widgets/glass_button.dart';
import '../../../../shared/widgets/lambda_button.dart';
import '../../../../shared/widgets/lambda_input.dart';
import '../../../../shared/widgets/name_limit_counter.dart';
import '../../../../shared/widgets/page_header.dart';
import '../../../../shared/widgets/slide_tab_bar.dart';
import '../../../../shared/widgets/slide_tab_view.dart';
import '../../../../shared/widgets/slide_up_modal.dart';
import '../viewmodel/exercise_viewmodel.dart';

class ExerciseLibraryScreen extends StatefulWidget {
  const ExerciseLibraryScreen({
    super.key,
    this.embedded = false,
    this.initialTab = 0,
  });

  /// When embedded in a hub tab, render one panel only — the hub owns the
  /// header and its own tab bar, so the nested header/tabs are hidden.
  final bool embedded;

  /// Which panel to show when [embedded]: 0 = Exercises, 1 = Variations.
  final int initialTab;

  @override
  State<ExerciseLibraryScreen> createState() => _ExerciseLibraryScreenState();
}

class _ExerciseLibraryScreenState extends State<ExerciseLibraryScreen> {
  final _viewModel = ExerciseViewModel();
  final _tabController = SlideTabController();
  final _exSearchController = TextEditingController();
  final _varSearchController = TextEditingController();
  final _createExController = TextEditingController();
  final _createVarController = TextEditingController();
  final _editVarController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _viewModel.fetchAll();
    if (widget.embedded && widget.initialTab == 1) {
      _viewModel.setTab(1);
    }
    _exSearchController.addListener(
      () => _viewModel.setExSearch(_exSearchController.text),
    );
    _varSearchController.addListener(
      () => _viewModel.setVarSearch(_varSearchController.text),
    );
  }

  @override
  void dispose() {
    _viewModel.dispose();
    _tabController.dispose();
    _exSearchController.dispose();
    _varSearchController.dispose();
    _createExController.dispose();
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

  // ── Archived dims ────────────────────────────────────────────────────────────

  void _openArchivedExercises() {
    showLambdaModal(
      context,
      fitContent: true,
      child: ArchivedSheet(
        title: 'Archived Exercises',
        emptyText: 'No archived exercises.',
        fetch: () async => [
          for (final e in await _viewModel.fetchArchivedExercises())
            (id: e.exerciseId, name: e.name),
        ],
        onRestore: (id) => _viewModel.reactivateExercise(id),
      ),
    );
  }

  void _openArchivedVariations() {
    showLambdaModal(
      context,
      fitContent: true,
      child: ArchivedSheet(
        title: 'Archived Variations',
        emptyText: 'No archived variations.',
        fetch: () async => [
          for (final v in await _viewModel.fetchArchivedVariations())
            (id: v.variationId, name: v.name),
        ],
        onRestore: (id) => _viewModel.reactivateVariation(id),
      ),
    );
  }

  // ── Edit Exercise ────────────────────────────────────────────────────────────

  void _openEditExercise(CustomExercise ex) async {
    // Exercise taps now go to the dedicated page (locked insights + rename /
    // archive) instead of the name-only bottom sheet.
    await context.push('/exercises/exercise/${ex.exerciseId}', extra: ex.name);
    // Rename/archive edits on the detail page must show immediately when the
    // library list is restored (its state lives on beneath the pushed route).
    _viewModel.fetchAll();
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
        onDelete: _confirmDeleteVariation,
      ),
    );
  }

  /// Deletes a never-used variation outright; archives a used one. The dialog
  /// copy follows the usage state so the user always knows which happened.
  Future<void> _confirmDeleteVariation(String variationId, String name) async {
    final used = await _viewModel.variationUsageCount(variationId) > 0;
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(
          used ? 'Archive Variation' : 'Delete Variation',
          style: AppFonts.ui(
            fontWeight: FontWeight.w800,
            color: AppColors.danger,
          ),
        ),
        content: Text(
          used
              ? 'Archive "$name"? It has been used, so it can\'t be fully '
                'deleted — it will disappear from pickers, but your logged '
                'history keeps it.'
              : 'Delete "$name"? This can\'t be undone.',
          style: AppFonts.ui(color: AppColors.muted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Cancel', style: AppFonts.ui(color: AppColors.muted)),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              Navigator.of(context, rootNavigator: true).pop();
              _viewModel.deleteVariation(variationId);
            },
            child: Text(
              used ? 'Archive' : 'Delete',
              style: AppFonts.ui(
                color: AppColors.danger,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
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
          final exercisesPanel = _ExercisesPanel(
            state: state,
            searchController: _exSearchController,
            onAdd: _openCreateExercise,
            onShowArchived: _openArchivedExercises,
            onEdit: _openEditExercise,
            onPrev: _viewModel.prevExPage,
            onNext: _viewModel.nextExPage,
          );
          final variationsPanel = _VariationsPanel(
            state: state,
            searchController: _varSearchController,
            onAdd: _openCreateVariation,
            onShowArchived: _openArchivedVariations,
            onEdit: _openEditVariation,
            onPrev: _viewModel.prevVarPage,
            onNext: _viewModel.nextVarPage,
          );
          return Column(
            children: [
              if (!widget.embedded) ...[
                PageHeader(
                  title: 'Exercises & Variations',
                  left: GestureDetector(
                    onTap: () => context.pop(),
                    child: Icon(
                      Icons.arrow_back_ios_new,
                      size: 18,
                      color: AppColors.accent,
                    ),
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
              ],
              if (state.error != null)
                Container(
                  width: double.infinity,
                  color: AppColors.dangerBg,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                    vertical: AppSpacing.sm,
                  ),
                  child: Text(
                    state.error!,
                    style: AppFonts.ui(
                      color: AppColors.danger,
                      fontSize: AppTextStyles.sm,
                    ),
                  ),
                ),
              if (widget.embedded)
                Expanded(
                  child: widget.initialTab == 0
                      ? exercisesPanel
                      : variationsPanel,
                )
              else
                SlideTabView(
                  tabs: [exercisesPanel, variationsPanel],
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
    required this.onShowArchived,
    required this.onEdit,
    required this.onPrev,
    required this.onNext,
  });

  final ExerciseState state;
  final TextEditingController searchController;
  final VoidCallback onAdd;
  final VoidCallback onShowArchived;
  final ValueChanged<CustomExercise> onEdit;
  final VoidCallback onPrev;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return state.isLoading
        ? Center(child: CircularProgressIndicator(color: AppColors.accent))
        : ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              Row(
                children: [
                  if (state.exercises.isNotEmpty)
                    Expanded(
                      child: TextField(
                        controller: searchController,
                        style: AppFonts.ui(
                          fontSize: AppTextStyles.sm,
                          color: AppColors.primary,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Search…',
                          hintStyle: AppFonts.ui(color: AppColors.muted),
                          filled: true,
                          fillColor: AppColors.surface,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(AppRadius.md),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          isDense: true,
                        ),
                      ),
                    ),
                  const SizedBox(width: AppSpacing.sm),
                  GlassButton(
                    label: '',
                    icon: Icons.add,
                    onPressed: onAdd,
                    compact: true,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  GlassButton(
                    label: '',
                    icon: Icons.archive_outlined,
                    onPressed: onShowArchived,
                    compact: true,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              if (state.exercises.isEmpty)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.xxl),
                    child: Column(
                      children: [
                        Text(
                          'No exercises yet',
                          style: AppFonts.ui(
                            fontSize: AppTextStyles.md,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primary,
                          ),
                        ),
                        SizedBox(height: AppSpacing.sm),
                        Text(
                          'Tap + to create your first exercise.',
                          style: AppFonts.ui(
                            fontSize: AppTextStyles.sm,
                            color: AppColors.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else if (state.pagedExercises.isEmpty)
                Text(
                  'No results.',
                  style: AppFonts.ui(
                    color: AppColors.muted,
                    fontSize: AppTextStyles.sm,
                  ),
                )
              else ...[
                ...state.pagedExercises.map(
                  (ex) => Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: AppCard(
                      onTap: () => onEdit(ex),
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                        vertical: AppSpacing.sm,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  toProperCase(ex.name),
                                  style: AppFonts.ui(
                                    fontSize: AppTextStyles.md,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.primary,
                                  ),
                                ),
                                if (state.usage[ex.exerciseId] != null)
                                  Text(
                                    _usageLine(
                                      state.usage[ex.exerciseId]!,
                                      isExercise: true,
                                    ),
                                    style: AppFonts.ui(
                                      fontSize: AppTextStyles.xs,
                                      color: AppColors.muted,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (state.exTotal > _pageSize)
                  _PaginationBar(
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
    required this.onShowArchived,
    required this.onEdit,
    required this.onPrev,
    required this.onNext,
  });

  final ExerciseState state;
  final TextEditingController searchController;
  final VoidCallback onAdd;
  final VoidCallback onShowArchived;
  final ValueChanged<CustomVariation> onEdit;
  final VoidCallback onPrev;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return state.isLoading
        ? Center(child: CircularProgressIndicator(color: AppColors.accent))
        : ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              Row(
                children: [
                  if (state.variations.isNotEmpty)
                    Expanded(
                      child: TextField(
                        controller: searchController,
                        style: AppFonts.ui(
                          fontSize: AppTextStyles.sm,
                          color: AppColors.primary,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Search…',
                          hintStyle: AppFonts.ui(color: AppColors.muted),
                          filled: true,
                          fillColor: AppColors.surface,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(AppRadius.md),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          isDense: true,
                        ),
                      ),
                    ),
                  const SizedBox(width: AppSpacing.sm),
                  GlassButton(
                    label: '',
                    icon: Icons.add,
                    onPressed: onAdd,
                    compact: true,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  GlassButton(
                    label: '',
                    icon: Icons.archive_outlined,
                    onPressed: onShowArchived,
                    compact: true,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              if (state.variations.isEmpty)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.xxl),
                    child: Column(
                      children: [
                        Text(
                          'No variations yet',
                          style: AppFonts.ui(
                            fontSize: AppTextStyles.md,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primary,
                          ),
                        ),
                        SizedBox(height: AppSpacing.sm),
                        Text(
                          'Tap + to create your first variation.',
                          style: AppFonts.ui(
                            fontSize: AppTextStyles.sm,
                            color: AppColors.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else if (state.pagedVariations.isEmpty)
                Text(
                  'No results.',
                  style: AppFonts.ui(
                    color: AppColors.muted,
                    fontSize: AppTextStyles.sm,
                  ),
                )
              else ...[
                ...state.pagedVariations.map(
                  (v) => Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: AppCard(
                      onTap: () => onEdit(v),
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                        vertical: AppSpacing.sm,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  toProperCase(v.name),
                                  style: AppFonts.ui(
                                    fontSize: AppTextStyles.md,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.primary,
                                  ),
                                ),
                                if (state.usage[v.variationId] != null)
                                  Text(
                                    _usageLine(
                                      state.usage[v.variationId]!,
                                      isExercise: false,
                                    ),
                                    style: AppFonts.ui(
                                      fontSize: AppTextStyles.xs,
                                      color: AppColors.muted,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (state.varTotal > _pageSize)
                  _PaginationBar(
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
String _usageLine(ExerciseUsage u, {required bool isExercise}) =>
    u.lastUsedLabel;

class _PaginationBar extends StatelessWidget {
  const _PaginationBar({
    required this.total,
    required this.page,
    required this.canPrev,
    required this.canNext,
    required this.onPrev,
    required this.onNext,
  });

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
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              // The glass recipe — enabled in accent, disabled stays muted.
              decoration: canPrev
                  ? glassBox(AppColors.accent)
                  : lambdaBox(ContainerTone.ghost, radius: AppRadius.md),
              child: Icon(
                Icons.chevron_left,
                size: 20,
                color: canPrev ? AppColors.accent : AppColors.muted,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Text(
            // Cumulative: everything shown up to this page, not just the
            // rows on the current one.
            '${((page + 1) * _pageSize).clamp(0, total)} of $total',
            style: AppFonts.mono(fontSize: 13, color: AppColors.muted),
          ),
          const SizedBox(width: AppSpacing.md),
          GestureDetector(
            onTap: canNext ? onNext : null,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              // The glass recipe — enabled in accent, disabled stays muted.
              decoration: canNext
                  ? glassBox(AppColors.accent)
                  : lambdaBox(ContainerTone.ghost, radius: AppRadius.md),
              child: Icon(
                Icons.chevron_right,
                size: 20,
                color: canNext ? AppColors.accent : AppColors.muted,
              ),
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
  });

  final TextEditingController controller;
  final ExerciseViewModel viewModel;

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
                Text(
                  'New Exercise',
                  style: AppFonts.ui(
                    fontSize: AppTextStyles.lg,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                LambdaInput(
                  controller: controller,
                  placeholder: 'Exercise name',
                  enabled: !state.isCreatingEx,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.done,
                  maxLength: kMaxExerciseNameLength,
                  onChanged: viewModel.setCreateExName,
                ),
                if (state.createExName.trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  NameLimitCounter(length: state.createExName.trim().length),
                ],
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
  });

  final TextEditingController controller;
  final ExerciseViewModel viewModel;

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
                Text(
                  'New Variation',
                  style: AppFonts.ui(
                    fontSize: AppTextStyles.lg,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                LambdaInput(
                  controller: controller,
                  placeholder: 'Variation name',
                  enabled: !state.isCreatingVar,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.done,
                  maxLength: kMaxExerciseNameLength,
                  onChanged: viewModel.setCreateVarName,
                ),
                if (state.createVarName.trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  NameLimitCounter(length: state.createVarName.trim().length),
                ],
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

// ── Edit Variation Modal ────────────────────────────────────────────────────────

class _EditVariationModal extends StatelessWidget {
  const _EditVariationModal({
    required this.controller,
    required this.viewModel,
    required this.onDelete,
  });

  final TextEditingController controller;
  final ExerciseViewModel viewModel;
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
                      child: Text(
                        'Edit Variation',
                        style: AppFonts.ui(
                          fontSize: AppTextStyles.lg,
                          fontWeight: FontWeight.w800,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                    GlassButton(
                      label: '',
                      icon: Icons.delete_outline,
                      color: AppColors.danger,
                      compact: true,
                      onPressed: () => onDelete(
                        state.editVariation!.variationId,
                        state.editVarName,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                LambdaInput(
                  controller: controller,
                  placeholder: 'Variation name',
                  enabled: !state.isSaving,
                  textCapitalization: TextCapitalization.words,
                  maxLength: kMaxExerciseNameLength,
                  onChanged: viewModel.setEditVarName,
                ),
                if (state.editVarName.trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  NameLimitCounter(length: state.editVarName.trim().length),
                ],
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
                        // Nothing to write until the name differs from the
                        // one being renamed — Cancel is the dismissal.
                        disabled: state.isSaving ||
                            state.editVarName.trim().isEmpty ||
                            state.editVarName.trim() ==
                                state.editVariation!.name,
                        onPressed: () async {
                          final original = state.editVariation!.name;
                          final renamed = state.editVarName.trim() != original;
                          if (renamed) {
                            final ok = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                backgroundColor: AppColors.surface,
                                title: Text(
                                  'Rename "$original"?',
                                  style: AppFonts.ui(
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.primary,
                                  ),
                                ),
                                content: Text(
                                  'This updates the variation name everywhere — all past sessions included.',
                                  style: AppFonts.ui(color: AppColors.muted),
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.of(ctx).pop(false),
                                    child: Text(
                                      'Cancel',
                                      style: AppFonts.ui(
                                        color: AppColors.muted,
                                      ),
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.of(ctx).pop(true),
                                    child: Text(
                                      'Rename',
                                      style: AppFonts.ui(
                                        color: AppColors.accent,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
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
