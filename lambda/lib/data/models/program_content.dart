import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'goal.dart';
import 'planned_session.dart';
import 'planned_session_exercise.dart';
import 'planned_session_exercise_set.dart';

/// An immutable snapshot of a program's contents — the JSON document a
/// completed review stores in `fact_program_review.snapshot_content`.
///
/// Deliberately a document rather than row copies. Three reasons: it is ONE
/// table to register in the three-place sync contract instead of three; a
/// deep history stays kilobytes rather than thousands of cold rows;
/// and it is immutable by construction — a document is one row, so it exists
/// or it doesn't, where a row-copy snapshot can be torn by a partial
/// transaction or a quarantined `ps_crud` op.
///
/// The `exercise_order` precedent for "don't store JSON" does not apply: that
/// was MUTABLE state re-read-modified on every reorder. This is write-once.
/// Mutable state belongs in columns; immutable snapshots belong in a document.
///
/// **Names are not embedded** — ids only, resolved live, exactly as
/// `20260826000000_snapshots_out_fks_in.sql` established for sessions.
/// Renaming an exercise therefore changes how old versions display, which is
/// consistent with every other surface in the app.
///
/// Each nested map carries the exact keys [PlannedSession.fromMap] /
/// [PlannedSessionExercise.fromMap] / [PlannedSessionExerciseSet.fromMap] read,
/// so [toSession] / [toExercise] / [toSet] produce real models and the viewer
/// renders through the EXISTING `SessionExerciseCard` / `SessionSetRow`.
/// Archive columns are omitted rather than written null: a snapshot only ever
/// captures active rows, so they are invariantly inactive, and every `fromMap`
/// tolerates the missing key.
class ProgramContent {
  const ProgramContent({
    this.schema = currentSchema,
    this.blocks = const [],
    this.sessions = const [],
    this.goals = const [],
  });

  /// Bump when the document shape changes incompatibly. [decode] refuses an
  /// unknown version rather than guessing at a shape it doesn't know.
  ///
  /// 2 added [goals]. Safe on the read side: a stored 1 decodes with none of
  /// them, which is exactly what it held — the key was simply not written yet.
  static const int currentSchema = 2;

  final int schema;
  final List<ContentBlock> blocks;

  /// In program order (the join row's global `sequence_order`), so a position
  /// in this list IS the workout's place in the program — which is what makes
  /// the diff's move detection meaningful.
  final List<ContentSession> sessions;

  /// Every goal the program owns, at both scopes — a block's targets are part
  /// of what the program is, and a review of a phase has to be able to say
  /// what that phase was chasing.
  final List<ContentGoal> goals;

  bool get isEmpty => sessions.isEmpty && blocks.isEmpty && goals.isEmpty;

  int get sessionCount => sessions.length;

  int get exerciseCount =>
      sessions.fold(0, (sum, s) => sum + s.exercises.length);

  int get setCount => sessions.fold(
      0, (sum, s) => sum + s.exercises.fold(0, (n, e) => n + e.sets.length));

  /// Deterministic serialization: keys are sorted recursively, so two
  /// logically identical documents produce byte-identical JSON (and therefore
  /// an identical [contentHash]) regardless of map insertion order.
  String encode() => jsonEncode(_canonical(toJson()));

  /// SHA-256 of [encode]. Used to detect "a review where nothing changed" and
  /// to let the UI prove a closed run's frozen record still matches.
  String get contentHash => sha256.convert(utf8.encode(encode())).toString();

  /// A short label like `a1b2c3d4` for compact display.
  String get shortHash => contentHash.substring(0, 8);

  Map<String, dynamic> toJson() => {
        'schema': schema,
        'blocks': blocks.map((b) => b.toMap()).toList(),
        'sessions': sessions.map((s) => s.toJson()).toList(),
        'goals': goals.map((g) => g.toMap()).toList(),
      };

