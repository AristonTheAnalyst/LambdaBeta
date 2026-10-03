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

  /// The block to run, or null for the whole program.
  final String? blockId;
}

/// Configures a run — its duration and what it runs.
///
/// This replaces three near-identical dialogs (`_BeginConfigDialog` in the
/// library, `_confirmBeginProgram` and `_editRunConfig` in the detail screen)
/// that had drifted apart in copy and in validation while asking the same
/// question. The fourth caller — starting a block — is where the extraction
/// pays for itself: the block picker drops into one sheet instead of being
/// added to three.
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

  /// Shown above the controls when the run replaces another one — the two
  /// callers that can interrupt a live run word this differently, so it is
  /// passed in rather than invented here.
  String? warning,

  /// The program's active blocks. Empty (the default) hides the picker
  /// entirely, so a blockless program's sheet is what it always was.
  List<ProgramBlock> blocks = const [],

  /// The block selected when the sheet opens.
  String? initialBlockId,

  /// Non-null = editing this run rather than starting one. Hides the block
  /// picker: the run is already under way, and repointing it mid-flight would
  /// silently change which workouts it is counting.
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
        blocks: run == null ? blocks : const [],
        initialBlockId: run == null ? initialBlockId : null,
        run: run,
      ),
    ),
  );
}

class _RunConfigSheet extends StatefulWidget {
  const _RunConfigSheet({
    required this.programName,
    required this.blocks,
    required this.run,
    this.title,
    this.actionLabel,
    this.warning,
    this.initialBlockId,
  });

  final String programName;
  final String? title;
  final String? actionLabel;
  final String? warning;
  final List<ProgramBlock> blocks;
  final String? initialBlockId;
  final ProgramRun? run;

  @override
  State<_RunConfigSheet> createState() => _RunConfigSheetState();
}

class _RunConfigSheetState extends State<_RunConfigSheet> {
  late final TextEditingController _count;
  String? _blockId;

  /// Whether the user has typed into the count field. Until they do, the field
  /// holds whatever the selected block suggests — so switching blocks updates
  /// the suggestion instead of fighting the user's own number.
  bool _countTouched = false;

  ProgramBlock? get _block {
    for (final b in widget.blocks) {
      if (b.blockId == _blockId) return b;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    final run = widget.run;
    _blockId = widget.initialBlockId ?? run?.blockId;
    final prefill = run?.targetSessions ?? _suggestedCount();
    _count = TextEditingController(text: prefill?.toString() ?? '');
    _countTouched = run != null;
  }

  @override
  void dispose() {
    _count.dispose();
    super.dispose();
  }

  /// The session count a block declares for itself, so a block run's field
  /// opens on a sensible number.
  int? _suggestedCount() => _block?.targetSessions;

  void _selectBlock(String? blockId) {
    setState(() {
      _blockId = blockId;
      if (!_countTouched) _count.text = _suggestedCount()?.toString() ?? '';
    });
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
          if (widget.blocks.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.lg),
            _label('Run'),
            const SizedBox(height: AppSpacing.sm),
            _BlockOption(
              title: 'Whole program',
              subtitle: widget.blocks.length == 1
                  ? 'the one block, in sequence'
                  : 'all ${widget.blocks.length} blocks, in sequence',
              selected: _blockId == null,
              onTap: () => _selectBlock(null),
            ),
            for (var i = 0; i < widget.blocks.length; i++) ...[
              const SizedBox(height: AppSpacing.sm),
              _BlockOption(
                title: widget.blocks[i].name,
                subtitle: _blockSubtitle(widget.blocks[i], i),
                selected: _blockId == widget.blocks[i].blockId,
                onTap: () => _selectBlock(widget.blocks[i].blockId),
              ),
            ],
          ],
          const SizedBox(height: AppSpacing.lg),
          // A block states its own length, so there is nothing to ask for here.
          // The line below says which length is in force rather than leaving a
          // duration control that would be overruled the moment the run was
          // read back.
          if (_blockId != null) ...[
            _label('Duration'),
            const SizedBox(height: AppSpacing.sm),
            Text(
              // `_block` is null here in one case only: editing a run that
              // already follows a block, where the picker is hidden and the
              // sheet was handed no blocks to look the name up in. The length
              // is still the block's, so it says so without naming it.
              _block == null
                  ? 'Set by the block this run follows.'
                  : _blockLengthLine(_block!),
              style: AppFonts.ui(
                fontSize: AppTextStyles.sm,
                color: AppColors.muted,
              ),
            ),
          ] else
            LambdaInput(
              controller: _count,
              label: 'Number of sessions',
              placeholder: 'e.g. 12',
              keyboardType: TextInputType.number,
              required: true,
              onChanged: (_) => _countTouched = true,
            ),
          const SizedBox(height: AppSpacing.xl),
          GlassButton(
            label: widget.actionLabel ?? 'Begin',
            solid: true,
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

  /// The block's length, or its position when it declares none.
  String _blockSubtitle(ProgramBlock b, int index) =>
      blockLengthPhrase(
        targetWeeks: b.targetWeeks,
        targetDays: b.targetDays,
        targetSessions: b.targetSessions,
      ) ??
      'Block ${index + 1}';

  Widget _label(String text) => Text(
        text,
        style: AppFonts.ui(
          fontSize: AppTextStyles.sm,
          fontWeight: FontWeight.w600,
          color: AppColors.primary,
        ),
      );
}

/// One row of the run-target picker. Selection is a border plus a check rather
/// than a fill, so the chosen one reads at a glance without the unselected rows
/// looking disabled.
class _BlockOption extends StatelessWidget {
  const _BlockOption({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        decoration: selected
            ? lambdaBox(ContainerTone.accent, radius: AppRadius.md)
            : lambdaBox(ContainerTone.ghost, radius: AppRadius.md),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    toProperCase(title),
                    style: AppFonts.ui(
                      fontSize: AppTextStyles.sm,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: AppFonts.mono(
                      fontSize: AppTextStyles.xs,
                      color: AppColors.muted,
                    ),
                  ),
                ],
              ),
            ),
            if (selected)
              Icon(Icons.check, size: 18, color: AppColors.accentText),
          ],
        ),
      ),
    );
  }
}
