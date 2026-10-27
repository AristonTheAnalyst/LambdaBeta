// LAB COPY — the /dev/pr-lab layout sandbox's own copy of the shared
// Notes modal. Never import this from a production screen. Edit freely:
// nothing here can reach the real session, planner, logs or PR History demo
// (2026-10-21).

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/styles/app_colors.dart';
import '../../../core/styles/app_fonts.dart';
import '../../../core/styles/app_radius.dart';
import '../../../core/styles/app_spacing.dart';
import '../../../core/styles/app_text_styles.dart';
import '../../../data/models/exercise_note.dart';
import '../../../shared/widgets/container_styles.dart';
import '../../../shared/widgets/glass_button.dart';
import '../../../shared/widgets/lambda_input.dart';
import '../../../shared/widgets/slide_up_modal.dart';
import '../../../shared/widgets/user_name_text.dart';
import 'pr_lab_section_label.dart';
import 'pr_lab_swipe_actions.dart';

/// The lab's Notes sheet — bound to a [Listenable] + callbacks rather than
/// a concrete viewmodel, exactly like the shared modal it is copied from.
///
/// The one difference is the feed's shape: the notes typed into the session
/// on the desk lead under a `THIS SESSION` heading, and every note from
/// before it follows under `PREVIOUS` (2026-10-21). The shared modal's `NEW`
/// badge is gone here — the heading already says which notes are new, and
/// the two would say it twice. The sheet otherwise behaves identically: pin,
/// tap-to-edit, swipe-to-delete, add.
void showPrLabNotesModal(
  BuildContext context, {
  required Listenable listenable,
  required List<ExerciseNote> Function(String exerciseId) notesFor,
  required Future<void> Function(String exerciseId) loadNotesFor,
  required Future<void> Function(String exerciseId, String text) addNote,
  required Future<void> Function(String exerciseId, String exerciseNoteId)
  toggleNotePin,
  required Future<void> Function(String exerciseId, String exerciseNoteId)
  deleteNote,
  required Future<void> Function(
    String exerciseId,
    String exerciseNoteId,
    String text,
  )
  updateNote,
  required String exerciseId,
  required String exerciseName,

  /// When non-null (the live session's id), notes created in that session
  /// form the sheet's first group.
  String? sessionId,
}) {
  showLambdaModal(
    context,
    fitContent: true,
    keyboardAware: true,
    child: _PrLabNotesModalContent(
      listenable: listenable,
      notesFor: notesFor,
      loadNotesFor: loadNotesFor,
      addNote: addNote,
      toggleNotePin: toggleNotePin,
      deleteNote: deleteNote,
      updateNote: updateNote,
      exerciseId: exerciseId,
      exerciseName: exerciseName,
      sessionId: sessionId,
    ),
  );
}

class _PrLabNotesModalContent extends StatefulWidget {
  const _PrLabNotesModalContent({
    required this.listenable,
    required this.notesFor,
    required this.loadNotesFor,
    required this.addNote,
    required this.toggleNotePin,
    required this.deleteNote,
    required this.updateNote,
    required this.exerciseId,
    required this.exerciseName,
    this.sessionId,
  });

  final Listenable listenable;
  final List<ExerciseNote> Function(String exerciseId) notesFor;
  final Future<void> Function(String exerciseId) loadNotesFor;
  final Future<void> Function(String exerciseId, String text) addNote;
  final Future<void> Function(String exerciseId, String exerciseNoteId)
  toggleNotePin;
  final Future<void> Function(String exerciseId, String exerciseNoteId) deleteNote;
  final Future<void> Function(String exerciseId, String exerciseNoteId, String text)
  updateNote;
  final String exerciseId;
  final String exerciseName;
  final String? sessionId;

  @override
  State<_PrLabNotesModalContent> createState() =>
      _PrLabNotesModalContentState();
}

class _PrLabNotesModalContentState extends State<_PrLabNotesModalContent> {
  bool _adding = false;
  final _draftCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    widget.loadNotesFor(widget.exerciseId);
    // The Save ExerciseNote button draws its enabled state from the draft, so the
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

