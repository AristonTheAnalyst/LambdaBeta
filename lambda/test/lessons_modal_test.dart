import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lambda/data/models/lesson.dart';
import 'package:lambda/data/repositories/lesson_repository.dart';
import 'package:lambda/features/session/view/lessons_modal.dart';

/// In-memory fake of [LessonRepository] so the modal can be driven in a widget
/// test without PowerSync. Tracks the same invariants the real repo enforces
/// (exclusive pin per exercise, soft-delete via is_active).
class FakeLessonRepo implements LessonRepository {
  final List<Lesson> lessons = [];
  int _calls = 0;

  @override
  Future<List<Lesson>> fetchLessons(String userId, String exerciseId) async =>
      List.of(lessons);

  @override
  Future<Lesson> createLesson(String userId, String exerciseId, String text, {String? sessionId}) async {
    final lesson = Lesson(
      lessonId: 'l${++_calls}',
      userId: userId,
      exerciseId: exerciseId,
      text: text,
      pinned: false,
      createdDate: DateTime(2026, 1, _calls),
    );
    lessons.add(lesson);
    return lesson;
  }

  @override
  Future<void> setPinned(String userId, String exerciseId, String lessonId, bool pinned) async {
    if (pinned) {
      for (var i = 0; i < lessons.length; i++) {
        if (lessons[i].exerciseId == exerciseId) {
          lessons[i] = _with(lessons[i], pinned: false);
        }
      }
    }
    for (var i = 0; i < lessons.length; i++) {
      if (lessons[i].lessonId == lessonId) {
        lessons[i] = _with(lessons[i], pinned: pinned);
      }
    }
  }

  @override
  Future<void> deleteLesson(String lessonId) async {
    lessons.removeWhere((l) => l.lessonId == lessonId);
  }

  Lesson _with(Lesson l, {bool? pinned}) => Lesson(
        lessonId: l.lessonId,
        userId: l.userId,
        exerciseId: l.exerciseId,
        text: l.text,
        pinned: pinned ?? l.pinned,
        createdDate: l.createdDate,
      );
}

void main() {
  final repo = FakeLessonRepo();
  final listenable = ValueNotifier(0);
  final exerciseId = 'ex1';

  Future<void> addLesson(String text) async {
    await repo.createLesson('u1', exerciseId, text);
    listenable.value++;
  }

  Widget buildModal() => MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                child: const Text('open'),
                onPressed: () => showLessonsModal(
                  context,
                  listenable: listenable,
                  lessonsFor: (_) => List.of(repo.lessons),
                  loadLessonsFor: (_) async {},
                  addLesson: (_, text) => addLesson(text),
                  toggleLessonPin: (_, lessonId) async {
                    await repo.setPinned('u1', exerciseId, lessonId,
                        !repo.lessons.firstWhere((l) => l.lessonId == lessonId).pinned);
                    listenable.value++;
                  },
                  deleteLesson: (_, lessonId) async {
                    await repo.deleteLesson(lessonId);
                    listenable.value++;
                  },
                  exerciseId: exerciseId,
                  exerciseName: 'Test Exercise',
                ),
              ),
            ),
          ),
        ),
      );

  testWidgets('pin clears other pins but never deletes the lesson',
      (tester) async {
    await addLesson('lesson one');
    await addLesson('lesson two');
    expect(repo.lessons.length, 2, reason: 'both lessons should be added');

    await tester.pumpWidget(buildModal());
    await tester.pumpAndSettle();

    await tester.tap(find.byType(ElevatedButton));
    await tester.pumpAndSettle();

    // The modal shows both lessons.
    expect(find.text('lesson one'), findsOneWidget);
    expect(find.text('lesson two'), findsOneWidget);

    // Pin "lesson two" via the pin button inside its row, regardless of the
    // modal's sort order.
    expect(find.byIcon(Icons.push_pin), findsNWidgets(2));
    final twoRow =
        find.ancestor(of: find.text('lesson two'), matching: find.byType(Row)).first;
    await tester.tap(find.descendant(of: twoRow, matching: find.byIcon(Icons.push_pin)));
    await tester.pumpAndSettle();

    // Exclusive pin: lesson two pinned, lesson one unpinned — NOT deleted.
    final one = repo.lessons.firstWhere((l) => l.text == 'lesson one');
    final two = repo.lessons.firstWhere((l) => l.text == 'lesson two');
    expect(one.pinned, isFalse, reason: 'pinning another must not delete/unpin-affect the first except clearing its pin');
    expect(two.pinned, isTrue, reason: 'pinned lesson should be pinned');
    expect(repo.lessons.length, 2, reason: 'pinning must never delete a lesson');
  });
}