  /// Throws [FormatException] on an unknown schema or malformed JSON — callers
  /// that must not crash read through the nullable snapshot getters on the
  /// record models, which swallow it and return null.
  static ProgramContent decode(String json) {
    final raw = jsonDecode(json);
    if (raw is! Map) {
      throw const FormatException('Snapshot content is not a JSON object');
    }
    final schema = raw['schema'];
    if (schema is! int || schema > currentSchema) {
      throw FormatException('Unsupported snapshot schema: $schema');
    }
    return ProgramContent(
      schema: schema,
      blocks: _mapList(raw['blocks'])
          .map(ContentBlock.fromMap)
          .toList(growable: false),
      sessions: _mapList(raw['sessions'])
          .map(ContentSession.fromJson)
          .toList(growable: false),
      // Absent in a schema-1 document, which held no goals at all.
      goals: _mapList(raw['goals'])
          .map(ContentGoal.fromMap)
          .toList(growable: false),
    );
  }

  /// Builds a snapshot from live rows, preserving [sessions]' given order.
  factory ProgramContent.fromRows({
    List<ContentBlock> blocks = const [],
    required List<ContentSession> sessions,
    List<ContentGoal> goals = const [],
  }) =>
      ProgramContent(blocks: blocks, sessions: sessions, goals: goals);
}

/// One block definition inside a snapshot. Empty until blocks ship — but the
/// key exists in schema 1 from the start so snapshots cut now stay readable
/// afterwards.
class ContentBlock {
  const ContentBlock({
    required this.blockId,
    required this.name,
    required this.blockOrder,
    this.notes,
    this.targetWeeks,
    this.targetDays,
    this.targetSessions,
  });

  final String blockId;
  final String name;
  final String? notes;
  final int blockOrder;
  final int? targetWeeks;
  final int? targetDays;
  final int? targetSessions;

  factory ContentBlock.fromMap(Map<String, dynamic> map) => ContentBlock(
        blockId: map['block_id'] as String,
        name: (map['name'] as String?) ?? '',
        notes: map['notes'] as String?,
        blockOrder: _toInt(map['block_order']) ?? 0,
        targetWeeks: _toInt(map['target_weeks']),
        targetDays: _toInt(map['target_days']),
        targetSessions: _toInt(map['target_sessions']),
      );

  Map<String, dynamic> toMap() => {
        'block_id': blockId,
        'name': name,
        'notes': notes,
        'block_order': blockOrder,
        'target_weeks': targetWeeks,
        'target_days': targetDays,
        'target_sessions': targetSessions,
      };
}

/// One goal inside a snapshot.
///
/// An id-only row like everything else here: the exercise is resolved live, so
/// renaming one changes how an old review reads, consistently with sessions.
///
/// A goal's scope is its [blockId] and it is stored as the scope rather than
/// the answer — null is the program's own, in force through every block
/// ([Goal.appliesDuring]'s rule). A snapshot that flattened it would have to
/// decide "in force" for a run it does not know about.
class ContentGoal {
  const ContentGoal({
    required this.goalId,
    required this.userId,
    this.blockId,
    this.exerciseId,
    this.variationId,
    this.targetWeight,
    this.targetReps,
    this.text,
  });

  final String goalId;
  final String userId;

  /// The block this goal belongs to; null for the program's own.
  final String? blockId;
  final String? exerciseId;
  final String? variationId;

  /// Numbers, unlike a planned set's free-text targets: a goal is a line the
  /// user crossed or did not, so there is nothing for "8-15" to mean.
  final num? targetWeight;
  final int? targetReps;
  final String? text;

  Map<String, dynamic> toMap() => {
        'goal_id': goalId,
        'user_id': userId,
        'block_id': blockId,
        'custom_exercise_id': exerciseId,
        'custom_variation_id': variationId,
        'target_weight': targetWeight,
        'target_reps': targetReps,
        'goal_text': text,
      };

  factory ContentGoal.fromMap(Map<String, dynamic> map) => ContentGoal(
        goalId: map['goal_id'] as String,
        userId: (map['user_id'] as String?) ?? '',
        blockId: map['block_id'] as String?,
        exerciseId: map['custom_exercise_id'] as String?,
        variationId: map['custom_variation_id'] as String?,
        targetWeight: _toNum(map['target_weight']),
        targetReps: _toInt(map['target_reps']),
        text: map['goal_text'] as String?,
      );

