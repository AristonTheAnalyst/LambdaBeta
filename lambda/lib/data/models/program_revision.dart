import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'planned_session.dart';
import 'planned_session_exercise.dart';
import 'planned_session_exercise_set.dart';

/// One immutable version of a program's contents (`fact_program_revision`).
///
/// Cut at the first save, at every review, and just before a block or the
/// program stops running. Never updated after insert.
class ProgramRevision {
  const ProgramRevision({
    required this.revisionId,
    required this.userId,
    required this.programId,
    required this.revisionNumber,
    required this.reason,
    required this.contentJson,
    required this.contentHash,
    required this.createdDate,
    this.blockId,
    this.blockRunId,
    this.reviewId,
    this.sessionCount = 0,
    this.exerciseCount = 0,
    this.setCount = 0,
  });

  final String revisionId;
  final String userId;
  final String programId;

  /// The block that was active when this was cut — CONTEXT, not scope. A
  /// revision is always a whole-program snapshot; this only lets the history
  /// view filter.
  final String? blockId;

  /// Plain refs (no FK): revisions and reviews reference each other, and a
  /// circular FK pair would break PowerSync upload ordering. Neither runs nor
  /// reviews are ever deleted, so nothing can dangle.
  final String? blockRunId;
  final String? reviewId;

  /// 1-based, unique per program. "Version N" in the UI.
  final int revisionNumber;

  /// One of [kRevisionCreated], [kRevisionReview], [kRevisionBlockEnd],
  /// [kRevisionProgramEnd], [kRevisionManual].
  final String reason;

  final String contentJson;
  final String contentHash;
  final DateTime createdDate;

  // Flat projections written at capture time so the timeline renders without
  // parsing [contentJson].
  final int sessionCount;
  final int exerciseCount;
  final int setCount;

  bool get isRunEnd =>
      reason == kRevisionBlockEnd || reason == kRevisionProgramEnd;

  /// Decoded contents, or null if the stored document can't be read (an
  /// unknown schema written by a newer build). Callers render a placeholder
  /// rather than throwing — an unreadable old version must not crash the
  /// history screen.
  ProgramRevisionContent? get content {
    try {
      return ProgramRevisionContent.decode(contentJson);
    } catch (_) {
      return null;
    }
  }

  factory ProgramRevision.fromMap(Map<String, dynamic> map) => ProgramRevision(
        revisionId: map['revision_id'] as String,
        userId: map['user_id'] as String,
        programId: map['program_id'] as String,
        blockId: map['block_id'] as String?,
        blockRunId: map['block_run_id'] as String?,
        reviewId: map['review_id'] as String?,
        revisionNumber: _toInt(map['revision_number']) ?? 0,
        reason: (map['reason'] as String?) ?? kRevisionManual,
        contentJson: (map['content_json'] as String?) ?? '{}',
        contentHash: (map['content_hash'] as String?) ?? '',
        sessionCount: _toInt(map['session_count']) ?? 0,
        exerciseCount: _toInt(map['exercise_count']) ?? 0,
        setCount: _toInt(map['set_count']) ?? 0,
        createdDate:
            DateTime.tryParse('${map['created_date']}')?.toLocal() ??
                DateTime.now(),
      );

  static int? _toInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    return int.tryParse('$v');
  }
}

/// Why a revision was cut. Persisted as text; the DB has a CHECK constraint
/// listing exactly these.
const kRevisionCreated = 'created';
const kRevisionReview = 'review';
const kRevisionBlockEnd = 'block_end';
const kRevisionProgramEnd = 'program_end';
const kRevisionManual = 'manual';

const kRevisionReasons = <String>[
  kRevisionCreated,
  kRevisionReview,
  kRevisionBlockEnd,
  kRevisionProgramEnd,
  kRevisionManual,
];

/// Human label for a [ProgramRevision.reason] — the chip on a version, in the
/// timeline and on the version itself.
String revisionReasonLabel(String reason) => switch (reason) {
      kRevisionCreated => 'Created',
      kRevisionReview => 'Review',
      kRevisionBlockEnd => 'Block end',
      kRevisionProgramEnd => 'Program end',
      kRevisionManual => 'Saved',
      _ => 'Version',
    };

