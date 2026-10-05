import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/styles/app_colors.dart';
import '../../../core/styles/app_fonts.dart';
import '../../../core/styles/app_radius.dart';
import '../../../core/styles/app_spacing.dart';
import '../../../data/models/lesson.dart';
import '../../../shared/widgets/glass_button.dart';
import '../../../shared/widgets/container_styles.dart';
import '../../../shared/widgets/slide_up_modal.dart';
import '../../../shared/widgets/swipe_actions.dart';

/// Bound to a [Listenable] + a handful of callbacks rather than a concrete
/// viewmodel type, so both `SessionViewModel` (a `ChangeNotifier`) and
/// `WorkoutEditorViewModel` (a `ValueNotifier<WorkoutEditorState>`) can
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
  required Future<void> Function(String exerciseId, String lessonId, String text)
      updateLesson,
  required String exerciseId,
  required String exerciseName,

  /// When non-null (the live session's id), lessons created in that session
  /// get a 'NEW' badge.
  String? sessionId,
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
      updateLesson: updateLesson,
      exerciseId: exerciseId,
      exerciseName: exerciseName,
      sessionId: sessionId,
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
    required this.updateLesson,
    required this.exerciseId,
    required this.exerciseName,
    this.sessionId,
  });

  final Listenable listenable;
  final List<Lesson> Function(String exerciseId) lessonsFor;
  final Future<void> Function(String exerciseId) loadLessonsFor;
  final Future<void> Function(String exerciseId, String text) addLesson;
  final Future<void> Function(String exerciseId, String lessonId) toggleLessonPin;
  final Future<void> Function(String exerciseId, String lessonId) deleteLesson;
  final Future<void> Function(String exerciseId, String lessonId, String text)
      updateLesson;
  final String exerciseId;
  final String exerciseName;
  final String? sessionId;

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
    // The Save Lesson button draws its enabled state from the draft, so the
    // modal has to rebuild as it is typed into.
    _draftCtrl.addListener(_onDraftChanged);
  }

  @override
  void dispose() {
    _draftCtrl.removeListener(_onDraftChanged);
    _draftCtrl.dispose();
    super.dispose();
  }

  void _onDraftChanged() => setState(() {});

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
          child: SizedBox(
            // Fixed half-screen sheet: small lesson counts don't inflate it
            // and the empty state doesn't collapse it to full screen — the
            // list scrolls within this height.
            height: MediaQuery.of(context).size.height * 0.5,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.xl, AppSpacing.xl, AppSpacing.xl, AppSpacing.lg),
              child: Column(
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
                                  fontSize: 13, color: AppColors.muted, letterSpacing: 0.8)),
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
                        borderSide: BorderSide(color: AppColors.primary),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    children: [
                      Expanded(
                        child: GlassButton(
                          label: 'Save Lesson',
                          solid: true,
                          // Nothing to save until something is typed.
                          disabled: _draftCtrl.text.trim().isEmpty,
                          onPressed: _addLesson,
                        ),
                      ),
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
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
                            child: Text('No lessons yet — tap Add to record a cue or breakthrough.',
                                textAlign: TextAlign.center,
                                style: AppFonts.ui(fontSize: 13, color: AppColors.muted)),
                          ),
                        )
                      : ListView.separated(
                          itemCount: ordered.length,
                          separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
                          itemBuilder: (context, i) {
                            final lesson = ordered[i];
                            return _LessonRow(
                              lesson: lesson,
                              isNew: widget.sessionId != null &&
                                  lesson.sessionId == widget.sessionId,
                              onTogglePin: () =>
                                  widget.toggleLessonPin(widget.exerciseId, lesson.lessonId),
                              onDelete: () =>
                                  widget.deleteLesson(widget.exerciseId, lesson.lessonId),
                              onUpdateText: (text) => widget.updateLesson(
                                  widget.exerciseId, lesson.lessonId, text),
                            );
                          },
                        ),
                ),
              ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _LessonRow extends StatefulWidget {
  const _LessonRow({
    required this.lesson,
    required this.isNew,
    required this.onTogglePin,
    required this.onDelete,
    required this.onUpdateText,
  });

  final Lesson lesson;

  /// True when this lesson was created in the live session — shows a 'NEW'
  /// badge next to the timestamp.
  final bool isNew;
  final VoidCallback onTogglePin;
  final VoidCallback onDelete;
  final void Function(String text) onUpdateText;

  @override
  State<_LessonRow> createState() => _LessonRowState();
}

