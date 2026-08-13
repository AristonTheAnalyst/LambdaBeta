import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/styles/app_colors.dart';
import '../../../core/styles/app_fonts.dart';
import '../../../core/styles/app_spacing.dart';
import '../../../core/styles/app_text_styles.dart';
import '../../../shared/widgets/glass_button.dart';
import '../../statistics/view/insights_screen.dart';
import '../viewmodel/exercise_viewmodel.dart';

/// Dedicated per-exercise page: the full Insights screen with the exercise
/// filter locked to this exercise, plus rename / archive actions in the
/// header. Replaces the old name-only edit bottom sheet as the exercise's
/// primary screen.
class ExerciseDetailScreen extends StatefulWidget {
  const ExerciseDetailScreen({
    super.key,
    required this.exerciseId,
    this.exerciseName,
  });

  final String exerciseId;
  final String? exerciseName;

  @override
  State<ExerciseDetailScreen> createState() => _ExerciseDetailScreenState();
}

class _ExerciseDetailScreenState extends State<ExerciseDetailScreen> {
  final _viewModel = ExerciseViewModel();
  String? _name;

  @override
  void initState() {
    super.initState();
    _name = widget.exerciseName;
  }

  @override
  void dispose() {
    _viewModel.dispose();
    super.dispose();
  }

  Future<void> _openEditMenu() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      useRootNavigator: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Text(_name ?? 'Exercise',
                  style: AppFonts.ui(
                      fontSize: AppTextStyles.lg,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primary)),
            ),
            InkWell(
              onTap: () => Navigator.of(ctx).pop('rename'),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg, vertical: AppSpacing.md),
                child: Row(
                  children: [
                    Icon(Icons.edit_outlined, size: 18, color: AppColors.primary),
                    const SizedBox(width: AppSpacing.sm),
                    Text('Rename',
                        style: AppFonts.ui(
                            fontSize: AppTextStyles.md,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primary)),
                  ],
                ),
              ),
            ),
            InkWell(
              onTap: () => Navigator.of(ctx).pop('archive'),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg, vertical: AppSpacing.md),
                child: Row(
                  children: [
                    Icon(Icons.archive_outlined,
                        size: 18, color: AppColors.danger),
                    const SizedBox(width: AppSpacing.sm),
                    Text('Archive',
                        style: AppFonts.ui(
                            fontSize: AppTextStyles.md,
                            fontWeight: FontWeight.w600,
                            color: AppColors.danger)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
          ],
        ),
      ),
    );
    if (action == 'rename') await _rename();
    if (action == 'archive') await _archive();
  }

  Future<void> _rename() async {
    final controller = TextEditingController(text: _name);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Rename exercise',
            style: AppFonts.ui(fontWeight: FontWeight.w800, color: AppColors.primary)),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          style: AppFonts.ui(color: AppColors.primary),
          decoration: InputDecoration(
            hintText: 'Exercise name',
            hintStyle: AppFonts.ui(color: AppColors.muted),
            enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: AppColors.border)),
            focusedBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: AppColors.accent)),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text('Cancel',
                  style: AppFonts.ui(color: AppColors.muted))),
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(controller.text),
              child: Text('Save',
                  style: AppFonts.ui(
                      color: AppColors.accent, fontWeight: FontWeight.w600))),
        ],
      ),
    );
    controller.dispose();
    if (newName == null || newName.trim().isEmpty) return;
    await _viewModel.renameExercise(widget.exerciseId, newName);
    if (mounted) setState(() => _name = newName.trim());
  }

  Future<void> _archive() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Archive exercise',
            style: AppFonts.ui(fontWeight: FontWeight.w800, color: AppColors.danger)),
        content: Text(
            'Archive "${_name ?? 'this exercise'}"? It will disappear from pickers, '
            'but your logged history keeps its name.',
            style: AppFonts.ui(color: AppColors.muted)),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text('Cancel',
                  style: AppFonts.ui(color: AppColors.muted))),
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text('Archive',
                  style: AppFonts.ui(
                      color: AppColors.danger, fontWeight: FontWeight.w600))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _viewModel.deleteExercise(widget.exerciseId);
    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    return InsightsScreen(
      lockedExerciseId: widget.exerciseId,
      lockedExerciseName: _name,
      headerRight: GlassButton(
        label: '',
        icon: Icons.edit_outlined,
        compact: true,
        onPressed: _openEditMenu,
      ),
    );
  }
}
