import 'package:flutter/material.dart';

import '../../../core/styles/app_colors.dart';
import '../../../core/styles/app_fonts.dart';
import '../../../core/styles/app_radius.dart';
import '../../../core/styles/app_spacing.dart';
import '../../../core/styles/app_text_styles.dart';
import '../../../core/utils/block_length.dart';
import '../../../core/utils/session_format.dart';
import '../../../data/models/program_block.dart';
import '../../../data/models/program_run.dart';
import '../../../shared/widgets/container_styles.dart';
import '../../../shared/widgets/glass_button.dart';
import '../../../shared/widgets/lambda_input.dart';
import '../../../shared/widgets/slide_up_modal.dart';

/// What the user chose when configuring a run.
///
/// One shape for all four callers — begin from the library, begin from the
/// program, start a block, and edit a running run — because they are the same
/// question ("how long, and what does it run") asked at four moments. The
/// caller decides what to do with the answer; the sheet never writes anything
/// itself.
///
/// A run is order-based by definition — it works through the program's
/// workouts in sequence, counting sessions. Day scheduling (and with it the
/// frequency progression mode and its calendar duration) is retired for now:
/// nothing assigns a workout to a weekday, so there is no schedule to
/// configure.
class RunConfigRequest {
  const RunConfigRequest({this.targetSessions, this.blockId});

  /// How many sessions the run lasts. Null for a block run, whose block owns
  /// the length.
  final int? targetSessions;

  /// The block to run, or null when the run is not under a block — a simple
  /// program's run, or an old run of a blocked program begun before blocks
  /// became the only way in.
  final String? blockId;
}

/// Configures a run — its duration and what it runs.
///
/// This replaces three near-identical dialogs (`_BeginConfigDialog` in the
/// library, `_confirmBeginProgram` and `_editRunConfig` in the detail screen)
/// that had drifted apart in copy and in validation while asking the same
/// question. The fourth caller — starting a block — is where the extraction
/// pays for itself: the block a run follows is decided at the call site and
/// handed here, instead of the "which block" question being threaded through
/// three separate dialogs.
///
/// Stateful so it owns the [TextEditingController] — disposing one right after
/// `showDialog` returns crashes, because the field is still mounted and
/// rebuilding during the pop animation.
Future<RunConfigRequest?> showRunConfigSheet(
  BuildContext context, {
  required String programName,

  /// Overrides the heading. Defaults to `Begin "Program"` for a new run and
  /// `Run config` when [run] is given.
  String? title,

  /// The confirm button's label. Defaults to `Begin`, or `Save` when editing.
  String? actionLabel,

  /// Shown above the controls when configuring the run is itself the
  /// confirmation. Restart is the only caller left: the pause warning is asked
  /// as its own question, on its own dialog, *before* this sheet opens — a
  /// run that steps another one aside has to be agreed to before "how long"
  /// is answered.
  String? warning,

  /// The block this begin will follow — the program's **next** unended block,
  /// or null on a blocked program that has none to run.
  ///
  /// One block, never a list. Blocks are a sequence: a run follows the phase
  /// the program is on, so a picker here would be offering choices the
  /// sequencing rule refuses — and the refusal would arrive as a dead Begin
  /// rather than as a reason. Which block that is comes from [BlockSequence],
  /// the same answer the program screen and the due prompts use.
  ProgramBlock? block,

  /// Whether this program is made of blocks, from `dim_program.uses_blocks`.
  ///
  /// Passed rather than inferred, because "no block to run" cannot tell a
  /// simple program from a blocked one with nothing in it — and those two owe
  /// the user opposite answers: a length to type, versus nothing to begin.
  bool usesBlocks = false,

  /// A simple program's remembered length, which the count field opens on.
  /// Ignored for a blocked program, whose block owns the length.
  int? defaultTargetSessions,

  /// Non-null = editing this run rather than starting one. The sheet then
  /// names the run's own block instead of taking one: the run is already under
  /// way, and repointing it mid-flight would silently change which workouts it
  /// is counting.
  ProgramRun? run,
}) {
  return showLambdaModal<RunConfigRequest>(
    context,
    keyboardAware: true,
    child: SafeArea(
      child: _RunConfigSheet(
        programName: programName,
        title: title ?? (run == null ? null : 'Run config'),
        actionLabel: actionLabel ?? (run == null ? 'Begin' : 'Save'),
        warning: warning,
        block: run == null ? block : null,
        usesBlocks: usesBlocks,
        defaultTargetSessions: defaultTargetSessions,
        run: run,
      ),
    ),
  );
}

