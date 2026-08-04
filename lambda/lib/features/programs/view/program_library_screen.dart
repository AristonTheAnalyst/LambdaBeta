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
import '../../../../shared/widgets/lambda_button.dart';
import '../../../../shared/widgets/lambda_input.dart';
import '../../../../shared/widgets/page_header.dart';
import '../../../../shared/widgets/press_squash.dart';
import '../../../../shared/widgets/slide_up_modal.dart';
import '../viewmodel/program_library_viewmodel.dart';

class ProgramLibraryScreen extends StatefulWidget {
  const ProgramLibraryScreen({super.key});

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
    showLambdaModal(
      context,
      fitContent: true,
      keyboardAware: true,
      child: _CreateProgramModal(
        controller: _createController,
        viewModel: _viewModel,
        onCreated: (id) => context.push('/exercises/programs/$id'),
      ),
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

  Future<void> _confirmSetCurrent(Program p) async {
    final currentId = _viewModel.state.value.currentProgramId;
    final currentProgram = currentId != null && currentId != p.programId
        ? _viewModel.state.value.programs
            .where((x) => x.programId == currentId)
            .firstOrNull
        : null;

    if (currentProgram == null) {
      _viewModel.setCurrentProgram(p.programId);
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Set as current?',
            style: AppFonts.ui(fontWeight: FontWeight.w800, color: AppColors.primary)),
        content: Text(
            'Set "${toProperCase(p.name)}" as current? Your progress on '
            '"${toProperCase(currentProgram.name)}" will reset.',
            style: AppFonts.ui(color: AppColors.muted)),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text('Cancel', style: AppFonts.ui(color: AppColors.muted))),
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text('Set Current',
                  style: AppFonts.ui(color: AppColors.accent, fontWeight: FontWeight.w600))),
        ],
      ),
    );
    if (ok == true && mounted) {
      _viewModel.setCurrentProgram(p.programId);
    }
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
                                    _confirmSetCurrent(p),
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
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PressSquash(
            onTap: onOpen,
            child: Row(
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
                              child: Text('CURRENT',
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
                  : 'Week ${progress!.weekNumber} of ${progress!.totalWeeks ?? '?'} · '
                      '${progress!.workoutsCompletedInCycle}/${progress!.totalWorkoutsInCycle} workouts',
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
                  label: 'Set Current',
                  icon: Icons.play_circle_outline,
                  compact: true,
                  loading: settingCurrent,
                  disabled: settingCurrent,
                  onPressed: onSetCurrent,
                ),
              const Spacer(),
              GlassButton(
                  label: '', icon: Icons.copy, compact: true, onPressed: onDuplicate),
              const SizedBox(width: AppSpacing.sm),
              GlassButton(
                  label: '',
                  icon: Icons.archive_outlined,
                  color: AppColors.danger,
                  compact: true,
                  onPressed: onArchive),
            ],
          ),
        ],
      ),
    );
  }
}

class _CreateProgramModal extends StatelessWidget {
  const _CreateProgramModal({
    required this.controller,
    required this.viewModel,
    required this.onCreated,
  });

  final TextEditingController controller;
  final ProgramLibraryViewModel viewModel;
  final ValueChanged<String> onCreated;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ProgramLibraryState>(
      valueListenable: viewModel.state,
      builder: (context, state, _) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('New Program',
                    style: AppFonts.ui(
                        fontSize: AppTextStyles.lg,
                        fontWeight: FontWeight.w800,
                        color: AppColors.primary)),
                const SizedBox(height: AppSpacing.md),
                LambdaInput(
                  controller: controller,
                  placeholder: 'Program name',
                  enabled: !state.isCreating,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.done,
                  onChanged: viewModel.setCreateName,
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
                          viewModel.closeCreate();
                        },
                        disabled: state.isCreating,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: LambdaButton(
                        label: 'Create',
                        onPressed: () async {
                          final id = await viewModel.submitCreate();
                          if (id != null && context.mounted) {
                            Navigator.of(context, rootNavigator: true).pop();
                            onCreated(id);
                          }
                        },
                        loading: state.isCreating,
                        disabled: state.isCreating,
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
