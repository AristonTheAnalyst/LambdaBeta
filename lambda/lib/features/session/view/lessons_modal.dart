import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/styles/app_colors.dart';
import '../../../core/styles/app_fonts.dart';
import '../../../core/styles/app_radius.dart';
import '../../../core/styles/app_spacing.dart';
import '../../../data/models/lesson.dart';
import '../../../shared/widgets/glass_button.dart';
import '../../../shared/widgets/slide_up_modal.dart';
import '../../../shared/widgets/swipe_actions.dart';

/// Bound to a [Listenable] + a handful of callbacks rather than a concrete
/// viewmodel type, so both `SessionViewModel` (a `ChangeNotifier`) and
/// `ProgramDetailViewModel` (a `ValueNotifier<ProgramDetailState>`) can
/// reuse this same modal for the exact same `fact_lesson` data — lessons are
/// per-exercise and cross-session, not tied to either feature.
void showLessonsModal(
  BuildContext context, {
  required Listenable listenable,
  required List<Lesson> Function(String exerciseId) lessonsFor,
  required Future<void> Function(String exerciseId) loadLessonsFor,
  required Future<void> Function(String exerciseId, String text) addLesson,
  required Future<void> Function(String exerciseId, String lessonId) toggleLessonPin,
  required Future<void> Function(String exerciseId, String lessonId) deleteLesson,
  required String exerciseId,
  required String exerciseName,
}) {
  showLambdaModal(
    context,
    fitContent: true,
    keyboardAware: true,
    child: _LessonsModalContent(
      listenable: listenable,
      lessonsFor: lessonsFor,
      loadLessonsFor: loadLessonsFor,
      addLesson: addLesson,
      toggleLessonPin: toggleLessonPin,
      deleteLesson: deleteLesson,
      exerciseId: exerciseId,
      exerciseName: exerciseName,
    ),
  );
}

class _LessonsModalContent extends StatefulWidget {
  const _LessonsModalContent({
    required this.listenable,
    required this.lessonsFor,
    required this.loadLessonsFor,
    required this.addLesson,
    required this.toggleLessonPin,
    required this.deleteLesson,
    required this.exerciseId,
    required this.exerciseName,
  });

  final Listenable listenable;
  final List<Lesson> Function(String exerciseId) lessonsFor;
  final Future<void> Function(String exerciseId) loadLessonsFor;
  final Future<void> Function(String exerciseId, String text) addLesson;
  final Future<void> Function(String exerciseId, String lessonId) toggleLessonPin;
  final Future<void> Function(String exerciseId, String lessonId) deleteLesson;
  final String exerciseId;
  final String exerciseName;

  @override
  State<_LessonsModalContent> createState() => _LessonsModalContentState();
}

class _LessonsModalContentState extends State<_LessonsModalContent> {
  bool _adding = false;
  final _draftCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    widget.loadLessonsFor(widget.exerciseId);
  }

  @override
  void dispose() {
    _draftCtrl.dispose();
    super.dispose();
  }

  void _addLesson() {
    if (_draftCtrl.text.trim().isEmpty) return;
    widget.addLesson(widget.exerciseId, _draftCtrl.text);
    _draftCtrl.clear();
    setState(() => _adding = false);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.listenable,
      builder: (context, _) {
        final lessons = widget.lessonsFor(widget.exerciseId);
        // Pinned first, then newest by datetime (Dart's sort is unstable, so
        // sort by both keys explicitly to preserve chronological order).
        final ordered = [...lessons]..sort((a, b) {
          final pin = (b.pinned ? 1 : 0).compareTo(a.pinned ? 1 : 0);
          return pin != 0 ? pin : b.createdDate.compareTo(a.createdDate);
        });
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl, AppSpacing.xl, AppSpacing.xl, AppSpacing.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(widget.exerciseName.toUpperCase(),
                              style: AppFonts.mono(
                                  fontSize: 9, color: AppColors.muted, letterSpacing: 0.8)),
                          Text('Lessons',
                              style: AppFonts.ui(
                                  fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.primary)),
                        ],
                      ),
                    ),
                    GlassButton(
                        label: 'Add', compact: true, onPressed: () => setState(() => _adding = true)),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                if (_adding) ...[
                  TextField(
                    controller: _draftCtrl,
                    autofocus: true,
                    maxLines: 3,
                    style: AppFonts.ui(fontSize: 14, color: AppColors.primary),
                    decoration: InputDecoration(
                      hintText: 'What did you learn? Cues, breakthroughs, adjustments…',
                      hintStyle: AppFonts.ui(color: AppColors.muted),
                      filled: true,
                      fillColor: AppColors.surfaceHigh,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        borderSide: BorderSide(color: AppColors.accent),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    children: [
                      Expanded(
                          child: GlassButton(label: 'Save Lesson', solid: true, onPressed: _addLesson)),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: GlassButton(
                          label: 'Cancel',
                          color: AppColors.muted,
                          onPressed: () => setState(() {
                            _adding = false;
                            _draftCtrl.clear();
                          }),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                ],
                Flexible(
                  child: ordered.isEmpty && !_adding
                      ? Padding(
                          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
                          child: Center(
                            child: Text('No lessons yet — tap Add to record a cue or breakthrough.',
                                textAlign: TextAlign.center,
                                style: AppFonts.ui(fontSize: 13, color: AppColors.muted)),
                          ),
                        )
                      : ListView.separated(
                          shrinkWrap: true,
                          itemCount: ordered.length,
                          separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
                          itemBuilder: (context, i) {
                            final lesson = ordered[i];
                            return _LessonRow(
                              lesson: lesson,
                              onTogglePin: () =>
                                  widget.toggleLessonPin(widget.exerciseId, lesson.lessonId),
                              onDelete: () =>
                                  widget.deleteLesson(widget.exerciseId, lesson.lessonId),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _LessonRow extends StatelessWidget {
  const _LessonRow({required this.lesson, required this.onTogglePin, required this.onDelete});

  final Lesson lesson;
  final VoidCallback onTogglePin;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return SwipeActions(
      borderRadius: AppRadius.md,
      actions: [
        SwipeAction(
          icon: Icons.delete_outline,
          label: 'Delete',
          color: AppColors.danger,
          onTap: onDelete,
        ),
      ],
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          color: lesson.pinned ? AppColors.accentBg : AppColors.surfaceHigh,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
              color: lesson.pinned ? AppColors.accent.withValues(alpha: 0.3) : AppColors.border),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Pin sits at the leading edge, far from the trailing Delete
            // drawer — a tap on the pin can never land on Delete, and the pin
            // never gets covered when the row slides open.
            GestureDetector(
              onTap: onTogglePin,
              child: Container(
                width: 28,
                height: 28,
                margin: const EdgeInsets.only(right: AppSpacing.sm, top: 1),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: lesson.pinned ? AppColors.accentBg : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                      color: lesson.pinned ? AppColors.accent : AppColors.border),
                ),
                child: Icon(Icons.push_pin,
                    size: 14, color: lesson.pinned ? AppColors.accent : AppColors.muted),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(lesson.text,
                      style: AppFonts.ui(fontSize: 13, color: AppColors.primary)),
                  const SizedBox(height: 4),
                  Text(DateFormat('MMM d · h:mm a').format(lesson.createdDate),
                      style: AppFonts.mono(
                          fontSize: 9,
                          color: lesson.pinned ? AppColors.accent : AppColors.muted)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
