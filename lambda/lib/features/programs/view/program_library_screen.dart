import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/styles/app_colors.dart';
import '../../../../core/styles/app_fonts.dart';
import '../../../../core/styles/app_radius.dart';
import '../../../../core/styles/app_spacing.dart';
import '../../../../core/styles/app_text_styles.dart';
import '../../../../core/utils/session_format.dart';
import '../../../../data/models/program.dart';
import '../../../../data/models/program_block.dart';
import '../../../../data/models/program_history.dart';
import '../../../../data/models/program_progress.dart';
import '../../../../shared/widgets/app_card.dart';
import '../../../../shared/widgets/archived_sheet.dart';
import '../../../../shared/widgets/glass_button.dart';
import '../../../../shared/widgets/page_header.dart';
import '../../../../shared/widgets/slide_up_modal.dart';
import '../../../../shared/widgets/swipe_actions.dart';
import 'program_wizard_screen.dart';
import 'run_config_sheet.dart';
import '../viewmodel/program_library_viewmodel.dart';

class ProgramLibraryScreen extends StatefulWidget {
  const ProgramLibraryScreen({super.key, this.showHeader = true});

  /// When embedded in a tab (Exercises hub), render content only — the hub
  /// owns the header, so a nested PageHeader would add empty top space and a
  /// dead back button.
  final bool showHeader;

  @override
  State<ProgramLibraryScreen> createState() => _ProgramLibraryScreenState();
}