  void _addNote() {
    if (_draftCtrl.text.trim().isEmpty) return;
    widget.addNote(widget.exerciseId, _draftCtrl.text);
    _draftCtrl.clear();
    setState(() => _adding = false);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.listenable,
      builder: (context, _) {
        final notes = widget.notesFor(widget.exerciseId);
        // Pinned first, then newest by datetime (Dart's sort is unstable, so
        // sort by both keys explicitly to preserve chronological order).
        final ordered = [...notes]
          ..sort((a, b) {
            final pin = (b.pinned ? 1 : 0).compareTo(a.pinned ? 1 : 0);
            return pin != 0 ? pin : b.createdDate.compareTo(a.createdDate);
          });
        // The session on the desk's notes lead; everything from before it
        // follows under its own heading. Pin order holds inside each group,
        // so a pinned old cue never jumps the line into this session's shelf.
        final sessionExerciseNotes = widget.sessionId == null
            ? const <ExerciseNote>[]
            : [
                for (final note in ordered)
                  if (note.sessionId == widget.sessionId) note,
              ];
        final previousNotes = [
          for (final note in ordered)
            if (widget.sessionId == null ||
                note.sessionId != widget.sessionId)
              note,
        ];
        final groups = <Widget>[];
        void addGroup(String label, List<ExerciseNote> notes) {
          if (notes.isEmpty) return;
          if (groups.isNotEmpty) {
            groups.add(const SizedBox(height: AppSpacing.md));
          }
          groups.add(PrLabSectionLabel(label));
          groups.add(const SizedBox(height: AppSpacing.sm));
          for (var i = 0; i < notes.length; i++) {
            if (i > 0) groups.add(const SizedBox(height: AppSpacing.sm));
            final note = notes[i];
            groups.add(
              _PrLabNoteRow(
                note: note,
                onTogglePin: () =>
                    widget.toggleNotePin(widget.exerciseId, note.exerciseNoteId),
                onDelete: () =>
                    widget.deleteNote(widget.exerciseId, note.exerciseNoteId),
                onUpdateText: (text) => widget.updateNote(
                  widget.exerciseId,
                  note.exerciseNoteId,
                  text,
                ),
              ),
            );
          }
        }

        addGroup('This session', sessionExerciseNotes);
        addGroup('Previously', previousNotes);
        return SafeArea(
          key: const ValueKey('pr-lab-notes-sheet'),
          child: SizedBox(
            // Fixed half-screen sheet: small note counts don't inflate it
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
                              'Notes',
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
                        semanticsLabel: 'Add note',
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
                            label: 'Save ExerciseNote',
                            solid: true,
                            // Nothing to save until something is typed.
                            disabled: _draftCtrl.text.trim().isEmpty,
                            onPressed: _addNote,
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
                                'No notes yet — tap Add to record a cue or breakthrough.',
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

class _PrLabNoteRow extends StatefulWidget {
  const _PrLabNoteRow({
    required this.note,
    required this.onTogglePin,
    required this.onDelete,
    required this.onUpdateText,
  });

  final ExerciseNote note;
  final VoidCallback onTogglePin;
  final VoidCallback onDelete;
  final void Function(String text) onUpdateText;

  @override
  State<_PrLabNoteRow> createState() => _PrLabNoteRowState();
}

class _PrLabNoteRowState extends State<_PrLabNoteRow> {
  bool _editing = false;
  late final TextEditingController _editCtrl;

  @override
  void initState() {
    super.initState();
    _editCtrl = TextEditingController(text: widget.note.text);
    // Save draws its enabled state from the text against the note it is
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

  /// Whether the text differs from the note being edited. An empty one is
  /// not a note, so it never counts as a change to save.
  bool get _editDiffers =>
      _editCtrl.text.trim().isNotEmpty &&
      _editCtrl.text.trim() != widget.note.text.trim();

  void _save() {
    if (_editCtrl.text.trim().isEmpty) return;
    widget.onUpdateText(_editCtrl.text);
    setState(() => _editing = false);
  }

  void _cancel() {
    _editCtrl.text = widget.note.text;
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

  /// Read view: pin box + note text (tap the text to edit it).
  Widget _view() {
    final note = widget.note;
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
          label: note.pinned ? 'Unpin note' : 'Pin note',
          child: GestureDetector(
            onTap: widget.onTogglePin,
            child: Container(
              width: 40,
              height: 40,
              margin: const EdgeInsets.only(right: AppSpacing.sm, top: 1),
              alignment: Alignment.center,
              decoration: note.pinned
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
                color: note.pinned ? AppColors.accent : AppColors.muted,
              ),
            ),
          ),
        ),
        Expanded(
          child: GestureDetector(
            onTap: () => setState(() {
              _editCtrl.text = widget.note.text;
              _editing = true;
            }),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // The sheet's content: the ladder's body size, with a line
                // height for prose (it had neither before, 2026-10-21).
                Text(
                  note.text,
                  style: AppFonts.ui(
                    fontSize: AppTextStyles.body,
                    height: 1.35,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  DateFormat('MMM d · h:mm a').format(note.createdDate),
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
          placeholder: 'ExerciseNote text…',
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
