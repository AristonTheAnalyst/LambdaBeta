import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/styles/app_colors.dart';
import '../../../core/styles/app_fonts.dart';
import '../../../core/styles/app_radius.dart';
import '../../../core/styles/app_spacing.dart';
import '../../../core/styles/app_text_styles.dart';
import '../../../core/utils/session_format.dart';
import '../../../data/models/program.dart';
import '../../../data/models/program_block.dart';
import '../../../data/models/program_history.dart';
import '../../../data/models/program_progress.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/archived_sheet.dart';
import '../../../shared/widgets/glass_button.dart';
import '../../../shared/widgets/page_header.dart';
import '../../../shared/widgets/slide_up_modal.dart';
import '../../../shared/widgets/status_chip.dart';
import '../../../shared/widgets/swipe_actions.dart';
import 'run_confirm_dialog.dart';
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
    _searchController.dispose();
    super.dispose();
  }

  /// The only way a program is created — the wizard asks for the shape first,
  /// which is why nothing here creates one directly.
  ///
  /// Reloads on pop: the wizard creates its program on the name step, so a
  /// wizard that is backed out of half-way still made one, and the list behind
  /// it has to show what is really there.
  Future<void> _openCreate() async {
    await Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(builder: (_) => const ProgramWizardScreen()),
    );
    if (mounted) await _viewModel.fetchAll();
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
        onDelete: _confirmHardDelete,
      ),
    );
  }

  /// The archived sheet's bin. Unlike [_confirmDelete] there is no undo, so it
  /// counts what the delete would unlink first — the runs go with the program,
  /// and sessions logged under them keep every set but lose the run they
  /// belonged to.
  Future<void> _confirmHardDelete(({String id, String name}) item) async {
    final sessions = await _viewModel.programSessionCount(item.id);
    if (!mounted) return;
    final name = toProperCase(item.name);
    final consequence = sessions == 0
        ? "This can't be undone."
        : '$sessions logged ${sessions == 1 ? "session stays" : "sessions stay"}'
            ' in Training Logs, unlinked from the run.';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Delete Program',
            style: AppFonts.ui(
                fontWeight: FontWeight.w800, color: AppColors.danger)),
        content: Text(
            'Delete "$name" permanently? Its runs and revision history go '
            'with it. $consequence',
            style: AppFonts.ui(color: AppColors.muted)),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child:
                  Text('Cancel', style: AppFonts.ui(color: AppColors.muted))),
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text('Delete',
                  style: AppFonts.ui(
                      color: AppColors.danger, fontWeight: FontWeight.w600))),
        ],
      ),
    );
    if (ok == true) await _viewModel.hardDeleteProgram(item.id);
  }

  /// The card's one-tap archive. This one can't delete for good: a program has
  /// to be archived before the bin in the archived sheet will take it, and the
  /// copy says "Archive" because that is all this does.
  void _confirmDelete(Program p) {
    final state = _viewModel.state.value;
    final isCurrent = state.currentProgramId == p.programId;
    final isPaused = !isCurrent && state.isPaused(p.programId);
    // Both live runs are ended here, and both are recorded. Saying which one it
    // is matters: "your current run" over a program that is not running would
    // describe an archive that is about to do nothing.
    final runNote = isCurrent
        ? 'Archiving it will also end your current run.'
        : isPaused
            ? 'Archiving it will also end its paused run.'
            : null;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Archive Program',
            style: AppFonts.ui(fontWeight: FontWeight.w800, color: AppColors.danger)),
        content: Text(
            runNote == null
                ? 'Archive "${toProperCase(p.name)}"? It will disappear from '
                    'this list, but the sessions logged from it stay intact.'
                : '${toProperCase(p.name)} is your ${isCurrent ? 'active' : 'paused'} program. '
                    '$runNote Sessions logged from it stay intact.',
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
    // The next block has to be read before the sheet opens so it can name it —
    // and starting a block is the reason this screen reads blocks at all.
    ProgramBlock? block;
    try {
      block = await _viewModel.nextBlockFor(p.programId);
    } catch (_) {
      // Unreadable. There is no fallback worth inventing: a blocked program
      // runs a block and this read found none, so the sheet says exactly that
      // rather than beginning a run with nothing to follow.
    }
    if (!mounted) return;

    // The question comes first — before the config, because it is the decision;
    // "how long" is a detail of an act the user has already chosen. Asked every
    // time, not only when another program is running: beginning changes which
    // program you are on, and a gate that is only sometimes there is one the
    // user has to guess at. The state is read *after* the block fetch above so
    // the question is asked against what is true now.
    final state = _viewModel.state.value;
    final displacedName = state.displacedProgramName(p.programId);
    final ok = await confirmStartRun(
      context,
      entry: RunEntry.begin,
      programName: p.name,
      displacesCurrentRun: state.displacesCurrentRun(p.programId),
      displacedName: displacedName,
      otherRunPaused: state.otherRunPaused(p.programId),
    );
    if (!ok || !mounted) return;

    final result = await showRunConfigSheet(
      context,
      programName: p.name,
      block: block,
      usesBlocks: p.usesBlocks,
      defaultTargetSessions: p.defaultTargetSessions,
    );
    if (result == null || !mounted) return;
    try {
      await _viewModel.setCurrentProgram(
        p.programId,
        targetSessions: result.targetSessions,
        blockId: result.blockId,
      );
    } catch (_) {
      // Error already set on _viewModel.state.error — the error bar and
      // SnackBar in the build method handle display.
    }
    if (!mounted) return;
    final error = _viewModel.state.value.error;
    if (error != null && context.mounted) {
      _showError(error);
    } else if (displacedName != null && context.mounted) {
      // What just happened to the run you left, said once and non-blockingly.
      // This is the anti-hopping rule's whole promise — nothing was lost, and
      // the way back is one tap — so it is said plainly instead of being left
      // for the user to discover. Only when the program could be named: the
      // confirmation has already covered the case where it could not, and a
      // sentence about "another program" is not worth a banner.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Lambda paused "${toProperCase(displacedName)}" — pick it '
            'back up any time.',
            style: AppFonts.ui(fontSize: AppTextStyles.sm),
          ),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  /// Picks a paused run back up, straight from its card.
  ///
  /// No config sheet: the run already has a config, and it is the whole point
  /// of pausing that it survives. This is the shortest path back into a program
  /// — one tap from the list you were already looking at — which is what makes
  /// "stop program hopping" a rule a user can live with rather than a wall.
  ///
  /// There is no sheet here to carry a warning, and a resume steps the current
  /// run aside exactly as a begin does — so it asks the same question, in the
  /// same words, and asks it every time for the same reason.
  Future<void> _resumeProgram(Program p) async {
    final state = _viewModel.state.value;
    final ok = await confirmStartRun(
      context,
      entry: RunEntry.resume,
      programName: p.name,
      displacesCurrentRun: state.displacesCurrentRun(p.programId),
      displacedName: state.displacedProgramName(p.programId),
      otherRunPaused: state.otherRunPaused(p.programId),
    );
    if (!ok || !mounted) return;
    await _viewModel.resumeProgram(p.programId);
    if (!mounted) return;
    final error = _viewModel.state.value.error;
    if (error != null) _showError(error);
  }

  void _showError(String error) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(error),
        backgroundColor: AppColors.danger,
        behavior: SnackBarBehavior.floating,
      ),
    );
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
              // Archiving a program ends whatever run it had open — current or
              // paused; when that run's closing record fails to write, this is
              // the only place it is ever said.
              if (state.historyWarning != null)
                Container(
                  width: double.infinity,
                  color: AppColors.dangerBg,
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
                  child: Text(state.historyWarning!,
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
                                // Never both: a run that is current is not
                                // paused, and the card must not have to decide
                                // which badge wins.
                                isPaused: !isCurrent && state.isPaused(p.programId),
                                settingCurrent: settingCurrent,
                                // A current or paused program is not asking to
                                // be begun, so the shape rule has nothing to
                                // say about it.
                                nothingToRun: !isCurrent &&
                                    !state.isPaused(p.programId) &&
                                    state.hasNothingToRun(p.programId),
                                progress: isCurrent ? state.currentProgress : null,
                                due: state.dueFor(p.programId),
                                onOpen: () =>
                                    context.push('/exercises/programs/${p.programId}'),
                                onSetCurrent: () =>
                                    _beginProgram(p),
                                onResume: () => _resumeProgram(p),
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
    required this.isPaused,
    required this.settingCurrent,
    required this.nothingToRun,
    required this.onOpen,
    required this.onSetCurrent,
    required this.onResume,
    required this.onDuplicate,
    required this.onDelete,
    this.progress,
    this.due,
  });

  final Program program;
  final bool isCurrent;

  /// A run of this program was stepped away from — open, resumable, not
  /// running. Badged, and its card action becomes Resume instead of Begin:
  /// there is a run to return to, so beginning a new one is not the offer.
  final bool isPaused;
  final bool settingCurrent;

  /// A blocked program with no blocks: there is nothing for a run to follow.
  /// Begin greys out and the card says why, rather than offering an act the
  /// sheet would then refuse.
  final bool nothingToRun;
  final VoidCallback onOpen;
  final VoidCallback onSetCurrent;
  final VoidCallback onResume;
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
                          const StatusChip(label: 'Active'),
                        ],
                        if (isPaused) ...[
                          const SizedBox(width: AppSpacing.xs),
                          const StatusChip(label: 'Paused', muted: true),
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
          if (nothingToRun) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Add a block to run this program.',
              style: AppFonts.ui(
                fontSize: AppTextStyles.sm,
                color: AppColors.muted,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          Divider(color: AppColors.border, height: 1),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              // Resume before Begin: a paused program already has a run and a
              // config, so the shortest path back to it is the one this card
              // should offer. Beginning a fresh attempt over the top of a
              // paused one is restarting, which lives on the program screen
              // where its consequences can be spelled out.
              if (isPaused)
                GlassButton(
                  label: 'Resume',
                  icon: Icons.play_circle_outline,
                  compact: true,
                  loading: settingCurrent,
                  disabled: settingCurrent,
                  onPressed: onResume,
                )
              else if (!isCurrent)
                GlassButton(
                  label: 'Begin Program',
                  icon: Icons.play_circle_outline,
                  compact: true,
                  loading: settingCurrent,
                  disabled: settingCurrent || nothingToRun,
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