class _RunConfigSheet extends StatefulWidget {
  const _RunConfigSheet({
    required this.programName,
    required this.usesBlocks,
    required this.run,
    this.block,
    this.defaultTargetSessions,
    this.title,
    this.actionLabel,
    this.warning,
  });

  final String programName;
  final String? title;
  final String? actionLabel;
  final String? warning;

  /// The next block to run, on a blocked program. Null when the program has
  /// none at all, or while editing a run that is not under one.
  final ProgramBlock? block;
  final bool usesBlocks;
  final int? defaultTargetSessions;
  final ProgramRun? run;

  @override
  State<_RunConfigSheet> createState() => _RunConfigSheetState();
}

class _RunConfigSheetState extends State<_RunConfigSheet> {
  late final TextEditingController _count;

  /// The block this sheet is about: the next one on a blocked begin, or the
  /// run's own while editing.
  ///
  /// Held as an id rather than the object because the editing case has only
  /// the id — the run carries `block_id` and nothing else, and the sheet is
  /// handed no block to look the name up in.
  String? _blockId;

  @override
  void initState() {
    super.initState();
    final run = widget.run;
    _blockId = widget.block?.blockId ?? run?.blockId;
    // The run's own count when one is being edited, else what the program
    // remembers — a simple program should not have to be told its own length
    // again every time it is begun. A block run is never asked: its block owns
    // the length, so the field is not shown.
    final prefill = run?.targetSessions ?? widget.defaultTargetSessions;
    _count = TextEditingController(text: prefill?.toString() ?? '');
  }

  @override
  void dispose() {
    _count.dispose();
    super.dispose();
  }

  /// Whether confirming would write anything.
  ///
  /// A block run always can — the block owns the length, so there is nothing
  /// here to compare. A program run needs a positive count, and when editing,
  /// a count that differs from the run's own: a confirm button that would
  /// write nothing should not look pressable. Cancel is the dismissal.
  bool get _canSubmit {
    if (_blockId != null) return true;
    // Beginning a blocked program without a block is the one thing this sheet
    // must never allow: a blocked program is defined by its blocks, so a run
    // with none has nothing to walk. Editing an already-running one is
    // different — a run that predates the shape rule still has to be fixable.
    if (widget.usesBlocks && widget.run == null) return false;
    final parsed = int.tryParse(_count.text.trim());
    if (parsed == null || parsed <= 0) return false;
    final run = widget.run;
    return run == null || parsed != run.targetSessions;
  }

