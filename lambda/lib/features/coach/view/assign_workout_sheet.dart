import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/styles/app_colors.dart';
import '../../../core/styles/app_fonts.dart';
import '../../../core/styles/app_spacing.dart';
import '../../../core/styles/app_text_styles.dart';
import '../../../data/models/planned_session.dart';
import '../../../shared/widgets/container_styles.dart';
import '../../../shared/widgets/glass_button.dart';
import '../../../shared/widgets/lambda_input.dart';
import '../../../shared/widgets/slide_up_modal.dart';
import '../../../shared/widgets/user_name_text.dart';
import '../../friends/viewmodel/friend_profile_viewmodel.dart';

/// The assign sheet (2026-10-26, #24; moved onto the friend profile
/// 2026-10-30): pick one of the coach's own workouts, add a word of context,
/// send. The athlete gets their own copy to accept — the coach's template is
/// never shared.
///
/// Returns true when an offer landed.
Future<bool?> showAssignWorkoutSheet(
  BuildContext context, {
  required FriendProfileViewModel vm,
  required String athleteName,
}) => showLambdaModal<bool>(
  context,
  fitContent: true,
  keyboardAware: true,
  child: _AssignWorkoutSheet(vm: vm, athleteName: athleteName),
);

class _AssignWorkoutSheet extends StatefulWidget {
  const _AssignWorkoutSheet({required this.vm, required this.athleteName});

  final FriendProfileViewModel vm;
  final String athleteName;

  @override
  State<_AssignWorkoutSheet> createState() => _AssignWorkoutSheetState();
}

class _AssignWorkoutSheetState extends State<_AssignWorkoutSheet> {
  final _noteCtrl = TextEditingController();
  List<PlannedSession>? _workouts;
  PlannedSession? _chosen;
  bool _sending = false;
  String? _loadError;
  String? _sendError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loadError = null;
      _workouts = null;
    });
    final workouts = await widget.vm.loadWorkouts();
    if (!mounted) return;
    setState(() {
      _workouts = workouts;
      _loadError = workouts == null
          ? (widget.vm.state.value.error ?? 'Could not load your workouts.')
          : null;
    });
  }

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final chosen = _chosen;
    if (chosen == null || _sending) return;
    setState(() {
      _sending = true;
      _sendError = null;
    });
    final note = _noteCtrl.text.trim();
    final sent = await widget.vm.assign(
      chosen,
      note: note.isEmpty ? null : note,
    );
    if (!mounted) return;
    setState(() {
      _sending = false;
      // A refusal stays in the sheet (the VM's error), so the sheet that
      // caused it is also the one that shows it — and the words are the
      // VM's, not a generic sentence written twice.
      if (!sent) {
        _sendError =
            widget.vm.state.value.error ?? 'Could not send that workout.';
      }
    });
    if (sent) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final workouts = _workouts;
    return SafeArea(
      key: const ValueKey('assign-workout-sheet'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl,
          AppSpacing.xl,
          AppSpacing.xl,
          AppSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Assign a workout',
              style: AppFonts.ui(
                fontSize: AppTextStyles.lg,
                fontWeight: FontWeight.w800,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Pick one of your workouts. '
              '${widget.athleteName} gets their own copy to accept.',
              style: AppFonts.ui(
                fontSize: AppTextStyles.sm,
                height: 1.4,
                color: AppColors.inkSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            if (_loadError != null) ...[
              Text(
                _loadError!,
                style: AppFonts.ui(
                  fontSize: AppTextStyles.sm,
                  color: AppColors.inkSecondary,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              GlassButton(
                label: 'Retry',
                compact: true,
                onPressed: _load,
              ),
            ] else if (workouts == null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
                child: Center(
                  child: CircularProgressIndicator(color: AppColors.accent),
                ),
              )
            else if (workouts.isEmpty)
              Text(
                'You have no workouts yet — build one in the Library first.',
                style: AppFonts.ui(
                  fontSize: AppTextStyles.sm,
                  color: AppColors.inkSecondary,
                ),
              )
            else ...[
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.35,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final workout in workouts) ...[
                        _workoutChoice(workout),
                        const SizedBox(height: AppSpacing.sm),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              LambdaInput(
                controller: _noteCtrl,
                label: 'Note (optional)',
                placeholder: 'Why this one?\nAnything to focus on?',
                elevated: true,
                minLines: 2,
                maxLines: 4,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: AppSpacing.lg),
              if (_sendError != null) ...[
                Text(
                  _sendError!,
                  key: const ValueKey('assign-workout-error'),
                  style: AppFonts.ui(
                    fontSize: AppTextStyles.sm,
                    color: AppColors.inkSecondary,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
              ],
              GlassButton(
                key: const ValueKey('assign-workout-send'),
                label: 'Send workout',
                solid: true,
                color: AppColors.success,
                loading: _sending,
                disabled: _chosen == null,
                onPressed: _send,
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// One selectable workout — the choice recipe (glass fill, accent when
  /// chosen), drawn through [UserNameText] so a 20-character name ellipsizes
  /// instead of overflowing the sheet.
  Widget _workoutChoice(PlannedSession workout) {
    final active = _chosen?.sessionId == workout.sessionId;
    return GestureDetector(
      key: ValueKey('assign-workout-${workout.sessionId}'),
      onTap: () => setState(() => _chosen = workout),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.md,
        ),
        decoration: glassBox(active ? AppColors.accent : AppColors.primary),
        child: Row(
          children: [
            Expanded(
              child: UserNameText(
                workout.name,
                style: AppFonts.ui(
                  fontSize: AppTextStyles.sm,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w600,
                  color: active ? AppColors.accent : AppColors.primary,
                ),
              ),
            ),
            if (active) Icon(LucideIcons.check, size: 16, color: AppColors.accent),
          ],
        ),
      ),
    );
  }
}