/// An immutable snapshot of a program's contents — the JSON document stored in
/// `fact_program_revision.content_json`.
///
/// Deliberately a document rather than row copies. Three reasons: it is ONE
/// table to register in the three-place sync contract instead of three; a
/// multi-revision history stays kilobytes rather than thousands of cold rows;
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
class ProgramRevisionContent {
  const ProgramRevisionContent({
    this.schema = currentSchema,
    this.blocks = const [],
    this.sessions = const [],
  });

  /// Bump when the document shape changes incompatibly. [decode] refuses an
  /// unknown version rather than guessing at a shape it doesn't know.
  static const int currentSchema = 1;

  final int schema;
  final List<RevisionBlock> blocks;

  /// In program order (the join row's global `sequence_order`), so a position
  /// in this list IS the workout's place in the program — which is what makes
  /// the diff's move detection meaningful.
  final List<RevisionSession> sessions;

  bool get isEmpty => sessions.isEmpty && blocks.isEmpty;

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
      };

  /// Throws [FormatException] on an unknown schema or malformed JSON — callers
  /// that must not crash should use [ProgramRevision.content], which swallows
  /// it and returns null.
  static ProgramRevisionContent decode(String json) {
    final raw = jsonDecode(json);
    if (raw is! Map) {
      throw const FormatException('Revision content is not a JSON object');
    }
    final schema = raw['schema'];
    if (schema is! int || schema > currentSchema) {
      throw FormatException('Unsupported revision schema: $schema');
    }
    return ProgramRevisionContent(
      schema: schema,
      blocks: _mapList(raw['blocks'])
          .map(RevisionBlock.fromMap)
          .toList(growable: false),
      sessions: _mapList(raw['sessions'])
          .map(RevisionSession.fromJson)
          .toList(growable: false),
    );
  }

  /// Builds a snapshot from live rows, preserving [sessions]' given order.
  factory ProgramRevisionContent.fromRows({
    List<RevisionBlock> blocks = const [],
    required List<RevisionSession> sessions,
  }) =>
      ProgramRevisionContent(blocks: blocks, sessions: sessions);
}

/// One block definition inside a snapshot. Empty until blocks ship — but the
/// key exists in schema 1 from the start so revisions cut now stay readable
/// afterwards.
class RevisionBlock {
  const RevisionBlock({
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

  factory RevisionBlock.fromMap(Map<String, dynamic> map) => RevisionBlock(
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

/// One workout inside a snapshot: the template row, its program link, and its
/// full content.
class RevisionSession {
  const RevisionSession({
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

  final List<RevisionExercise> exercises;

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

  factory RevisionSession.fromJson(Map<String, dynamic> map) {
    final link = map['link'];
    final linkMap = link is Map ? link : const {};
    return RevisionSession(
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
          .map(RevisionExercise.fromJson)
          .toList(growable: false),
    );
  }

  /// The real model, for rendering through the shared session widgets.
  PlannedSession toSession() => PlannedSession.fromMap(toSessionMap());
}

/// One exercise group inside a snapshotted workout.
class RevisionExercise {
  const RevisionExercise({
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
  final List<RevisionSet> sets;

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

  factory RevisionExercise.fromJson(Map<String, dynamic> map) => RevisionExercise(
        plannedExerciseId: map['planned_exercise_id'] as String,
        plannedSessionId: map['planned_session_id'] as String,
        userId: map['user_id'] as String,
        exerciseId: map['custom_exercise_id'] as String?,
        exerciseOrder: _toInt(map['exercise_order']) ?? 0,
        sets: _mapList(map['sets']).map(RevisionSet.fromMap).toList(growable: false),
      );

  PlannedSessionExercise toExercise() =>
      PlannedSessionExercise.fromMap(toExerciseMap());
}

/// One target set inside a snapshotted exercise group.
class RevisionSet {
  const RevisionSet({
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

  factory RevisionSet.fromMap(Map<String, dynamic> map) => RevisionSet(
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