class _LessonRowState extends State<_LessonRow> {
  bool _editing = false;
  late final TextEditingController _editCtrl;

  @override
  void initState() {
    super.initState();
    _editCtrl = TextEditingController(text: widget.lesson.text);
    // Save draws its enabled state from the text against the lesson it is
    // editing, so the editor has to rebuild as it is typed into.
    _editCtrl.addListener(_onEditChanged);
  }

  @override
  void dispose() {
    _editCtrl.removeListener(_onEditChanged);
    _editCtrl.dispose();
    super.dispose();
  }

  void _onEditChanged() => setState(() {});

  /// Whether the text differs from the lesson being edited. An empty one is
  /// not a lesson, so it never counts as a change to save.
  bool get _editDiffers =>
      _editCtrl.text.trim().isNotEmpty &&
      _editCtrl.text.trim() != widget.lesson.text.trim();

  void _save() {
    if (_editCtrl.text.trim().isEmpty) return;
    widget.onUpdateText(_editCtrl.text);
    setState(() => _editing = false);
  }

  void _cancel() {
    _editCtrl.text = widget.lesson.text;
    setState(() => _editing = false);
  }

  @override
  Widget build(BuildContext context) {
    return SwipeActions(
      borderRadius: AppRadius.md,
      actions: [
        SwipeAction(
          icon: Icons.delete_outline,
          label: 'Delete',
          color: AppColors.danger,
          onTap: widget.onDelete,
        ),
      ],
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: lambdaBox(
          // The row itself stays neutral — pinning accents only the pin box.
          ContainerTone.ghost,
          radius: AppRadius.md,
        ),
        child: _editing ? _editor() : _view(),
      ),
    );
  }

  /// Read view: pin box + lesson text (tap the text to edit it).
  Widget _view() {
    final lesson = widget.lesson;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Pin sits at the leading edge, far from the trailing Delete
        // drawer — a tap on the pin can never land on Delete, and the pin
        // never gets covered when the row slides open. When pinned, the
        // box takes the glass recipe in accent — the pressable chrome.
        GestureDetector(
          onTap: widget.onTogglePin,
          child: Container(
            width: 40,
            height: 40,
            margin: const EdgeInsets.only(right: AppSpacing.sm, top: 1),
            alignment: Alignment.center,
            decoration: lesson.pinned
                ? glassBox(AppColors.accent, radius: 6)
                : BoxDecoration(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppColors.border, width: 0.5),
                  ),
            child: Icon(Icons.push_pin,
                size: 14, color: lesson.pinned ? AppColors.accent : AppColors.muted),
          ),
        ),
        Expanded(
          child: GestureDetector(
            onTap: () => setState(() {
              _editCtrl.text = widget.lesson.text;
              _editing = true;
            }),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(lesson.text,
                    style: AppFonts.ui(fontSize: 13, color: AppColors.primary)),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(DateFormat('MMM d · h:mm a').format(lesson.createdDate),
                        style: AppFonts.mono(
                            fontSize: 13, color: AppColors.muted)),
                    if (widget.isNew) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: AppColors.accentBg,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: AppColors.accent.withValues(alpha: 0.35),
                          ),
                        ),
                        child: Text('NEW',
                            style: AppFonts.mono(
                                fontSize: 14,
                                letterSpacing: 0.6,
                                color: AppColors.accent)),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Edit view: prefilled field + Save/Cancel, like the add flow.
  Widget _editor() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _editCtrl,
          autofocus: true,
          maxLines: 3,
          style: AppFonts.ui(fontSize: 14, color: AppColors.primary),
          decoration: InputDecoration(
            hintText: 'Lesson text…',
            hintStyle: AppFonts.ui(color: AppColors.muted),
            filled: true,
            fillColor: AppColors.surfaceHigh,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.md),
              borderSide: BorderSide(color: AppColors.primary),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(
                child: GlassButton(
                    label: 'Save',
                    solid: true,
                    compact: true,
                    disabled: !_editDiffers,
                    onPressed: _save)),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: GlassButton(
                label: 'Cancel',
                color: AppColors.muted,
                compact: true,
                onPressed: _cancel,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
