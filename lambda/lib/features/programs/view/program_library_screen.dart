import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/styles/app_colors.dart';
import '../../../../core/styles/app_fonts.dart';
import '../../../../core/styles/app_radius.dart';
import '../../../shared/widgets/container_styles.dart';
import '../../../../core/styles/app_spacing.dart';
import '../../../../core/styles/app_text_styles.dart';
import '../../../../core/utils/session_format.dart';
import '../../../../data/models/program.dart';
import '../../../../data/models/program_progress.dart';
import '../../../../shared/widgets/app_card.dart';
import '../../../../shared/widgets/archived_sheet.dart';
import '../../../../shared/widgets/glass_button.dart';
import '../../../../shared/widgets/lambda_input.dart';
import '../../../../shared/widgets/segmented_control.dart';
import '../../../../shared/widgets/page_header.dart';
import '../../../../shared/widgets/slide_up_modal.dart';
import '../../../../shared/widgets/swipe_actions.dart';
import 'program_wizard_screen.dart';
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

    if (currentProgram != null) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: Text('Begin Program?',
              style: AppFonts.ui(fontWeight: FontWeight.w800, color: AppColors.primary)),
          content: Text(
              'Begin "${toProperCase(p.name)}"? Your progress on '
              '"${toProperCase(currentProgram.name)}" will reset.',
              style: AppFonts.ui(color: AppColors.muted)),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text('Cancel', style: AppFonts.ui(color: AppColors.muted))),
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: Text('Begin',
                    style: AppFonts.ui(color: AppColors.accent, fontWeight: FontWeight.w600))),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }

    if (!mounted) return;
    await _showBeginConfigModal(p);
  }

  /// Asks for the run's duration config: sequential → number of sessions;
  /// calendar → number of weeks OR an end date.
  Future<void> _showBeginConfigModal(Program p) async {
    final result = await showDialog<_RunConfig>(
      context: context,
      builder: (_) => _BeginConfigDialog(program: p),
    );
    if (result == null || !mounted) return;
    try {
      await _viewModel.setCurrentProgram(
        p.programId,
        progressionMode: result.mode,
        targetSessions: result.mode == 'order' ? result.count : null,
        targetWeeks: (result.mode == 'frequency' && !result.useEndDate)
            ? result.count
            : null,
        endDate: result.endDate,
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
            Text(
              progress!.isFinished
                  ? 'Finished'
                  : progress!.run.progressionMode == 'frequency'
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

/// Result of the "Begin Program" config dialog — progression mode + duration.
class _RunConfig {
  const _RunConfig({
    this.count,
    this.endDate,
    this.useEndDate = false,
    this.mode = 'order',
  });
  final int? count;
  final DateTime? endDate;
  final bool useEndDate;
  final String mode; // 'frequency' | 'order'
}

/// The "Begin Program" duration-config dialog. Stateful so it owns the
/// [TextEditingController] — disposing a controller right after `showDialog`
/// returns crashes because the TextField is still mounted and rebuilding
/// during the pop animation.
class _BeginConfigDialog extends StatefulWidget {
  const _BeginConfigDialog({required this.program});

  final Program program;

  @override
  State<_BeginConfigDialog> createState() => _BeginConfigDialogState();
}

class _BeginConfigDialogState extends State<_BeginConfigDialog> {
  final _controller = TextEditingController();
  bool _useEndDate = false;
  DateTime? _endDate;
  String _mode = 'order';

  /// Frequency runs schedule by days in the week/fortnight; order runs work
  /// through the list. The mode lives on the run, chosen here at run start.
  bool get _isFrequency => _mode == 'frequency';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final count = int.tryParse(_controller.text.trim());
    if (_isFrequency && _useEndDate) {
      final end = _endDate;
      if (end == null) return;
      Navigator.of(context).pop(_RunConfig(
        endDate: end,
        useEndDate: true,
        mode: _mode,
      ));
    } else {
      if (count == null || count <= 0) return;
      Navigator.of(context).pop(_RunConfig(count: count, mode: _mode));
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text('Begin "${toProperCase(widget.program.name)}"',
          style: AppFonts.ui(fontWeight: FontWeight.w800, color: AppColors.primary)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SegmentedControl<String>(
            subtle: true,
            options: const [
              SegmentOption(label: 'Order', value: 'order'),
              SegmentOption(label: 'Frequency', value: 'frequency'),
            ],
            value: _mode,
            onChange: (v) => setState(() => _mode = v),
          ),
          const SizedBox(height: AppSpacing.md),
          if (_isFrequency) ...[
            SegmentedControl<bool>(
              subtle: true,
              options: const [
                SegmentOption(label: 'Weeks', value: false),
                SegmentOption(label: 'End date', value: true),
              ],
              value: _useEndDate,
              onChange: (v) => setState(() => _useEndDate = v),
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          if (!_isFrequency || !_useEndDate)
            LambdaInput(
              controller: _controller,
              label: _isFrequency ? 'Number of weeks' : 'Number of sessions',
              placeholder: _isFrequency ? 'e.g. 6' : 'e.g. 12',
              keyboardType: TextInputType.number,
              required: true,
            )
          else ...[
            Text('End date',
                style: AppFonts.ui(fontSize: AppTextStyles.sm,
                    fontWeight: FontWeight.w600, color: AppColors.primary)),
            const SizedBox(height: 6),
            GestureDetector(
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: DateTime.now().add(const Duration(days: 7)),
                  firstDate: DateTime.now(),
                  lastDate: DateTime(now.year + 5),
                );
                if (picked != null) setState(() => _endDate = picked);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: glassBox(AppColors.primary, radius: 8),
                child: Text(_endDate != null
                    ? '${_endDate!.day}/${_endDate!.month}/${_endDate!.year}'
                    : 'Pick a date…',
                    style: AppFonts.ui(color: _endDate != null ? AppColors.primary : AppColors.muted)),
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Cancel', style: AppFonts.ui(color: AppColors.muted))),
        TextButton(
            onPressed: _submit,
            child: Text('Begin',
                style: AppFonts.ui(color: AppColors.accent, fontWeight: FontWeight.w600))),
      ],
    );
  }
}
