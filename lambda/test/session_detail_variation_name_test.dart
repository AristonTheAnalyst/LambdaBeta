import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lambda/data/cache/past_sets_timeline_cache.dart';
import 'package:lambda/data/models/custom_variation.dart';
import 'package:lambda/data/models/exercise_detail.dart';
import 'package:lambda/data/models/lesson.dart';
import 'package:lambda/data/models/session.dart';
import 'package:lambda/data/models/session_exercise.dart';
import 'package:lambda/data/models/session_exercise_set.dart';
import 'package:lambda/data/repositories/exercise_repository.dart';
import 'package:lambda/data/repositories/lesson_repository.dart';
import 'package:lambda/data/repositories/session_repository.dart';
import 'package:lambda/features/logs/viewmodel/session_detail_viewmodel.dart';
import 'support/fake_coach_repository.dart';

/// A variation pick on a past record must NAME the variation it now has the
/// moment the write lands (2026-10-25). The row stores only the id; the name
/// comes from `dim_variation`, and the old patch carried the PREVIOUS name
/// forward — so Done flipped the cell to read-only still naming the variation
/// the set no longer had, until the record was reopened.
class _FakeSessionRepo extends Fake implements SessionRepository {
  /// Every row in `dim_variation`, archived ones included — what the two
  /// joined reads (`loadSetsForSession`, the timeline) resolve names from.
  final dimNames = <String, String>{'v1': 'Chest', 'v2': 'Back'};

  /// Raw fact rows — ids only, exactly what the table stores.
  final rows = <String, SessionExerciseSet>{};
  bool timelineHoldsThisSession = true;
  int updateSetCalls = 0;

  SessionExerciseSet rawRow(String setId, {String? variationId}) =>
      SessionExerciseSet(
        sessionExerciseSetId: setId,
        sessionExerciseId: 'se1',
        sessionId: 'w1',
        userId: 'u1',
        exerciseId: 'ex1',
        setNumber: 1,
        weight: 50,
        reps: const [5],
        variationId: variationId,
      );

  /// The join the real reads perform: the id plus its dim name.
  SessionExerciseSet hydrated(SessionExerciseSet r) => SessionExerciseSet(
    sessionExerciseSetId: r.sessionExerciseSetId,
    sessionExerciseId: r.sessionExerciseId,
    sessionId: r.sessionId,
    userId: r.userId,
    exerciseId: r.exerciseId,
    variationId: r.variationId,
    variationName: r.variationId == null ? null : dimNames[r.variationId],
    setNumber: r.setNumber,
    weight: r.weight,
    reps: r.reps,
    notes: r.notes,
  );

  @override
  Future<Session?> fetchSession(String sessionId) async => Session(
    sessionId: 'w1',
    userId: 'u1',
    createdDatetime: DateTime(2026, 10, 10),
    endDatetime: DateTime(2026, 10, 10, 10),
  );

  @override
  Future<void> updateSessionNotes(
    String sessionId, {
    String? preNotes,
    String? postNotes,
    int? preFeeling,
    int? postFeeling,
  }) async {}

  @override
  Future<List<SessionExercise>> loadSessionExercises(String sessionId) async =>
      [
        const SessionExercise(
          sessionExerciseId: 'se1',
          sessionId: 'w1',
          userId: 'u1',
          exerciseOrder: 1,
          exerciseId: 'ex1',
        ),
      ];

  @override
  Future<List<SessionExerciseSet>> loadSetsForSession(String sessionId) async =>
      [for (final r in rows.values) hydrated(r)];

  @override
  Future<void> updateSet(
    String setId, {
    double? weight,
    bool clearWeight = false,
    List<num>? reps,
    bool clearReps = false,
    String? variationId,
    bool clearVariation = false,
    String? notes,
    bool clearNotes = false,
    bool isDeleted = false,
    bool clearIsDeleted = false,
  }) async {
    updateSetCalls++;
    // The real repo invalidates the shared cache on every fact write.
    PastSetsTimelineCache.instance.invalidate();
    final r = rows[setId]!;
    rows[setId] = SessionExerciseSet(
      sessionExerciseSetId: r.sessionExerciseSetId,
      sessionExerciseId: r.sessionExerciseId,
      sessionId: r.sessionId,
      userId: r.userId,
      exerciseId: r.exerciseId,
      variationId: clearVariation ? null : (variationId ?? r.variationId),
      setNumber: r.setNumber,
      weight: clearWeight ? null : (weight ?? r.weight),
      reps: clearReps ? const [] : (reps ?? r.reps),
      notes: clearNotes ? null : (notes ?? r.notes),
    );
  }

  /// What the shared cache reads. A completed record's rows live here; an
  /// active session's cannot (the timeline only reads ended sessions).
  Future<List<PastSetRow>> timeline() async {
    if (!timelineHoldsThisSession) return [];
    return [
      for (final r in rows.values)
        PastSetRow(
          sessionExerciseSetId: r.sessionExerciseSetId,
          sessionExerciseId: r.sessionExerciseId,
          sessionId: r.sessionId,
          userId: r.userId,
          exerciseId: r.exerciseId,
          variationId: r.variationId,
          variationName: r.variationId == null
              ? null
              : dimNames[r.variationId],
          setNumber: r.setNumber,
          weight: r.weight,
          reps: r.reps,
          notes: r.notes,
          sessionCreatedDate: DateTime(2026, 10, 10, 10),
        ),
    ];
  }
}

class _FakeExerciseRepo extends Fake implements ExerciseRepository {
  _FakeExerciseRepo(this.catalog);