class _ProgramLibraryScreenState extends State<ProgramLibraryScreen> {
  final _viewModel = ProgramLibraryViewModel();
  final _createController = TextEditingController();
  final _searchController = TextEditingController();
  bool _needsRefresh = false;
  String _query = '';
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    // Capture the router once — dispose() can't look up ancestors.
    _router = GoRouter.of(context);
    _router.routerDelegate.addListener(_onRouteChange);
    _searchController.addListener(
      () => setState(() => _query = _searchController.text),
    );
    _viewModel.fetchAll();
  }

  void _onRouteChange() {
    if (!mounted) return;
    // Only refresh when we're on a screen that shows programs.
    final loc = GoRouterState.of(context).uri.toString();
    if (loc == '/exercises' || loc == '/session') {
      setState(() => _needsRefresh = true);
    }
  }

  @override
  void dispose() {
    _router.routerDelegate.removeListener(_onRouteChange);
    _viewModel.dispose();
    _createController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _openCreate() {
    _createController.clear();
    _viewModel.openCreate();
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(builder: (_) => const ProgramWizardScreen()),
    );
  }

  void _openArchived() {
    showLambdaModal(
      context,
      fitContent: true,
      child: ArchivedSheet(
        title: 'Archived Programs',
        emptyText: 'No archived programs.',
        fetch: () async => [
          for (final pr in await _viewModel.fetchArchivedPrograms())
            (id: pr.programId, name: pr.name),
        ],
        onRestore: (id) => _viewModel.reactivateProgram(id),
      ),
    );
  }

  /// Programs can never be fully deleted — runs FK-reference them — so the
  /// dialog says "Archive" and the copy explains it.
  void _confirmDelete(Program p) {
    final isCurrent = _viewModel.state.value.currentProgramId == p.programId;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Archive Program',
            style: AppFonts.ui(fontWeight: FontWeight.w800, color: AppColors.danger)),
        content: Text(
            isCurrent
                ? '${toProperCase(p.name)} is your active program. '
                    'Archiving it will also end your current run. '
                    'Sessions logged from it stay intact.'
                : 'Archive "${toProperCase(p.name)}"? It will disappear from '
                    'this list, but the sessions logged from it stay intact.',
            style: AppFonts.ui(color: AppColors.muted)),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child:
                  Text('Cancel', style: AppFonts.ui(color: AppColors.muted))),
          TextButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                _viewModel.deleteProgram(p.programId);
              },
              child: Text('Archive',
                  style: AppFonts.ui(
                      color: AppColors.danger, fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }

  Future<void> _beginProgram(Program p) async {
    final currentId = _viewModel.state.value.currentProgramId;
    final currentProgram = currentId != null && currentId != p.programId
        ? _viewModel.state.value.programs
            .where((x) => x.programId == currentId)
            .firstOrNull
        : null;

    // The blocks have to be read before the sheet opens so it can offer them —
    // and starting a block is the reason this screen needs them at all.
    List<ProgramBlock> blocks = const [];
    try {
      blocks = await _viewModel.blocksFor(p.programId);
    } catch (_) {
      // Offline or unreadable: the sheet simply has no blocks to offer, and
      // beginning the whole program still works.
    }
    if (!mounted) return;

    // Beginning a program while another is running is a destructive act — the
    // other run ends here — so it is stated before the config, not after.
    final result = await showRunConfigSheet(
      context,
      programName: p.name,
      blocks: blocks,
      warning: currentProgram == null
          ? null
          : 'This resets your progress on '
              '"${toProperCase(currentProgram.name)}".',
    );
    if (result == null || !mounted) return;
    try {
      await _viewModel.setCurrentProgram(
        p.programId,
        progressionMode: result.progressionMode,
        targetSessions: result.targetSessions,
        targetWeeks: result.targetWeeks,
        endDate: result.endDate,
        blockId: result.blockId,
      );
    } catch (_) {
      // Error already set on _viewModel.state.error — the error bar and
      // SnackBar in the build method handle display.
    }
    if (!mounted) return;
    final error = _viewModel.state.value.error;
    if (error != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error),
          backgroundColor: AppColors.danger,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_needsRefresh) {
      _needsRefresh = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _viewModel.fetchAll();
      });
    }
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: ValueListenableBuilder<ProgramLibraryState>(
        valueListenable: _viewModel.state,
        builder: (context, state, _) {
          final programs = state.sortedPrograms
              .where((p) => p.name.toLowerCase().contains(_query.toLowerCase()))
              .toList();
          return Column(
            children: [
              if (widget.showHeader)
                PageHeader(
                  title: 'Programs',
                  left: GestureDetector(
                    onTap: () => context.pop(),
                    child: Icon(Icons.arrow_back_ios_new,
                        size: 18, color: AppColors.accent),
                  ),
                  right: GlassButton(
                      label: '', icon: Icons.add, onPressed: _openCreate, compact: true),
                ),
              if (!widget.showHeader)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, 0),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _searchController,
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
                              borderRadius:
                                  BorderRadius.circular(AppRadius.md),
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
                        onPressed: _openCreate,
                        compact: true,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      GlassButton(
                        label: '',
                        icon: Icons.archive_outlined,
                        onPressed: _openArchived,
                        compact: true,
                      ),
                    ],
                  ),
                ),
              if (state.error != null)
                Container(
                  width: double.infinity,
                  color: AppColors.dangerBg,
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
                  child: Text(state.error!,
                      style: AppFonts.ui(
                          color: AppColors.danger, fontSize: AppTextStyles.sm)),
                ),
              Expanded(
                child: state.isLoading
                    ? Center(
                        child: CircularProgressIndicator(color: AppColors.accent))
                    : state.programs.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text('No programs yet',
                                    style: AppFonts.ui(
                                        fontSize: AppTextStyles.md,
                                        fontWeight: FontWeight.w800,
                                        color: AppColors.primary)),
                                const SizedBox(height: AppSpacing.sm),
                                Text('Tap + to plan your first program.',
                                    style: AppFonts.ui(
                                        fontSize: AppTextStyles.sm,
                                        color: AppColors.muted)),
                              ],
                            ),
                          )
                        : programs.isEmpty
                            ? Center(
                                child: Text(
                                  'No matches for "$_query".',
                                  style: AppFonts.ui(
                                    fontSize: AppTextStyles.sm,
                                    color: AppColors.muted,
                                  ),
                                ),
                              )
                            : ListView.separated(
                            padding: const EdgeInsets.all(AppSpacing.lg),
                            itemCount: programs.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: AppSpacing.md),
                            itemBuilder: (context, i) {
                              final p = programs[i];
                              final isCurrent = p.programId == state.currentProgramId;
                              final settingCurrent =
                                  state.settingCurrentId == p.programId;
                              return _ProgramCard(
                                program: p,
                                isCurrent: isCurrent,
                                settingCurrent: settingCurrent,
                                progress: isCurrent ? state.currentProgress : null,
                                due: state.dueFor(p.programId),
                                onOpen: () =>
                                    context.push('/exercises/programs/${p.programId}'),
                                onSetCurrent: () =>
                                    _beginProgram(p),
                                onDuplicate: () =>
                                    _viewModel.duplicateProgram(p.programId),
                                onDelete: () => _confirmDelete(p),
                              );
                            },
                          ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ProgramCard extends StatelessWidget {
  const _ProgramCard({
    required this.program,
    required this.isCurrent,
    required this.settingCurrent,
    required this.onOpen,
    required this.onSetCurrent,
    required this.onDuplicate,
    required this.onDelete,
    this.progress,
    this.due,
  });

  final Program program;
  final bool isCurrent;
  final bool settingCurrent;
  final VoidCallback onOpen;
  final VoidCallback onSetCurrent;
  final VoidCallback onDuplicate;
  final VoidCallback onDelete;

  /// Progress of the current program — shown as a bar only on the current card.
  final ProgramProgress? progress;

  /// Something waiting on this program. The badge opens the program rather
  /// than acting here: a review needs the achievements panel and the proposal
  /// in front of it, and neither belongs on a library card.
  final DueItem? due;

  @override
  Widget build(BuildContext context) {
    return SwipeActions(
      actions: [
        SwipeAction(
          icon: Icons.copy_rounded,
          label: 'Duplicate',
          color: AppColors.accent,
          onTap: onDuplicate,
        ),
        SwipeAction(
          icon: Icons.delete_outline,
          label: 'Delete',
          color: AppColors.danger,
          onTap: onDelete,
        ),
      ],
      child: AppCard(
      onTap: onOpen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(toProperCase(program.name),
                              style: AppFonts.ui(
                                  fontSize: AppTextStyles.md,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.primary),
                              overflow: TextOverflow.ellipsis),
                        ),
                        if (isCurrent) ...[
                          const SizedBox(width: AppSpacing.xs),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.accentBg,
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: AppColors.accent.withValues(
                                  alpha: 0.35,
                                ),
                              ),
                            ),
                            child: Text('Active',
                                style: AppFonts.ui(
                                    fontSize: 14,
                                    letterSpacing: 0.5,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.accent)),
                          ),
                        ],
                        if (due != null) ...[
                          const SizedBox(width: AppSpacing.xs),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.accentBg,
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: AppColors.accent.withValues(
                                  alpha: 0.35,
                                ),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.flag_outlined,
                                    size: 12, color: AppColors.accent),
                                const SizedBox(width: 4),
                                Text(due!.label,
                                    style: AppFonts.ui(
                                        fontSize: 14,
                                        letterSpacing: 0.5,
                                        fontWeight: FontWeight.w800,
                                        color: AppColors.accent)),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (program.description?.isNotEmpty == true) ...[
                      const SizedBox(height: 2),
                      Text(program.description!,
                          style: AppFonts.ui(
                              fontSize: AppTextStyles.sm,
                              color: AppColors.muted),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (progress != null) ...[
            const SizedBox(height: AppSpacing.sm),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: progress!.progress,
                minHeight: 6,
                backgroundColor: AppColors.surfaceHigh,
                valueColor: AlwaysStoppedAnimation<Color>(AppColors.accent),
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            // A block run's numbers are already block-relative, so the only
            // thing this line has to add is which block they belong to.
            if (progress!.blockLabel != null)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xs),
                child: Text(
                  progress!.blockLabel!,
                  style: AppFonts.ui(
                    fontSize: AppTextStyles.sm,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                ),
              ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              // "Ready to end", not "Finished": the length is met, and the run
              // is still current until the user says otherwise. Saying
              // "Finished" over a row that still offers to continue is the
              // exact confusion this rename exists to remove.
              progress!.isLengthReached
                  ? 'Ready to end'
                  : !progress!.boundedBySessions
                      ? 'Week ${progress!.weekNumber} of ${progress!.totalWeeks ?? '?'} · ${progress!.remainingLabel}'
                      : '${progress!.workoutsCompletedInCycle}/${progress!.totalWorkoutsInCycle} sessions · ${progress!.remainingLabel}',
              style: AppFonts.mono(fontSize: 13, color: AppColors.muted),
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          Divider(color: AppColors.border, height: 1),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              if (!isCurrent)
                GlassButton(
                  label: 'Begin Program',
                  icon: Icons.play_circle_outline,
                  compact: true,
                  loading: settingCurrent,
                  disabled: settingCurrent,
                  onPressed: onSetCurrent,
                ),
              const Spacer(),
              GlassButton(
                  label: '', icon: Icons.copy, compact: true, onPressed: onDuplicate),
            ],
          ),
        ],
      ),
      ),
    );
  }
}
