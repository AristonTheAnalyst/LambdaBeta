// LAB COPY — the /dev/pr-lab layout sandbox's own copy of the shared
// Lessons modal. Never import this from a production screen. Edit freely:
// nothing here can reach the real session, planner, logs or PR History demo
// (2026-10-21).

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/styles/app_colors.dart';
import '../../../core/styles/app_fonts.dart';
import '../../../core/styles/app_radius.dart';
import '../../../core/styles/app_spacing.dart';
import '../../../core/styles/app_text_styles.dart';
import '../../../data/models/lesson.dart';
import '../../../shared/widgets/container_styles.dart';
import '../../../shared/widgets/glass_button.dart';
import '../../../shared/widgets/lambda_input.dart';
import '../../../shared/widgets/slide_up_modal.dart';
import '../../../shared/widgets/user_name_text.dart';
import 'pr_lab_section_label.dart';
import 'pr_lab_swipe_actions.dart';

/// The lab's Lessons sheet — bound to a [Listenable] + callbacks rather than
/// a concrete viewmodel, exactly like the shared modal it is copied from.
///
/// The one difference is the feed's shape: the lessons typed into the session
/// on the desk lead under a `THIS SESSION` heading, and every lesson from
/// before it follows under `PREVIOUS` (2026-10-21). The shared modal's `NEW`
/// badge is gone here — the heading already says which lessons are new, and
/// the two would say it twice. The sheet otherwise behaves identically: pin,
/// tap-to-edit, swipe-to-delete, add.
void showPrLabLessonsModal(
  BuildContext context, {
  required Listenable listenable,
  required List<Lesson> Function(String exerciseId) lessonsFor,
  required Future<void> Function(String exerciseId) loadLessonsFor,
  required Future<void> Function(String exerciseId, String text) addLesson,
  required Future<void> Function(String exerciseId, String lessonId)
  toggleLessonPin,
  required Future<void> Function(String exerciseId, String lessonId)
  deleteLesson,
  required Future<void> Function(
    String exerciseId,
    String lessonId,
    String text,
  )
  updateLesson,
  required String exerciseId,
  required String exerciseName,

  /// When non-null (the live session's id), lessons created in that session
  /// form the sheet's first group.
  String? sessionId,
}) {
  showLambdaModal(
    context,
    fitContent: true,
    keyboardAware: true,
    child: _PrLabLessonsModalContent(
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

class _PrLabLessonsModalContent extends StatefulWidget {
  const _PrLabLessonsModalContent({
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
  final Future<void> Function(String exerciseId, String lessonId)
  toggleLessonPin;
  final Future<void> Function(String exerciseId, String lessonId) deleteLesson;
  final Future<void> Function(String exerciseId, String lessonId, String text)
  updateLesson;
  final String exerciseId;
  final String exerciseName;
  final String? sessionId;

  @override
  State<_PrLabLessonsModalContent> createState() =>
      _PrLabLessonsModalContentState();
}

class _PrLabLessonsModalContentState extends State<_PrLabLessonsModalContent> {
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
        final ordered = [...lessons]
          ..sort((a, b) {
            final pin = (b.pinned ? 1 : 0).compareTo(a.pinned ? 1 : 0);
            return pin != 0 ? pin : b.createdDate.compareTo(a.createdDate);
          });
        // The session on the desk's lessons lead; everything from before it
        // follows under its own heading. Pin order holds inside each group,
        // so a pinned old cue never jumps the line into this session's shelf.
        final sessionLessons = widget.sessionId == null
            ? const <Lesson>[]
            : [
                for (final lesson in ordered)
                  if (lesson.sessionId == widget.sessionId) lesson,
              ];
        final previousLessons = [
          for (final lesson in ordered)
            if (widget.sessionId == null ||
                lesson.sessionId != widget.sessionId)
              lesson,
        ];
        final groups = <Widget>[];
        void addGroup(String label, List<Lesson> lessons) {
          if (lessons.isEmpty) return;
          if (groups.isNotEmpty) {
            groups.add(const SizedBox(height: AppSpacing.md));
          }
          groups.add(PrLabSectionLabel(label));
          groups.add(const SizedBox(height: AppSpacing.sm));
          for (var i = 0; i < lessons.length; i++) {
            if (i > 0) groups.add(const SizedBox(height: AppSpacing.sm));
            final lesson = lessons[i];
            groups.add(
              _PrLabLessonRow(
                lesson: lesson,
                onTogglePin: () =>
                    widget.toggleLessonPin(widget.exerciseId, lesson.lessonId),
                onDelete: () =>
                    widget.deleteLesson(widget.exerciseId, lesson.lessonId),
                onUpdateText: (text) => widget.updateLesson(
                  widget.exerciseId,
                  lesson.lessonId,
                  text,
                ),
              ),
            );
          }
        }

        addGroup('This session', sessionLessons);
        addGroup('Previously', previousLessons);
        return SafeArea(
          key: const ValueKey('pr-lab-lessons-sheet'),
          child: SizedBox(
            // Fixed half-screen sheet: small lesson counts don't inflate it
            // and the empty state doesn't collapse it to full screen — the
            // list scrolls within this height.
            height: MediaQuery.of(context).size.height * 0.5,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl,
                AppSpacing.xl,
                AppSpacing.xl,
                AppSpacing.lg,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // The exercise as an eyebrow over the title — the
                            // header recipe the PR sheet now shares.
                            UserNameText(
                              widget.exerciseName.toUpperCase(),
                              tooltip: true,
                              style: AppFonts.mono(
                                fontSize: AppTextStyles.caption,
                                fontWeight: FontWeight.w500,
                                color: AppColors.inkSecondary,
                                letterSpacing: 0.8,
                              ),
                            ),
                            Text(
                              'Lessons',
                              style: AppFonts.ui(
                                fontSize: AppTextStyles.lg,
                                fontWeight: FontWeight.w800,
                                color: AppColors.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      GlassButton(
                        label: '',
                        icon: Icons.add,
                        semanticsLabel: 'Add lesson',
                        compact: true,
                        onPressed: () => setState(() => _adding = true),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  if (_adding) ...[
                    LambdaInput(
                      controller: _draftCtrl,
                      autofocus: true,
                      minLines: 2,
                      maxLines: 3,
                      placeholder:
                          'What did you learn? Cues, breakthroughs, adjustments…',
                      // The sheet's default background is a surface ground.
                      elevated: true,
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
                            // Solid vs glass already carries the hierarchy;
                            // muted ink on muted glass measured 3.44:1
                            // (2026-10-21).
                            label: 'Cancel',
                            color: AppColors.primary,
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
                              padding: const EdgeInsets.symmetric(
                                vertical: AppSpacing.xl,
                              ),
                              child: Text(
                                'No lessons yet — tap Add to record a cue or breakthrough.',
                                textAlign: TextAlign.center,
                                style: AppFonts.ui(
                                  fontSize: AppTextStyles.sm,
                                  height: 1.4,
                                  color: AppColors.inkSecondary,
                                ),
                              ),
                            ),
                          )
                        : ListView(children: groups),
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

class _PrLabLessonRow extends StatefulWidget {
  const _PrLabLessonRow({
    required this.lesson,
    required this.onTogglePin,
    required this.onDelete,
    required this.onUpdateText,
  });

  final Lesson lesson;
  final VoidCallback onTogglePin;
  final VoidCallback onDelete;
  final void Function(String text) onUpdateText;

  @override
  State<_PrLabLessonRow> createState() => _PrLabLessonRowState();
}

class _PrLabLessonRowState extends State<_PrLabLessonRow> {
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
    // The lab's circle drawer, same as the set rows: the delete circle scales
    // in as the row is swiped (2026-10-22).
    return PrLabSwipeActions(
      borderRadius: AppRadius.md,
      actions: [
        PrLabSwipeAction(
          icon: Icons.delete_outline,
          color: AppColors.danger,
          foreground: AppColors.dangerText,
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
        Semantics(
          button: true,
          // The action, not the glyph — the pin is a lone icon control with
          // no word beside it (accessibility §5).
          label: lesson.pinned ? 'Unpin lesson' : 'Pin lesson',
          child: GestureDetector(
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
              child: Icon(
                Icons.push_pin,
                // A lone glyph control draws at the nav scale, 18–20
                // (typography §3).
                size: 18,
                color: lesson.pinned ? AppColors.accent : AppColors.muted,
              ),
            ),
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
                // The sheet's content: the ladder's body size, with a line
                // height for prose (it had neither before, 2026-10-21).
                Text(
                  lesson.text,
                  style: AppFonts.ui(
                    fontSize: AppTextStyles.body,
                    height: 1.35,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  DateFormat('MMM d · h:mm a').format(lesson.createdDate),
                  style: AppFonts.mono(
                    fontSize: AppTextStyles.xs,
                    fontWeight: FontWeight.w500,
                    color: AppColors.inkSecondary,
                  ),
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
        LambdaInput(
          controller: _editCtrl,
          autofocus: true,
          minLines: 2,
          maxLines: 3,
          placeholder: 'Lesson text…',
          // The sheet's default background is a surface ground.
          elevated: true,
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
                onPressed: _save,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: GlassButton(
                label: 'Cancel',
                color: AppColors.primary,
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