  /// The real model, for rendering through the shared goal widgets.
  ///
  /// [programId] is passed in: the document is one program's, so repeating its
  /// id on every goal would be bytes for a fact the reader already holds.
  Goal toGoal({String? programId}) => Goal(
        goalId: goalId,
        userId: userId,
        programId: programId,
        blockId: blockId,
        text: text,
        exerciseId: exerciseId,
        variationId: variationId,
        targetWeight: targetWeight,
        targetReps: targetReps,
      );
}

/// One workout inside a snapshot: the template row, its program link, and its
/// full content.
class ContentSession {
  const ContentSession({
    required this.sessionId,
    required this.userId,
    required this.name,
    required this.exercises,
    this.notes,
    this.createdDate,
    this.sequenceOrder,
    this.dayOfWeek,
    this.weekOffset,
    this.blockId,
  });

  final String sessionId;
  final String userId;
  final String name;
  final String? notes;
  final DateTime? createdDate;

  /// Schedule slots from the join row. Null when the workout had no link
  /// (which should not happen inside a program, but a snapshot must not
  /// assume).
  final int? sequenceOrder;
  final int? dayOfWeek;
  final int? weekOffset;
  final String? blockId;

  final List<ContentExercise> exercises;

  int get setCount =>
      exercises.fold(0, (sum, e) => sum + e.sets.length);

  /// The stored map is directly [PlannedSession.fromMap]-compatible
  /// (`user_id` is repeated per session rather than hoisted to the document —
  /// ~36 bytes each, in exchange for the viewer being a plain `fromMap` call).
  Map<String, dynamic> toSessionMap() => {
        'session_id': sessionId,
        'user_id': userId,
        'name': name,
        'notes': notes,
        'created_date': createdDate?.toUtc().toIso8601String(),
      };

  Map<String, dynamic> toJson() => {
        ...toSessionMap(),
        'link': {
          'sequence_order': sequenceOrder,
          'day_of_week': dayOfWeek,
          'week_offset': weekOffset,
          'block_id': blockId,
        },
        'exercises': exercises.map((e) => e.toJson()).toList(),
      };

  factory ContentSession.fromJson(Map<String, dynamic> map) {
    final link = map['link'];
    final linkMap = link is Map ? link : const {};
    return ContentSession(
      sessionId: map['session_id'] as String,
      userId: map['user_id'] as String,
      name: (map['name'] as String?) ?? '',
      notes: map['notes'] as String?,
      createdDate: map['created_date'] != null
          ? DateTime.tryParse('${map['created_date']}')
          : null,
      sequenceOrder: _toInt(linkMap['sequence_order']),
      dayOfWeek: _toInt(linkMap['day_of_week']),
      weekOffset: _toInt(linkMap['week_offset']),
      blockId: linkMap['block_id'] as String?,
      exercises: _mapList(map['exercises'])
          .map(ContentExercise.fromJson)
          .toList(growable: false),
    );
  }

  /// The real model, for rendering through the shared session widgets.
  PlannedSession toSession() => PlannedSession.fromMap(toSessionMap());
}

/// One exercise group inside a snapshotted workout.
class ContentExercise {
  const ContentExercise({
    required this.plannedExerciseId,
    required this.plannedSessionId,
    required this.userId,
    required this.exerciseOrder,
    required this.sets,
    this.exerciseId,
  });

  final String plannedExerciseId;
  final String plannedSessionId;
  final String userId;
  final String? exerciseId;
  final int exerciseOrder;
  final List<ContentSet> sets;

  Map<String, dynamic> toExerciseMap() => {
        'planned_exercise_id': plannedExerciseId,
        'planned_session_id': plannedSessionId,
        'user_id': userId,
        'custom_exercise_id': exerciseId,
        'exercise_order': exerciseOrder,
      };

  Map<String, dynamic> toJson() => {
        ...toExerciseMap(),
        'sets': sets.map((s) => s.toMap()).toList(),
      };

