// LAB COPY — the /dev/pr-lab layout sandbox's own in-memory notes. Never
// import this from a production screen. Edit freely: nothing here can reach
// the real session, planner, logs or PR History demo (2026-10-21).

import 'package:flutter/foundation.dart';

import '../../../data/models/exercise_note.dart';

/// The fake session on the stage — the fixture's `_todaySessionId`, repeated
/// here because the fixture keeps it private (and the lab must not edit the
/// production demo's file to reach it). Notes stamped with this id are the
/// ones the session-scoped book tile counts.
const String kPrLabSessionId = 'demo-session-2026-10-20';

/// The lab's notes, kept in memory only — seeded fake rows for the demo
/// exercises, with every write landing in this object and nowhere else.
///
/// The lab's notes modal (`showPrLabNotesModal`) is bound to a
/// [Listenable] + plain callbacks, so the lab can hand it this store exactly
/// the way the live session hands it `SessionViewModel` — same interactions,
/// no database and no viewmodel (2026-10-21).
class PrLabNoteStore extends ChangeNotifier {
  PrLabNoteStore() : _notes = _seedNotes();

  /// Exercise id → its notes, oldest first.
  final Map<String, List<ExerciseNote>> _notes;

  /// The notes for one exercise, in creation order — the modal sorts
  /// (pinned first, then newest) itself.
  List<ExerciseNote> notesFor(String exerciseId) =>
      _notes[exerciseId] ?? const [];

  /// Every note the exercise has, any session.
  int countFor(String exerciseId) => notesFor(exerciseId).length;

  /// The notes added in the session on stage — what the action bar's book
  /// tile quotes (2026-10-21). Past notes are still opened by the tile;
  /// they just do not count as this session's work.
  int sessionCountFor(String exerciseId) => notesFor(
    exerciseId,
  ).where((note) => note.sessionId == kPrLabSessionId).length;

  /// The modal's load hook. The store is already in memory, so this is a
  /// no-op kept for the shared sheet's signature.
  Future<void> loadNotesFor(String exerciseId) async {}

  Future<void> addNote(String exerciseId, String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    final list = _notes.putIfAbsent(exerciseId, () => []);
    list.add(
      ExerciseNote(
        // Monotonic enough for a demo: the list only ever grows.
        exerciseNoteId:
            'lab-note-$exerciseId-${DateTime.now().microsecondsSinceEpoch}',
        userId: 'demo-user',
        exerciseId: exerciseId,
        text: trimmed,
        pinned: false,
        createdDate: DateTime.now(),
        // Typed during the session on screen: the book tile counts it.
        sessionId: kPrLabSessionId,
      ),
    );
    notifyListeners();
  }

  Future<void> togglePin(String exerciseId, String exerciseNoteId) async {
    _replace(
      exerciseId,
      exerciseNoteId,
      (note) => ExerciseNote(
        exerciseNoteId: note.exerciseNoteId,
        userId: note.userId,
        exerciseId: note.exerciseId,
        text: note.text,
        pinned: !note.pinned,
        createdDate: note.createdDate,
        sessionId: note.sessionId,
      ),
    );
  }

  Future<void> updateText(
    String exerciseId,
    String exerciseNoteId,
    String text,
  ) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    _replace(
      exerciseId,
      exerciseNoteId,
      (note) => ExerciseNote(
        exerciseNoteId: note.exerciseNoteId,
        userId: note.userId,
        exerciseId: note.exerciseId,
        text: trimmed,
        pinned: note.pinned,
        createdDate: note.createdDate,
        sessionId: note.sessionId,
      ),
    );
  }

  Future<void> deleteNote(String exerciseId, String exerciseNoteId) async {
    final list = _notes[exerciseId];
    if (list == null) return;
    list.removeWhere((note) => note.exerciseNoteId == exerciseNoteId);
    notifyListeners();
  }

  void _replace(
    String exerciseId,
    String exerciseNoteId,
    ExerciseNote Function(ExerciseNote note) update,
  ) {
    final list = _notes[exerciseId];
    if (list == null) return;
    final index = list.indexWhere((note) => note.exerciseNoteId == exerciseNoteId);
    if (index < 0) return;
    list[index] = update(list[index]);
    notifyListeners();
  }
}

/// The fake notes — exercise ids are [kDemoExercises]' ids from
/// `pr_history_fixture.dart`, so the pills have something to open on every
/// tab of the stage.
Map<String, List<ExerciseNote>> _seedNotes() {
  ExerciseNote note({
    required String exerciseId,
    required String id,
    required String text,
    required DateTime date,
    bool pinned = false,
    String? sessionId,
  }) => ExerciseNote(
    exerciseNoteId: id,
    userId: 'demo-user',
    exerciseId: exerciseId,
    text: text,
    pinned: pinned,
    createdDate: date,
    sessionId: sessionId,
  );

  return {
    'demo-bench': [
      note(
        exerciseId: 'demo-bench',
        id: 'lab-bench-l1',
        text: 'Elbows tucked at 45° — own the descent, don\'t bounce.',
        date: DateTime(2026, 8, 4, 18, 12),
      ),
      note(
        exerciseId: 'demo-bench',
        id: 'lab-bench-l2',
        text:
            'Wider grip was shifting the bar path left. Back to ring finger on the ring.',
        date: DateTime(2026, 9, 8, 18, 40),
        pinned: true,
      ),
      note(
        exerciseId: 'demo-bench',
        id: 'lab-bench-l3',
        text: 'Leg drive starts before the bar leaves the chest, not after.',
        date: DateTime(2026, 10, 20, 18, 22),
        sessionId: kPrLabSessionId,
      ),
      note(
        exerciseId: 'demo-bench',
        id: 'lab-bench-l4',
        text: 'Third set: bar drifted over the face. Same groove as set one.',
        date: DateTime(2026, 10, 20, 18, 47),
        sessionId: kPrLabSessionId,
      ),
    ],
    'demo-incline': [
      note(
        exerciseId: 'demo-incline',
        id: 'lab-incline-l1',
        text: 'Bench at 30° — 45° turns it into a shoulder press.',
        date: DateTime(2026, 9, 3, 17, 55),
      ),
      note(
        exerciseId: 'demo-incline',
        id: 'lab-incline-l2',
        text:
            'Pause on the chest for a one-count; the bounce was the whole PR.',
        date: DateTime(2026, 9, 17, 18, 21),
      ),
      note(
        exerciseId: 'demo-incline',
        id: 'lab-incline-l3',
        text: 'Seat one notch up — the shoulder stopped pinching at 30°.',
        date: DateTime(2026, 10, 20, 18, 31),
        sessionId: kPrLabSessionId,
      ),
    ],
    'demo-fly': [
      note(
        exerciseId: 'demo-fly',
        id: 'lab-fly-l1',
        text: 'Slight elbow bend held all the way through — never lock out.',
        date: DateTime(2026, 9, 11, 18, 8),
      ),
    ],
  };
}
