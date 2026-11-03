import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lambda/core/powersync/database.dart' as ps;
import 'package:lambda/core/powersync/schema.dart';
import 'package:lambda/core/utils/lambda_exception.dart';
import 'package:lambda/data/cache/past_sets_timeline_cache.dart';
import 'package:lambda/data/models/coach_assignment.dart';
import 'package:lambda/data/models/program_content.dart';
import 'package:lambda/data/repositories/coach_repository.dart';
import 'package:powersync/powersync.dart';

/// Coach authoring's data layer against a real local mirror (2026-10-26,
/// #24). The stream and the RLS policies are server-side and are verified
/// with two accounts; everything the client owns is here:
///
/// * an assignment's snapshot is built from the coach's template and carries
///   only the ids that workout uses;
/// * the athlete's accept resolves exercise and variation NAMES against their
///   own library (reuse → reactivate → create), copies the workout with fresh
///   ids in one transaction, and stamps the assignment;
/// * an unresolvable group (the coach deleted the exercise) is skipped, and an
///   unreadable document refuses with a sentence;
/// * decline and withdraw leave no copy;
/// * feedback is one row per (coach, session) — written, rewritten, deleted.
///
///   flutter test integration_test/coach_authoring_test.dart -d macos
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const coach = 'coach';
  const athlete = 'athlete';

  late Directory dir;
  late PowerSyncDatabase db;
  late CoachRepository repo;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('lambda_ps_coach');
    db = PowerSyncDatabase(schema: schema, path: '${dir.path}/test.db');
    await db.initialize();
    ps.swapDatabase(db);
    repo = CoachRepository();
    PastSetsTimelineCache.instance.invalidate();
  });

  tearDown(() async {
    PastSetsTimelineCache.instance.invalidate();
    await db.close();
    await dir.delete(recursive: true);
  });

  Future<void> insertExercise(String userId, String id, String name) =>
      db.execute(
        'INSERT INTO dim_exercise (id, custom_exercise_id, user_id, '
        'exercise_name, date_archived) VALUES (?, ?, ?, ?, ?)',
        [id, id, userId, name, null],
      );

  /// The coach's library and the template the tests assign: Bench (Pause on
  /// set 1), Squat, Nordic Curl — one group each, targets free text.
  Future<void> seedCoachTemplate() async {
    await db.execute(
      'INSERT INTO dim_user (id, user_id, user_name, user_lastname) '
      'VALUES (?, ?, ?, ?)',
      [coach, coach, 'Casey', 'Coach'],
    );
    await db.execute(
      'INSERT INTO dim_user (id, user_id, user_name, user_lastname) '
      'VALUES (?, ?, ?, ?)',
      [athlete, athlete, 'Alex', 'Athlete'],
    );
    await insertExercise(coach, 'c-ex-bench', 'Bench Press');
    await insertExercise(coach, 'c-ex-squat', 'Squat');
    await insertExercise(coach, 'c-ex-nordic', 'Nordic Curl');
    await db.execute(
      'INSERT INTO dim_variation (id, custom_variation_id, user_id, '
      'variation_name, date_archived) VALUES (?, ?, ?, ?, ?)',
      ['c-var-pause', 'c-var-pause', coach, 'Pause', null],
    );
    await db.execute(
      'INSERT INTO dim_planned_session '
      '(id, session_id, user_id, name, created_date) VALUES (?, ?, ?, ?, ?)',
      ['ws-1', 'ws-1', coach, 'Push A', '2026-10-20T09:00:00.000Z'],
    );
    for (final (index, (id, exercise)) in [
      ('pe-1', 'c-ex-bench'),
      ('pe-2', 'c-ex-squat'),
      ('pe-3', 'c-ex-nordic'),
    ].indexed) {
      await db.execute(
        'INSERT INTO dim_planned_session_exercise '
        '(id, planned_exercise_id, planned_session_id, user_id, '
        ' custom_exercise_id, exercise_order, is_archived) '
        'VALUES (?, ?, ?, ?, ?, ?, ?)',
        [id, id, 'ws-1', coach, exercise, index + 1, 0],
      );
    }
    for (final (index, (id, group, variation, weight, reps)) in [
      ('ps-1', 'pe-1', 'c-var-pause', '60', '5'),
      ('ps-2', 'pe-1', null, '8-15', 'AMRAP'),
      ('ps-3', 'pe-2', null, '100', '5'),
      ('ps-4', 'pe-3', null, null, '5'),
    ].indexed) {
      await db.execute(
        'INSERT INTO dim_planned_session_exercise_set '
        '(id, planned_set_id, planned_exercise_id, user_id, '
        ' custom_variation_id, set_number, target_weight, target_reps, '
        ' is_archived) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [id, id, group, coach, variation, index + 1, weight, reps, 0],
      );
    }
  }

  /// The athlete's library, as the coach's names should find it: Bench
  /// exists, Squat is archived, Pause exists — Nordic Curl does not.
  Future<void> seedAthleteLibrary() async {
    await insertExercise(athlete, 'a-ex-bench', 'Bench Press');
    await db.execute(
      'INSERT INTO dim_exercise (id, custom_exercise_id, user_id, '
      'exercise_name, date_archived) VALUES (?, ?, ?, ?, ?)',
      [
        'a-ex-squat',
        'a-ex-squat',
        athlete,
        'Squat',
        '2026-10-01T00:00:00.000Z',
      ],
    );
    await db.execute(
      'INSERT INTO dim_variation (id, custom_variation_id, user_id, '
      'variation_name, date_archived) VALUES (?, ?, ?, ?, ?)',
      ['a-var-pause', 'a-var-pause', athlete, 'Pause', null],
    );
  }

  Future<CoachAssignment> assignPushA({String? note}) async {
    final workouts = await repo.assignableWorkouts(coach);
    final assignment = await repo.createAssignment(
      coachId: coach,
      athleteId: athlete,
      workout: workouts.single,
      note: note,
    );
    return assignment;
  }

  test('the assignment freezes the workout and only the names it uses', () async {
    await seedCoachTemplate();

    final assignment = await assignPushA(note: 'Keep the bar path tight');

    expect(assignment.name, 'Push A');
    expect(assignment.note, 'Keep the bar path tight');
    expect(assignment.isPending, isTrue);

    final row = await db.get(
      'SELECT * FROM fact_coach_assignment WHERE assignment_id = ?',
      [assignment.assignmentId],
    );
    expect(row['coach_user_id'], coach);
    expect(row['athlete_user_id'], athlete);
    expect(row['planned_session_id'], 'ws-1');
    expect(row['accepted_date'], isNull);

    // The names map covers exactly the ids the snapshot holds.
    expect(assignment.exerciseNames, {
      'c-ex-bench': 'Bench Press',
      'c-ex-squat': 'Squat',
      'c-ex-nordic': 'Nordic Curl',
    });
    expect(assignment.variationNames, {'c-var-pause': 'Pause'});

    final content = ProgramContent.decode(assignment.snapshotContent);
    expect(content.sessions.single.name, 'Push A');
    expect(content.sessions.single.exercises.length, 3);
    expect(content.sessions.single.exercises.first.sets.length, 2);
  });

  test('accept copies the workout, remapping names into the athlete\'s library',
      () async {
    await seedCoachTemplate();
    await seedAthleteLibrary();
    final assignment = await assignPushA();

    final copy = await repo.acceptAssignment(athlete, assignment);

    expect(copy.name, 'Push A');
    expect(copy.userId, athlete);
    expect(copy.isCoachAssigned, isTrue);
    expect(copy.coachAssignmentId, assignment.assignmentId);

    final session = await db.get(
      'SELECT * FROM dim_planned_session WHERE session_id = ?',
      [copy.sessionId],
    );
    expect(session['user_id'], athlete);
    expect(session['name'], 'Push A');
    expect(session['coach_assignment_id'], assignment.assignmentId);
    expect(session['base_session_id'], isNull);

    final groups = await db.getAll(
      'SELECT * FROM dim_planned_session_exercise '
      'WHERE planned_session_id = ? ORDER BY exercise_order',
      [copy.sessionId],
    );
    expect(groups.length, 3);
    // Existing name reused; archived name reactivated; unknown name created.
    expect(groups[0]['custom_exercise_id'], 'a-ex-bench');
    expect(groups[1]['custom_exercise_id'], 'a-ex-squat');
    final nordicId = groups[2]['custom_exercise_id'] as String;
    expect(nordicId, isNot('c-ex-nordic'));
    final nordic = await db.get(
      'SELECT * FROM dim_exercise WHERE custom_exercise_id = ?',
      [nordicId],
    );
    expect(nordic['exercise_name'], 'Nordic Curl');
    expect(nordic['user_id'], athlete);
    final squat = await db.get(
      "SELECT * FROM dim_exercise WHERE custom_exercise_id = 'a-ex-squat'",
    );
    expect(squat['date_archived'], isNull, reason: 'the accept reactivates it');

    final sets = await db.getAll(
      'SELECT * FROM dim_planned_session_exercise_set '
      'WHERE planned_exercise_id IN '
      '(${List.filled(groups.length, '?').join(', ')}) '
      'ORDER BY planned_exercise_id, set_number',
      [for (final g in groups) g['planned_exercise_id']],
    );
    expect(sets.length, 4);
    final benchSets = sets
        .where((s) => s['planned_exercise_id'] == groups[0]['planned_exercise_id'])
        .toList();
    expect(benchSets.first['custom_variation_id'], 'a-var-pause');
    expect(benchSets.first['target_weight'], '60');
    expect(benchSets.first['target_reps'], '5');
    expect(benchSets.last['custom_variation_id'], isNull);
    expect(benchSets.last['target_weight'], '8-15');
    expect(benchSets.last['target_reps'], 'AMRAP');

    final stamped = await db.get(
      'SELECT * FROM fact_coach_assignment WHERE assignment_id = ?',
      [assignment.assignmentId],
    );
    expect(stamped['accepted_date'], isNotNull);
    expect(stamped['athlete_planned_session_id'], copy.sessionId);

    // The coach's template is untouched: same ids, same groups.
    final coachGroups = await db.getAll(
      'SELECT * FROM dim_planned_session_exercise '
      "WHERE planned_session_id = 'ws-1' ORDER BY exercise_order",
    );
    expect(coachGroups.map((g) => g['custom_exercise_id']), [
      'c-ex-bench',
      'c-ex-squat',
      'c-ex-nordic',
    ]);
  });

  test('a group whose name the coach cannot resolve is skipped', () async {
    await seedCoachTemplate();
    // The coach deleted the exercise from their library after adding it to
    // the template: the snapshot still names the id, the names map cannot.
    await db.execute(
      "DELETE FROM dim_exercise WHERE custom_exercise_id = 'c-ex-nordic'",
    );
    await seedAthleteLibrary();
    final assignment = await assignPushA();
    expect(assignment.exerciseNames.containsKey('c-ex-nordic'), isFalse);

    final copy = await repo.acceptAssignment(athlete, assignment);

    final groups = await db.getAll(
      'SELECT * FROM dim_planned_session_exercise '
      'WHERE planned_session_id = ? ORDER BY exercise_order',
      [copy.sessionId],
    );
    expect(groups.length, 2);
    expect(groups.map((g) => g['custom_exercise_id']), [
      'a-ex-bench',
      'a-ex-squat',
    ]);
  });

  test('an unreadable snapshot refuses with a sentence', () async {
    final broken = CoachAssignment(
      assignmentId: 'as-broken',
      coachUserId: coach,
      athleteUserId: athlete,
      plannedSessionId: 'ws-1',
      name: 'Push A',
      snapshotContent: 'not a document',
      createdDate: DateTime.utc(2026, 10, 24),
    );

    await expectLater(
      repo.acceptAssignment(athlete, broken),
      throwsA(
        isA<LambdaException>().having(
          (e) => e.message,
          'message',
          contains("couldn't be read"),
        ),
      ),
    );
  });

  test('decline stamps the row and copies nothing; withdraw removes it',
      () async {
    await seedCoachTemplate();
    await seedAthleteLibrary();
    final toDecline = await assignPushA();
    final toWithdraw = await repo.createAssignment(
      coachId: coach,
      athleteId: athlete,
      workout: (await repo.assignableWorkouts(coach)).single,
    );

    await repo.declineAssignment(athlete, toDecline);

    final declined = await db.get(
      'SELECT * FROM fact_coach_assignment WHERE assignment_id = ?',
      [toDecline.assignmentId],
    );
    expect(declined['declined_date'], isNotNull);
    expect(declined['accepted_date'], isNull);

    await repo.withdrawAssignment(coach, toWithdraw);
    final remaining = await db.getAll('SELECT * FROM fact_coach_assignment');
    expect(remaining.length, 1);
    expect(remaining.single['assignment_id'], toDecline.assignmentId);

    final copies = await db.getAll(
      'SELECT * FROM dim_planned_session WHERE user_id = ?',
      [athlete],
    );
    expect(copies, isEmpty, reason: 'neither side produced a workout');
  });

  test('feedback is one row per (coach, session), rewritten in place', () async {
    await seedCoachTemplate();

    final first = await repo.saveFeedback(
      coachId: coach,
      athleteId: athlete,
      sessionId: 's-1',
      body: '  Great depth  ',
    );
    expect(first.body, 'Great depth');

    final watched = await repo.watchFeedback('s-1').first;
    expect(watched.single.body, 'Great depth');

    final rewritten = await repo.saveFeedback(
      coachId: coach,
      athleteId: athlete,
      sessionId: 's-1',
      body: 'Even better depth',
    );
    expect(rewritten.feedbackId, first.feedbackId);

    final rows = await db.getAll('SELECT * FROM fact_coach_feedback');
    expect(rows.length, 1);
    expect(rows.single['body'], 'Even better depth');
    expect(rows.single['edited_date'], isNotNull);

    final names = await repo.userNames([coach]);
    expect(names[coach], 'Casey Coach');

    await repo.deleteFeedback(coach, first.feedbackId);
    expect(await db.getAll('SELECT * FROM fact_coach_feedback'), isEmpty);
  });

  test('an empty note is refused before it reaches the row', () async {
    await seedCoachTemplate();

    await expectLater(
      repo.saveFeedback(
        coachId: coach,
        athleteId: athlete,
        sessionId: 's-1',
        body: '   ',
      ),
      throwsA(
        isA<LambdaException>().having(
          (e) => e.message,
          'message',
          'Write something first.',
        ),
      ),
    );
    expect(await db.getAll('SELECT * FROM fact_coach_feedback'), isEmpty);
  });
}