  factory ContentExercise.fromJson(Map<String, dynamic> map) => ContentExercise(
        plannedExerciseId: map['planned_exercise_id'] as String,
        plannedSessionId: map['planned_session_id'] as String,
        userId: map['user_id'] as String,
        exerciseId: map['custom_exercise_id'] as String?,
        exerciseOrder: _toInt(map['exercise_order']) ?? 0,
        sets: _mapList(map['sets']).map(ContentSet.fromMap).toList(growable: false),
      );

  PlannedSessionExercise toExercise() =>
      PlannedSessionExercise.fromMap(toExerciseMap());
}

/// One target set inside a snapshotted exercise group.
class ContentSet {
  const ContentSet({
    required this.plannedSetId,
    required this.plannedExerciseId,
    required this.plannedSessionId,
    required this.userId,
    required this.setNumber,
    this.variationId,
    this.targetWeight,
    this.targetReps,
    this.targetNotes,
  });

  final String plannedSetId;
  final String plannedExerciseId;
  final String plannedSessionId;
  final String userId;
  final String? variationId;
  final int setNumber;

  /// Free text by design — "60", "60-70", "AMRAP". A plan is a hint, not a
  /// contract, so these are never parsed as numbers.
  final String? targetWeight;
  final String? targetReps;
  final String? targetNotes;

  /// Compared field-by-field by the diff; order here is irrelevant since
  /// comparison is by id.
  Map<String, dynamic> toMap() => {
        'planned_set_id': plannedSetId,
        'planned_exercise_id': plannedExerciseId,
        'planned_session_id': plannedSessionId,
        'user_id': userId,
        'custom_variation_id': variationId,
        'set_number': setNumber,
        'target_weight': targetWeight,
        'target_reps': targetReps,
        'target_notes': targetNotes,
      };

  factory ContentSet.fromMap(Map<String, dynamic> map) => ContentSet(
        plannedSetId: map['planned_set_id'] as String,
        plannedExerciseId: map['planned_exercise_id'] as String,
        plannedSessionId: map['planned_session_id'] as String,
        userId: map['user_id'] as String,
        variationId: map['custom_variation_id'] as String?,
        setNumber: _toInt(map['set_number']) ?? 1,
        targetWeight: _asTargetText(map['target_weight']),
        targetReps: _asTargetText(map['target_reps']),
        targetNotes: map['target_notes'] as String?,
      );

  PlannedSessionExerciseSet toSet() =>
      PlannedSessionExerciseSet.fromMap(toMap());
}

/// Sorts map keys recursively so `jsonEncode` output is canonical.
dynamic _canonical(dynamic value) {
  if (value is Map) {
    final keys = value.keys.map((k) => '$k').toList()..sort();
    return <String, dynamic>{for (final k in keys) k: _canonical(value[k])};
  }
  if (value is List) return value.map(_canonical).toList();
  return value;
}

List<Map<String, dynamic>> _mapList(dynamic v) {
  if (v is! List) return const [];
  return v
      .whereType<Map>()
      .map((m) => m.cast<String, dynamic>())
      .toList(growable: false);
}

int? _toInt(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  return int.tryParse('$v');
}

num? _toNum(dynamic v) {
  if (v == null) return null;
  if (v is num) return v;
  return num.tryParse('$v');
}

/// Normalizes a target column to raw text, matching
/// `PlannedSessionExerciseSet._toTargetText` so a snapshot round-trips to the
/// same model the planner shows. Handles the legacy "60.0" and "[8,10]" forms.
String? _asTargetText(dynamic v) {
  if (v == null) return null;
  var s = '$v'.trim();
  if (s.isEmpty) return null;
  if (s.startsWith('[')) {
    try {
      final list = (jsonDecode(s) as List).cast<dynamic>();
      if (list.isEmpty) return null;
      return list.join(',');
    } catch (_) {
      return s;
    }
  }
  if (s.contains('.') && num.tryParse(s) != null) {
    s = s.replaceFirst(RegExp(r'\.0+$'), '');
  }
  return s;
}
