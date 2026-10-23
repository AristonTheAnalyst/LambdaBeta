// LAB COPY — the /dev/pr-lab layout sandbox's own in-memory lessons. Never
// import this from a production screen. Edit freely: nothing here can reach
// the real session, planner, logs or PR History demo (2026-10-21).

import 'package:flutter/foundation.dart';

import '../../../data/models/lesson.dart';

/// The fake session on the stage — the fixture's `_todaySessionId`, repeated
/// here because the fixture keeps it private (and the lab must not edit the
/// production demo's file to reach it). Lessons stamped with this id are the
/// ones the session-scoped book tile counts.
const String kPrLabSessionId = 'demo-session-2026-10-20';

/// The lab's lessons, kept in memory only — seeded fake rows for the demo
/// exercises, with every write landing in this object and nowhere else.
///
/// The lab's lessons modal (`showPrLabLessonsModal`) is bound to a
/// [Listenable] + plain callbacks, so the lab can hand it this store exactly
/// the way the live session hands it `SessionViewModel` — same interactions,
/// no database and no viewmodel (2026-10-21).
class PrLabLessonStore extends ChangeNotifier {
  PrLabLessonStore() : _lessons = _seedLessons();

  /// Exercise id → its lessons, oldest first.
  final Map<String, List<Lesson>> _lessons;

  /// The lessons for one exercise, in creation order — the modal sorts
  /// (pinned first, then newest) itself.
  List<Lesson> lessonsFor(String exerciseId) =>
      _lessons[exerciseId] ?? const [];

  /// Every lesson the exercise has, any session.
  int countFor(String exerciseId) => lessonsFor(exerciseId).length;

  /// The lessons added in the session on stage — what the action bar's book
  /// tile quotes (2026-10-21). Past lessons are still opened by the tile;
  /// they just do not count as this session's work.
  int sessionCountFor(String exerciseId) => lessonsFor(
    exerciseId,
  ).where((lesson) => lesson.sessionId == kPrLabSessionId).length;

  /// The modal's load hook. The store is already in memory, so this is a
  /// no-op kept for the shared sheet's signature.
  Future<void> loadLessonsFor(String exerciseId) async {}

  Future<void> addLesson(String exerciseId, String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    final list = _lessons.putIfAbsent(exerciseId, () => []);
    list.add(
      Lesson(
        // Monotonic enough for a demo: the list only ever grows.
        lessonId:
            'lab-lesson-$exerciseId-${DateTime.now().microsecondsSinceEpoch}',
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

  Future<void> togglePin(String exerciseId, String lessonId) async {
    _replace(
      exerciseId,
      lessonId,
      (lesson) => Lesson(
        lessonId: lesson.lessonId,
        userId: lesson.userId,
        exerciseId: lesson.exerciseId,
        text: lesson.text,
        pinned: !lesson.pinned,
        createdDate: lesson.createdDate,
        sessionId: lesson.sessionId,
      ),
    );
  }

  Future<void> updateText(
    String exerciseId,
    String lessonId,
    String text,
  ) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    _replace(
      exerciseId,
      lessonId,
      (lesson) => Lesson(
        lessonId: lesson.lessonId,
        userId: lesson.userId,
        exerciseId: lesson.exerciseId,
        text: trimmed,
        pinned: lesson.pinned,
        createdDate: lesson.createdDate,
        sessionId: lesson.sessionId,
      ),
    );
  }

  Future<void> deleteLesson(String exerciseId, String lessonId) async {
    final list = _lessons[exerciseId];
    if (list == null) return;
    list.removeWhere((lesson) => lesson.lessonId == lessonId);
    notifyListeners();
  }

  void _replace(
    String exerciseId,
    String lessonId,
    Lesson Function(Lesson lesson) update,
  ) {
    final list = _lessons[exerciseId];
    if (list == null) return;
    final index = list.indexWhere((lesson) => lesson.lessonId == lessonId);
    if (index < 0) return;
    list[index] = update(list[index]);
    notifyListeners();
  }
}

/// The fake lessons — exercise ids are [kDemoExercises]' ids from
/// `pr_history_fixture.dart`, so the pills have something to open on every
/// tab of the stage.
Map<String, List<Lesson>> _seedLessons() {
  Lesson lesson({
    required String exerciseId,
    required String id,
    required String text,
    required DateTime date,
    bool pinned = false,
    String? sessionId,
  }) => Lesson(
    lessonId: id,
    userId: 'demo-user',
    exerciseId: exerciseId,
    text: text,
    pinned: pinned,
    createdDate: date,
    sessionId: sessionId,
  );

  return {
    'demo-bench': [
      lesson(
        exerciseId: 'demo-bench',
        id: 'lab-bench-l1',
        text: 'Elbows tucked at 45° — own the descent, don\'t bounce.',
        date: DateTime(2026, 8, 4, 18, 12),
      ),
      lesson(
        exerciseId: 'demo-bench',
        id: 'lab-bench-l2',
        text:
            'Wider grip was shifting the bar path left. Back to ring finger on the ring.',
        date: DateTime(2026, 9, 8, 18, 40),
        pinned: true,
      ),
      lesson(
        exerciseId: 'demo-bench',
        id: 'lab-bench-l3',
        text: 'Leg drive starts before the bar leaves the chest, not after.',
        date: DateTime(2026, 10, 20, 18, 22),
        sessionId: kPrLabSessionId,
      ),
      lesson(
        exerciseId: 'demo-bench',
        id: 'lab-bench-l4',
        text: 'Third set: bar drifted over the face. Same groove as set one.',
        date: DateTime(2026, 10, 20, 18, 47),
        sessionId: kPrLabSessionId,
      ),
    ],
    'demo-incline': [
      lesson(
        exerciseId: 'demo-incline',
        id: 'lab-incline-l1',
        text: 'Bench at 30° — 45° turns it into a shoulder press.',
        date: DateTime(2026, 9, 3, 17, 55),
      ),
      lesson(
        exerciseId: 'demo-incline',
        id: 'lab-incline-l2',
        text:
            'Pause on the chest for a one-count; the bounce was the whole PR.',
        date: DateTime(2026, 9, 17, 18, 21),
      ),
      lesson(
        exerciseId: 'demo-incline',
        id: 'lab-incline-l3',
        text: 'Seat one notch up — the shoulder stopped pinching at 30°.',
        date: DateTime(2026, 10, 20, 18, 31),
        sessionId: kPrLabSessionId,
      ),
    ],
    'demo-fly': [
      lesson(
        exerciseId: 'demo-fly',
        id: 'lab-fly-l1',
        text: 'Slight elbow bend held all the way through — never lock out.',
        date: DateTime(2026, 9, 11, 18, 8),
      ),
    ],
  };
}
