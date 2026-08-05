import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/styles/app_colors.dart';
import '../../../../core/styles/app_fonts.dart';
import '../../../../core/styles/app_spacing.dart';
import '../../../../core/styles/app_text_styles.dart';
import '../../../../core/utils/workout_format.dart';
import '../../../../data/models/program.dart';
import '../../../../data/models/program_progress.dart';
import '../../../../shared/widgets/app_card.dart';
import '../../../../shared/widgets/glass_button.dart';
import '../../../../shared/widgets/lambda_input.dart';
import '../../../../shared/widgets/segmented_control.dart';
import '../../../../shared/widgets/page_header.dart';
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

  @override
  void initState() {
    super.initState();
    _viewModel.fetchAll();
  }

  @override
  void dispose() {
    _viewModel.dispose();
    _createController.dispose();
    super.dispose();
  }

  void _openCreate() {
    _createController.clear();
    _viewModel.openCreate();
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(builder: (_) => const ProgramWizardScreen()),
    );
  }

  void _confirmArchive(Program p) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Archive Program',
            style: AppFonts.ui(fontWeight: FontWeight.w800, color: AppColors.danger)),
        content: Text(
            'Archive "${toProperCase(p.name)}"? Past workouts logged from it stay intact.',
            style: AppFonts.ui(color: AppColors.muted)),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child:
                  Text('Cancel', style: AppFonts.ui(color: AppColors.muted))),
          TextButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                _viewModel.archiveProgram(p.programId);
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
    final now = DateTime.now();
    final controller = TextEditingController();
    final isCalendar = p.progressionMode == 'calendar';
    var useEndDate = false;
    DateTime? endDate;

    final result = await showDialog<_RunConfig>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: Text('Begin "${toProperCase(p.name)}"',
              style: AppFonts.ui(fontWeight: FontWeight.w800, color: AppColors.primary)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (isCalendar) ...[
                SegmentedControl<bool>(
                  subtle: true,
                  options: const [
                    SegmentOption(label: 'Weeks', value: false),
                    SegmentOption(label: 'End date', value: true),
                  ],
                  value: useEndDate,
                  onChange: (v) => setState(() => useEndDate = v),
                ),
                const SizedBox(height: AppSpacing.md),
              ],
              if (!isCalendar || !useEndDate)
                LambdaInput(
                  controller: controller,
                  label: isCalendar ? 'Number of weeks' : 'Number of sessions',
                  placeholder: isCalendar ? 'e.g. 6' : 'e.g. 12',
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
                      context: ctx,
                      initialDate: DateTime.now().add(const Duration(days: 7)),
                      firstDate: DateTime.now(),
                      lastDate: DateTime(now.year + 5),
                    );
                    if (picked != null) setState(() => endDate = picked);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Text(endDate != null
                        ? '${endDate!.day}/${endDate!.month}/${endDate!.year}'
                        : 'Pick a date…',
                        style: AppFonts.ui(color: endDate != null ? AppColors.primary : AppColors.muted)),
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: Text('Cancel', style: AppFonts.ui(color: AppColors.muted))),
            TextButton(
                onPressed: () {
                  final count = int.tryParse(controller.text.trim());
                  if (isCalendar && useEndDate) {
                    if (endDate == null) return;
                    Navigator.of(ctx).pop(_RunConfig(endDate: endDate));
                  } else {
                    if (count == null || count <= 0) return;
                    Navigator.of(ctx).pop(_RunConfig(count: count));
                  }
                },
                child: Text('Begin',
                    style: AppFonts.ui(color: AppColors.accent, fontWeight: FontWeight.w600))),
          ],
        ),
      ),
    );
    controller.dispose();
    if (result == null || !mounted) return;
    await _viewModel.setCurrentProgram(
      p.programId,
      targetSessions: isCalendar ? null : result.count,
      targetWeeks: (isCalendar && !useEndDate) ? result.count : null,
      endDate: result.endDate,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: ValueListenableBuilder<ProgramLibraryState>(
        valueListenable: _viewModel.state,
        builder: (context, state, _) {
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
                      AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, 0),
                  child: Row(
                    children: [
                      Expanded(
                        child: GlassButton(
                          label: 'New Program',
                          icon: Icons.add,
                          onPressed: _openCreate,
                        ),
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
                        : ListView.separated(
                            padding: const EdgeInsets.all(AppSpacing.lg),
                            itemCount: state.sortedPrograms.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: AppSpacing.md),
                            itemBuilder: (context, i) {
                              final p = state.sortedPrograms[i];
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
                                onArchive: () => _confirmArchive(p),
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
    required this.onArchive,
    this.progress,
  });

  final Program program;
  final bool isCurrent;
  final bool settingCurrent;
  final VoidCallback onOpen;
  final VoidCallback onSetCurrent;
  final VoidCallback onDuplicate;
  final VoidCallback onArchive;

  /// Progress of the current program — shown as a bar only on the current card.
  final ProgramProgress? progress;

  @override
  Widget build(BuildContext context) {
    return SwipeActions(
      actions: [
        SwipeAction(
          icon: Icons.archive_outlined,
          label: 'Archive',
          color: AppColors.danger,
          onTap: onArchive,
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
                              border: Border.all(color: AppColors.accent),
                            ),
                            child: Text('Active',
                                style: AppFonts.ui(
                                    fontSize: 10,
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
              Icon(Icons.chevron_right, size: 16, color: AppColors.muted),
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
                  : progress!.program.progressionMode == 'calendar'
                      ? 'Week ${progress!.weekNumber} of ${progress!.totalWeeks ?? '?'} · ${progress!.remainingLabel}'
                      : '${progress!.workoutsCompletedInCycle}/${progress!.totalWorkoutsInCycle} sessions · ${progress!.remainingLabel}',
              style: AppFonts.mono(fontSize: 9, color: AppColors.muted),
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

/// Result of the "Begin Program" duration-config dialog.
class _RunConfig {
  const _RunConfig({this.count, this.endDate});
  final int? count;
  final DateTime? endDate;
}
