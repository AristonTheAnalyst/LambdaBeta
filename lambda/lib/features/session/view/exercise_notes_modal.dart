import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/styles/app_colors.dart';
import '../../../core/styles/app_fonts.dart';
import '../../../core/styles/app_radius.dart';
import '../../../core/styles/app_spacing.dart';
import '../../../core/styles/app_text_styles.dart';
import '../../../data/models/exercise_note.dart';
import '../../../shared/widgets/coach_created_mark.dart';
import '../../../shared/widgets/glass_button.dart';
import '../../../shared/widgets/user_name_text.dart';
import '../../../shared/widgets/container_styles.dart';
import '../../../shared/widgets/lambda_input.dart';
import '../../../shared/widgets/slide_up_modal.dart';
import '../../../shared/widgets/swipe_actions.dart';
import 'sheet_section_label.dart';

/// Bound to a [Listenable] + a handful of callbacks rather than a concrete
/// viewmodel type, so both `SessionViewModel` (a `ChangeNotifier`) and
/// `WorkoutEditorViewModel` (a `ValueNotifier<WorkoutEditorState>`) can
/// reuse this same modal for the exact same `dim_exercise_note` data — notes are
/// per-exercise and cross-session, not tied to either feature.
///
/// The feed is grouped in chronological order, newest first (2026-10-23):
/// the notes added after the session on the desk (`AFTER`, drawn only
/// when it holds something), then the session itself — `THIS
/// SESSION` while it is the live one, its date (`18 OCT 2026`) when it is a
/// past record — then everything from before it (`PREVIOUSLY`). Reading a
/// past record from Logs needs the third shelf: a note written afterwards
/// is not "previously". The old `NEW` badge is gone: the heading already
/// says which notes are new, and the two would say it twice. Pin,
/// tap-to-edit, swipe-to-delete and add all behave as before.
///
/// Where a review stands behind the record (2026-10-26), the caller also
/// names the checkpoint the last pass closed on: the after-group then splits
/// in two — what landed since that checkpoint (`SINCE LAST REVIEW`) above
/// what landed after the session but no later than it (`AFTER`). A pass is
/// reading for its own window, and that window belongs at the top of the
/// sheet rather than folded into the session's aftermath. With no session on
/// the desk — the planner's review editor, which has no record to place in
/// time — the checkpoint divides the whole outside-the-session shelf
/// instead: since the pass leads, the rest is `PREVIOUSLY`. Without a
/// checkpoint nothing moves: the three shelves stand as they always did.
void showExerciseNotesModal(
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

  /// When non-null (the session on the desk's id), its notes form the
  /// sheet's first group.
  String? sessionId,

  /// When the session on the desk started — what places a note added
  /// outside it into `PREVIOUSLY` or `AFTER`. Null keeps the lab's two
  /// groups.
  DateTime? sessionStartedAt,

  /// Whether the session on the desk is the live one. True names the middle
  /// shelf `THIS SESSION`; false dates it, because a record being read is
  /// not "this session" to the person reading it.
  bool sessionIsLive = false,

  /// A friend's record (2026-10-23): the shelves read exactly as always, but
  /// no composer, no pin, no edit, no delete — the notes are somebody else's.
  bool readOnly = false,

  /// Whether the sheet offers Delete. Coach mode sets this false
  /// (2026-10-28): notes can be written and pinned, never removed.
  bool canDelete = true,

  /// When set, only notes created by this user are editable/pinnable at all
  /// — coach mode passes the coach's id, so the athlete's own notes draw as
  /// read-only shelves while the coach's notes stay manageable (2026-10-29).
  String? manageOnlyUserId,

  /// Where the last review of this ground ended (2026-10-26) — resolved by
  /// the caller, which is the only one that knows a pass stands behind the
  /// record. A note written after it leads the sheet as `SINCE LAST
  /// REVIEW`; one written after the session but no later than it stays
  /// `AFTER`. Null keeps the three shelves exactly as they were.
  DateTime? sinceLastReviewAt,
}) {
  showLambdaModal(
    context,
    fitContent: true,
    keyboardAware: true,
    child: _ExerciseNotesModalContent(
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
      sessionStartedAt: sessionStartedAt,
      sessionIsLive: sessionIsLive,
      readOnly: readOnly,
      canDelete: canDelete,
      manageOnlyUserId: manageOnlyUserId,
      sinceLastReviewAt: sinceLastReviewAt,
    ),
  );
}