  /// The ACTIVE library — archived variations are absent here, though their
  /// dim rows still name old sets (2026-10-14).
  final List<CustomVariation> catalog;

  @override
  Future<Map<String, ExerciseDetail>> fetchExerciseDetailMap(
    String userId,
  ) async => {};

  @override
  Future<List<CustomVariation>> fetchVariations(String userId) async => catalog;
}

class _FakeLessonRepo extends Fake implements LessonRepository {
  @override
  Future<List<Lesson>> fetchLessons(String userId, String exerciseId) async =>
      [];
}

void main() {
  late _FakeSessionRepo repo;
  late List<CustomVariation> catalog;

  SessionDetailViewModel buildVm() => SessionDetailViewModel(
    coachRepo: FakeCoachRepository(),
    sessionRepo: repo,
    exerciseRepo: _FakeExerciseRepo(catalog),
    lessonRepo: _FakeLessonRepo(),
    userId: 'u1',
  );

  /// Loads the record twice, as the edit tests do: the first load starts the
  /// async reads against an empty DB, the second reads the seeded rows.
  void loadSeeded(SessionDetailViewModel vm, FakeAsync async) {
    vm.load('w1');
    async.flushMicrotasks();
    vm.load('w1');
    async.flushMicrotasks();
  }

  setUp(() {
    repo = _FakeSessionRepo();
    catalog = const [
      CustomVariation(variationId: 'v1', userId: 'u1', name: 'Chest'),
      CustomVariation(variationId: 'v2', userId: 'u1', name: 'Back'),
    ];
    PastSetsTimelineCache.loaderOverride = (u) => repo.timeline();
    PastSetsTimelineCache.instance.invalidate();
  });

  tearDown(() {
    PastSetsTimelineCache.loaderOverride = null;
    PastSetsTimelineCache.instance.invalidate();
  });

  test('a variation pick renames the row at once — Done shows the new name', () {
    fakeAsync((async) {
      final vm = buildVm();
      repo.rows['s1'] = repo.rawRow('s1', variationId: 'v1');
      loadSeeded(vm, async);
      expect(vm.state.value.setsFor(1).single.variationName, 'Chest');

      // Exactly what the row's `onVariationChanged` calls.
      vm.startEditing();
      vm.quickUpdateSet(
        repo.rows['s1']!,
        variationId: 'v2',
        immediate: true,
      );
      async.flushMicrotasks();
      expect(repo.updateSetCalls, 1);

      final shown = vm.state.value.setsFor(1).single;
      expect(shown.variationId, 'v2');
      expect(
        shown.variationName,
        'Back',
        reason: 'the grid names the variation it now has — not the old one',
      );
      final historyRow = vm.state.value.historyByExercise['ex1']!.first
          .sets
          .first;
      expect(
        historyRow.variationName,
        'Back',
        reason: 'the timeline copy inside state is patched just the same',
      );
      expect(
        vm.state.value.prEvents.single.variationName,
        'Back',
        reason: 'the PR feed names the variation the event was set with',
      );

      // Done: the record flips back to read-only over the same row.
      vm.saveNotes();
      async.flushMicrotasks();
      expect(vm.state.value.isEditing, isFalse);
      expect(
        vm.state.value.setsFor(1).single.variationName,
        'Back',
        reason: 'the read-only cell must not revert to the pre-edit name',
      );
      vm.dispose();
    });
  });

  test('clearing the variation clears its name too', () {
    fakeAsync((async) {
      final vm = buildVm();
      repo.rows['s1'] = repo.rawRow('s1', variationId: 'v1');
      loadSeeded(vm, async);

      vm.quickUpdateSet(
        repo.rows['s1']!,
        variationId: null,
        clearVariation: true,
        immediate: true,
      );
      async.flushMicrotasks();

      final shown = vm.state.value.setsFor(1).single;
      expect(shown.variationId, isNull);
      expect(
        shown.variationName,
        isNull,
        reason: 'no id, no name — the cell reads "No Variation"',
      );
      expect(
        vm.state.value.historyByExercise['ex1']!.first.sets.first.variationName,
        isNull,
      );
      vm.dispose();
    });
  });

  test('a row the timeline cannot hold takes its name from the catalogue', () {
    fakeAsync((async) {
      // An active session: its rows never ride the past-sets timeline.
      repo.timelineHoldsThisSession = false;
      final vm = buildVm();
      repo.rows['s1'] = repo.rawRow('s1', variationId: 'v1');
      loadSeeded(vm, async);

      vm.quickUpdateSet(
        repo.rows['s1']!,
        variationId: 'v2',
        immediate: true,
      );
      async.flushMicrotasks();

      expect(
        vm.state.value.setsFor(1).single.variationName,
        'Back',
        reason: 'the live catalogue names the pick when no timeline row can',
      );
      vm.dispose();
    });
  });

  test('an unchanged id keeps an archived variation’s snapshot name', () {
    fakeAsync((async) {
      repo.timelineHoldsThisSession = false;
      // The dim row still exists (the joined reads name it), but the
      // variation is archived, so the active catalogue no longer lists it.
      repo.dimNames['v9'] = 'Old Stuff';
      final vm = buildVm();
      repo.rows['s1'] = repo.rawRow('s1', variationId: 'v9');
      loadSeeded(vm, async);
      expect(vm.state.value.setsFor(1).single.variationName, 'Old Stuff');

      vm.quickUpdateSet(repo.rows['s1']!, weight: 60, immediate: true);
      async.flushMicrotasks();

      expect(
        vm.state.value.setsFor(1).single.variationName,
        'Old Stuff',
        reason: 'a weight edit must never blank a readable variation name',
      );
      vm.dispose();
    });
  });
}