  void _submit() {
    // A block run carries no length of its own. The block's own targets are
    // what `getProgress` measures it against — `block?.targetSessions ??
    // run.targetSessions` — so anything typed here would be shadowed on the
    // very first read. Not sending it at all is the only honest answer to a
    // duration the user was never asked about.
    if (_blockId != null) {
      Navigator.of(context).pop(RunConfigRequest(blockId: _blockId));
      return;
    }
    // Belt and braces with [_canSubmit]: the button is disabled, but a submit
    // that would start a blockless run of a blocked program must not exist.
    if (widget.usesBlocks && widget.run == null) return;
    final count = int.tryParse(_count.text.trim());
    if (count == null || count <= 0) return;
    Navigator.of(context).pop(RunConfigRequest(targetSessions: count));
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.xl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            widget.title ?? 'Begin "${toProperCase(widget.programName)}"',
            style: AppFonts.ui(
              fontSize: AppTextStyles.lg,
              fontWeight: FontWeight.w800,
              color: AppColors.primary,
            ),
          ),
          if (widget.warning != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              widget.warning!,
              style: AppFonts.ui(
                fontSize: AppTextStyles.sm,
                color: AppColors.muted,
              ),
            ),
          ],
          // A blocked program runs its blocks, so this names the block the run
          // will follow. Named, not picked: blocks are a sequence, so there is
          // exactly one block a begin can mean — the next one — and a picker
          // would be offering choices the sequencing rule refuses.
          if (widget.run == null && widget.usesBlocks) ...[
            const SizedBox(height: AppSpacing.lg),
            _label('Run'),
            const SizedBox(height: AppSpacing.sm),
            if (widget.block == null)
              Text(
                'Add a block to run this program — a blocked program runs its '
                'blocks, and this one has none yet.',
                style: AppFonts.ui(
                  fontSize: AppTextStyles.sm,
                  color: AppColors.muted,
                ),
              )
            else
              _BlockRow(title: widget.block!.name),
          ],
          const SizedBox(height: AppSpacing.lg),
          // A block states its own length, so a block run is never asked for a
          // count — the line below says which length is in force, rather than
          // leaving a duration control that would be overruled the moment the
          // run was read back. The one remaining no-count case is a blocked
          // begin with nothing to run, where the copy above has said why.
          if (_blockId != null) ...[
            _label('Duration'),
            const SizedBox(height: AppSpacing.sm),
            Text(
              // `widget.block` is null here in one case only: editing a run
              // that already follows a block. The editing path passes no
              // block — the run carries just its id, and a run that is under
              // way must not be repointed — so the length is still the
              // block's, and the line says so without naming it.
              widget.block == null
                  ? 'Set by the block this run follows.'
                  : _blockLengthLine(widget.block!),
              style: AppFonts.ui(
                fontSize: AppTextStyles.sm,
                color: AppColors.muted,
              ),
            ),
          ] else if (widget.run != null || !widget.usesBlocks) ...[
            // The count field appears only when the count is the run's own: a
            // simple program's run, or an old run of a blocked program that
            // predates the shape rule and still has to be editable.
            LambdaInput(
              controller: _count,
              label: 'Number of sessions',
              placeholder: 'e.g. 12',
              keyboardType: TextInputType.number,
              required: true,
              // The sheet's default background is a surface ground.
              elevated: true,
              onChanged: (_) => setState(() {}),
            ),
          ],
          const SizedBox(height: AppSpacing.xl),
          GlassButton(
            label: widget.actionLabel ?? 'Begin',
            solid: true,
            disabled: !_canSubmit,
            onPressed: _submit,
          ),
        ],
      ),
    );
  }

  /// The block's own length, in the words the rest of the app uses for it.
  String _blockLengthLine(ProgramBlock b) {
    final phrase = blockLengthPhrase(
      targetWeeks: b.targetWeeks,
      targetDays: b.targetDays,
      targetSessions: b.targetSessions,
    );
    if (phrase != null) return '$phrase, as set on the block.';
    return 'Open-ended — end it by hand when the phase is done.';
  }

  Widget _label(String text) => Text(
        text,
        style: AppFonts.ui(
          fontSize: AppTextStyles.sm,
          fontWeight: FontWeight.w600,
          color: AppColors.primary,
        ),
      );
}

/// The block this run will follow, named.
///
/// Not a control: there is no choice to make, so nothing here looks pressable.
/// The length is said below it, which is why this row carries only the name.
class _BlockRow extends StatelessWidget {
  const _BlockRow({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      decoration: lambdaBox(ContainerTone.ghost, radius: AppRadius.md),
      child: Text(
        toProperCase(title),
        style: AppFonts.ui(
          fontSize: AppTextStyles.sm,
          fontWeight: FontWeight.w600,
          color: AppColors.primary,
        ),
      ),
    );
  }
}
