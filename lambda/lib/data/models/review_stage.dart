import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'planned_session.dart';

/// The version marker on the stored document. A row written by a newer build
/// reads as no stage at all rather than a half-understood one — the same
/// doctrine as `ProgramContent.decode`.
const int kReviewStageVersion = 1;

/// One workout as a review pass has left it: a copy of its planned-session row
/// and of every exercise group and target set under it, archived rows
/// included.
///
/// The rows are kept as the maps the models already round-trip
/// (`toMap`/`fromMap`), which is what makes staging a workout one deep read at
/// its first write and a JSON document at rest — no second schema to keep in
/// step with the dims.
class StagedWorkout {
  StagedWorkout({
    required this.session,
    required this.exercises,
    required this.sets,
  });

  /// The `dim_planned_session` row, shaped as [PlannedSession.toMap].
  final Map<String, dynamic> session;

  /// Exercise groups by `planned_exercise_id`, and target sets by
  /// `planned_set_id` — both every row the workout holds, archived included.
  final Map<String, Map<String, dynamic>> exercises;
  final Map<String, Map<String, dynamic>> sets;

  String get sessionId => session['session_id'] as String;
  String get name => session['name'] as String;
  String? get notes => session['notes'] as String?;
  bool get isArchived => session['date_archived'] != null;

  /// The workout as the editor reads it — null when the pass has archived it,
  /// mirroring `fetchPlannedSessionById`'s active-row filter.
  PlannedSession? get model =>
      isArchived ? null : PlannedSession.fromMap(session);

  Map<String, dynamic> toJson() => {
    'session': session,
    'exercises': exercises.values.toList(growable: false),
    'sets': sets.values.toList(growable: false),
  };

  static StagedWorkout? fromJson(Object? json) {
    if (json is! Map) return null;
    final session = json['session'];
    if (session is! Map<String, dynamic>) return null;
    if (session['session_id'] is! String) return null;
    final exercises = <String, Map<String, dynamic>>{};
    for (final row in (json['exercises'] as List? ?? const [])) {
      if (row is Map<String, dynamic> && row['planned_exercise_id'] is String) {
        exercises[row['planned_exercise_id'] as String] = row;
      }
    }
    final sets = <String, Map<String, dynamic>>{};
    for (final row in (json['sets'] as List? ?? const [])) {
      if (row is Map<String, dynamic> && row['planned_set_id'] is String) {
        sets[row['planned_set_id'] as String] = row;
      }
    }
    return StagedWorkout(session: session, exercises: exercises, sets: sets);
  }
}

/// The workouts a review pass has edited so far, as a document on the review
/// row's dormant `proposed_content` column (2026-10-27).
///
/// A pass is a comparison, not an edit session: its changes are **staged** —
/// written here, on the review, rather than onto the plan — and only land on
/// the live dim rows when the pass finishes. Cancelling the pass deletes the
/// review row and with it everything the pass staged, so a cancel is a true
/// discard and the plan never moved.
///
/// A workout enters the document at its **first write** and keeps every row it
/// held at that moment (archived groups and sets included), so the document is
/// the whole workout, not a diff — applying it is a row-for-row write that
/// needs no reading back. Workouts the pass only looked at stay out, and keep
/// reading live.
class ReviewStage {
  ReviewStage({Map<String, StagedWorkout>? workouts})
    : workouts = workouts ?? <String, StagedWorkout>{};

  /// Staged workouts by planned-session id, in the order they were first
  /// edited.
  final Map<String, StagedWorkout> workouts;

  bool get isEmpty => workouts.isEmpty;

  bool get isNotEmpty => workouts.isNotEmpty;

  bool contains(String sessionId) => workouts.containsKey(sessionId);

  StagedWorkout? workout(String sessionId) => workouts[sessionId];

  /// The stored document. Key order is insertion order, so an unchanged stage
  /// encodes byte-identically — [contentHash] is meaningful.
  String encode() => jsonEncode({
    'stage': kReviewStageVersion,
    'workouts': {
      for (final entry in workouts.entries) entry.key: entry.value.toJson(),
    },
  });

  String get contentHash => sha256.convert(utf8.encode(encode())).toString();

  /// The stage a review row carries — null when there is none, when the
  /// document is unreadable, or when it was written by a newer build. An
  /// unreadable stage must never crash the pass that resumes it: a pass with
  /// no stage is simply a pass with nothing edited yet.
  static ReviewStage? tryDecode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final json = jsonDecode(raw);
      if (json is! Map || json['stage'] != kReviewStageVersion) return null;
      final workouts = <String, StagedWorkout>{};
      for (final entry in (json['workouts'] as Map? ?? const {}).entries) {
        final key = entry.key;
        if (key is! String) continue;
        final workout = StagedWorkout.fromJson(entry.value);
        if (workout == null) continue;
        workouts[key] = workout;
      }
      return ReviewStage(workouts: workouts);
    } catch (_) {
      return null;
    }
  }
}