class _ExerciseNotesModalContent extends StatefulWidget {
  const _ExerciseNotesModalContent({
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
    this.sessionStartedAt,
    this.sessionIsLive = false,
    this.readOnly = false,
    this.canDelete = true,
    this.manageOnlyUserId,
    this.sinceLastReviewAt,
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
  final DateTime? sessionStartedAt;
  final bool sessionIsLive;

  /// A friend's record — the sheet reads, it never writes (2026-10-23).
  final bool readOnly;

  /// Whether the rows offer Delete. Coach mode sets it false (2026-10-28);
  /// composing, pinning and editing stay.
  final bool canDelete;

  /// When set, only notes created by this user are manageable (2026-10-29).
  final String? manageOnlyUserId;

  /// Where the last review of this ground ended — the split inside the
  /// after-group (2026-10-26). Null keeps the three shelves.
  final DateTime? sinceLastReviewAt;

  @override
  State<_ExerciseNotesModalContent> createState() => _ExerciseNotesModalContentState();
}

class _ExerciseNotesModalContentState extends State<_ExerciseNotesModalContent> {
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
        // Chronological, newest first (2026-10-23): what has been added
        // since the session, the session itself, then what came before it.
        // Pin order holds inside each group, so a pinned old cue never jumps
        // the line into another shelf. A note added after the session is
        // not "previously" — reading a past record needs the third shelf, or
        // the headings would misdate it. A live session's middle shelf is
        // "this session"; a record's is its date.
        final startedAt = widget.sessionStartedAt;
        final sessionLabel = widget.sessionIsLive || startedAt == null
            ? 'This session'
            : DateFormat('d MMM yyyy').format(startedAt);
        bool inThisSession(ExerciseNote note) =>
            widget.sessionId != null && note.sessionId == widget.sessionId;
        final sessionExerciseNotes = [
          for (final note in ordered)
            if (inThisSession(note)) note,
        ];
        final afterNotes = [
          for (final note in ordered)
            if (!inThisSession(note) &&
                startedAt != null &&
                note.createdDate.isAfter(startedAt))
              note,
        ];
        // A checkpoint behind the record splits the after-group in two
        // (2026-10-26): what landed since the last review leads, and what
        // landed after the session but no later than that review keeps the
        // `AFTER` shelf. A strict split, drawn newest-first — the newer half
        // must come first, or the sheet would file a later note under an
        // older heading. With no session on the desk (the planner) there is
        // no after-group to split: the checkpoint divides the whole shelf
        // outside the session instead, so the pass still leads and what came
        // at or before it is `PREVIOUSLY`.
        final checkpoint = widget.sinceLastReviewAt;
        bool afterCheckpoint(ExerciseNote note) =>
            checkpoint != null && note.createdDate.isAfter(checkpoint);
        final sinceReviewNotes = [
          for (final note in ordered)
            if (!inThisSession(note) &&
                (startedAt == null || note.createdDate.isAfter(startedAt)) &&
                afterCheckpoint(note))
              note,
        ];
        final afterRemainderNotes = [
          for (final note in afterNotes)
            if (!afterCheckpoint(note)) note,
        ];
        final previousNotes = [
          for (final note in ordered)
            if (!inThisSession(note) &&
                (startedAt == null
                    ? !afterCheckpoint(note)
                    : !note.createdDate.isAfter(startedAt)))
              note,
        ];
        final groups = <Widget>[];
        void addGroup(String label, List<ExerciseNote> groupNotes) {
          if (groupNotes.isEmpty) return;
          if (groups.isNotEmpty) {
            groups.add(const SizedBox(height: AppSpacing.md));
          }
          groups.add(SheetSectionLabel(label));
          groups.add(const SizedBox(height: AppSpacing.sm));
          for (var i = 0; i < groupNotes.length; i++) {
            if (i > 0) groups.add(const SizedBox(height: AppSpacing.sm));
            final note = groupNotes[i];
            groups.add(
              _NoteRow(
                note: note,
                // A coach may manage only their own notes; the athlete's shelve
                // read-only (2026-10-29).
                readOnly:
                    widget.readOnly ||
                    (widget.manageOnlyUserId != null &&
                        note.createdByUserId != widget.manageOnlyUserId),
                canDelete: widget.canDelete,
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

        addGroup('Since last review', sinceReviewNotes);
        addGroup('After', afterRemainderNotes);
        addGroup(sessionLabel, sessionExerciseNotes);
        addGroup('Previously', previousNotes);
        return SafeArea(
          key: const ValueKey('notes-sheet'),
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
                            // header recipe the PR History sheet shares.
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
                              'Exercise Notes',
                              style: AppFonts.ui(
                                fontSize: AppTextStyles.lg,
                                fontWeight: FontWeight.w800,
                                color: AppColors.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // A friend's notes are read, never added to.
                      if (!widget.readOnly)
                        GlassButton(
                          label: '',
                          icon: Icons.add,
                          semanticsLabel: 'Add exercise note',
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
                            label: 'Save Note',
                            solid: true,
                            // Nothing to save until something is typed.
                            disabled: _draftCtrl.text.trim().isEmpty,
                            onPressed: _addNote,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: GlassButton(
                            label: 'Cancel',
                            // Solid vs glass already carries the hierarchy;
                            // muted ink on muted glass measured 3.44:1
                            // (2026-10-22).
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
                                widget.readOnly
                                    ? 'No exercise notes yet.'
                                    : 'No exercise notes yet — tap Add to record a cue or breakthrough.',
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

class _NoteRow extends StatefulWidget {
  const _NoteRow({
    required this.note,
    required this.onTogglePin,
    required this.onDelete,
    required this.onUpdateText,
    this.readOnly = false,
    this.canDelete = true,
  });

  final ExerciseNote note;
  final VoidCallback onTogglePin;
  final VoidCallback onDelete;
  final void Function(String text) onUpdateText;

  /// Draws the row without any write affordance — no swipe drawer, no pin
  /// control, no tap-to-edit (2026-10-23).
  final bool readOnly;

  /// Keeps the row editable and pinnable but withholds the delete swipe
  /// (2026-10-28, coach mode).
  final bool canDelete;

  @override
  State<_NoteRow> createState() => _NoteRowState();
}

class _NoteRowState extends State<_NoteRow> {
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
    final row = Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: lambdaBox(
        // The row itself stays neutral — pinning accents only the pin box.
        ContainerTone.ghost,
        radius: AppRadius.md,
      ),
      child: _editing ? _editor() : _view(),
    );
    if (widget.readOnly || !widget.canDelete) return row;
    return SwipeActions(
      borderRadius: AppRadius.md,
      actions: [
        SwipeAction(
          icon: Icons.delete_outline,

          color: AppColors.danger,
          foreground: AppColors.dangerText,
          onTap: widget.onDelete,
        ),
      ],
      child: row,
    );
  }

  /// Read view: pin box + note text (tap the text to edit it).
  Widget _view() {
    final note = widget.note;
    // The pin box, drawn either as the control it is or as the state it
    // shows on a friend's read-only shelf.
    final pinBox = Container(
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
    );
    final textBody = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // The sheet's content: the ladder's body size, with a line
        // height for prose.
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
        if (note.createdByUserId != null || note.updatedByUserId != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: CoachCreatedMark(
              createdByUserId: note.createdByUserId,
              updatedByUserId: note.updatedByUserId,
            ),
          ),
      ],
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Pin sits at the leading edge, far from the trailing Delete
        // drawer — a tap on the pin can never land on Delete, and the pin
        // never gets covered when the row slides open. When pinned, the
        // box takes the glass recipe in accent — the pressable chrome.
        Semantics(
          button: !widget.readOnly,
          // The action, not the glyph — the pin is a lone icon control with
          // no word beside it (accessibility §5). A friend's shelf has no
          // action to announce, so it reads the pin's state instead.
          label: widget.readOnly
              ? (note.pinned ? 'Pinned note' : 'Unpinned note')
              : (note.pinned ? 'Unpin note' : 'Pin note'),
          child: widget.readOnly
              ? pinBox
              : GestureDetector(onTap: widget.onTogglePin, child: pinBox),
        ),
        Expanded(
          child: widget.readOnly
              // No tap-to-edit on somebody else's note.
              ? textBody
              : GestureDetector(
                  onTap: () => setState(() {
                    _editCtrl.text = widget.note.text;
                    _editing = true;
                  }),
                  child: textBody,
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
          placeholder: 'Note text…',
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
