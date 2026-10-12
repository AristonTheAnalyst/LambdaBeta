import 'dart:convert';

import 'program_content.dart';

/// What a review examines — on rows written **before** reviews were re-scoped
/// to a set of workouts (2026-10-06). New rows carry their set in
/// [ProgramReview.sessionIdsJson] instead, and nothing in the app branches on
/// this any more; it survives to read the old rows' legacy columns.
enum ReviewScopeKind { program, block, session }

/// A checkpoint on a program's run (`fact_program_review`).
///
/// One row shape, three flavours — a plain [kReviewKindReview], a
/// [kReviewKindChange] carrying a proposed edit, and the automatic
/// [kReviewKindClose] written when a run ends. They differ only in which fields
/// are filled, so they share a table and a `kind`.
///
/// There is no `status` column and no derived status enum to keep in sync:
/// [isOpen], [isDue] and [isCompleted] all read the same nullable timestamp, so
/// they cannot disagree with each other.
class ProgramReview {
  const ProgramReview({
    required this.reviewId,
    required this.userId,
    this.programId,
    required this.kind,
    required this.createdDate,
    this.blockId,
    this.sessionId,
    this.programRunId,
    this.title,
    this.notes,
    this.scheduledFor,
    this.completedDate,
    this.outcome,
    this.proposedContent,
    this.proposedHash,
    this.snapshotContent,
    this.snapshotHash,
    this.baselineContent,
    this.baselineHash,
    this.exerciseNotesJson,
    this.achievementsJson,
    this.sessionIdsJson,
    this.reviewedSessionsJson,
    this.goalIdsJson,
    this.workoutNotesJson,
  });

  final String reviewId;
  final String userId;

  /// The program this review belongs to, or **null for a standalone review** —
  /// a pass over a set of workouts and goals that was never one program's to
  /// own. Standalone is the only sense the app starts reviews in while the
  /// concept is being settled (the Library's Reviews tab); the program surfaces
  /// are retired from the UI with their plumbing kept. See [isStandalone].
  final String? programId;

  /// True when this review was started on its own — workouts and goals picked
  /// directly, no program in the picture.
  bool get isStandalone => programId == null;

  /// The review's **legacy** BLOCK scope: null = not a block review, else the
  /// block it examined. Never set together with [sessionId]. Rows written
  /// since reviews were re-scoped leave it null and carry a set instead
  /// ([sessionIdsJson]).
  final String? blockId;

  /// The review's **legacy** SESSION scope: the `planned_session_id` examined,
  /// or null. Never set together with [blockId] — the server has a CHECK for
  /// it. Superseded by [sessionIdsJson].
  ///
  /// This is the plan (a `dim_planned_session`), not a logged session: a review
  /// is a pass over what you intend to do, and what you intend is what you edit.
  final String? sessionId;

  final String? programRunId;

  /// One of [kReviewKindReview], [kReviewKindChange], [kReviewKindClose].
  final String kind;

  final String? title;
  final String? notes;

  /// When the user asked to be reminded. Null = an unscheduled checkpoint —
  /// either one taken on the spot, or an automatic close.
  final DateTime? scheduledFor;

  /// Null = open. The single source of truth for a review's status.
  final DateTime? completedDate;

  /// One of [kOutcomeReviewed], [kOutcomeApplied], [kOutcomeDismissed],
  /// [kOutcomeClosed]. Non-null exactly when [completedDate] is — the DB has a
  /// CHECK constraint pairing them, so an outcome can never be orphaned from
  /// the completion it describes.
  final String? outcome;

  /// A proposed edit, kind [kReviewKindChange] only. Mutable until acted on —
  /// this is a PROPOSAL, never a snapshot. Nothing copies it into live rows:
  /// the review container opens the normal editor, and the user makes the
  /// change themselves.
  final String? proposedContent;
  final String? proposedHash;

  /// The plan as it actually stood when this review completed — a
  /// `ProgramContent` document, the same one the retired revision table held.
  /// Null while the review is open, and on reviews completed before the
  /// snapshot moved onto this row.
  ///
  /// Always a WHOLE-PROGRAM document: the scope says what was being looked at,
  /// not what was copied. That is what lets a session review's snapshot be
  /// diffed against the program review that followed it.
  final String? snapshotContent;
  final String? snapshotHash;

  /// The plan **as found** — captured when the review STARTED, so a comparison
  /// exists even on the first review of a thing, when no previous finished
  /// snapshot does. Always a whole-program document, same shape as
  /// [snapshotContent].
  ///
  /// Written once and never overwritten: a baseline that moved with the user's
  /// edits would compare the plan to itself and read "identical" forever.
  final String? baselineContent;
  final String? baselineHash;

  /// Per-exercise notes taken DURING the review, keyed by the planned
  /// exercise's id: `{"<planned_exercise_id>": "<note>"}`.
  ///
  /// Part of the review's record only — not written to the exercise, not
  /// pinned as lessons, and not carried into the next review.
  final String? exerciseNotesJson;

  /// The frozen record of what the run achieved, written by `closeRun`
  /// together with [kOutcomeClosed]. The one deliberate exception to deriving
  /// on read: a finished block's record must not change because someone later
  /// corrected a set.
  final String? achievementsJson;

  /// The **set scope**: the ordered planned-session ids this review covers, as
  /// a JSON array (`["s1","s2"]`). Null on rows written before reviews were
  /// re-scoped — those name their one thing the old way and are resolved to a
  /// set by [sessionsIn].
  final String? sessionIdsJson;

  /// The workouts finished inside this pass so far, keyed by id:
  /// `{"<planned_session_id>": "<ISO timestamp>"}`. Written one entry at a
  /// time as each workout is marked done, and kept after the review completes
  /// as the record of what the pass actually walked.
  final String? reviewedSessionsJson;

  /// The **goal set**: the ordered goal ids this review covers, as a JSON
  /// array (`["g1","g3"]`). Null when the pass picked no goals — and on every
  /// row written before reviews could carry them.
  final String? goalIdsJson;

  /// Workout-level notes taken DURING the review, keyed by the planned
  /// session's id: `{"<planned_session_id>": "<note>"}` — the sibling of
  /// [exerciseNotesJson]. Part of the review's record only, like the exercise
  /// notes: not written to the workout, not carried into the next review.
  final String? workoutNotesJson;

  final DateTime createdDate;

  bool get isOpen => completedDate == null;

  bool get isCompleted => completedDate != null;

  bool get hasProposal => proposedContent != null;

  bool get isClosed => kind == kReviewKindClose;

  /// How a row written before reviews were re-scoped names its one thing.
  /// New rows report [ReviewScopeKind.program] — meaningless for them, which
  /// is why nothing branches on it any more.
  ReviewScopeKind get scopeKind {
    if (sessionId != null) return ReviewScopeKind.session;
    if (blockId != null) return ReviewScopeKind.block;
    return ReviewScopeKind.program;
  }

  /// The ids this review covers **as stored** — the JSON array, or null on a
  /// legacy row. Unreadable JSON reads as null (a legacy row), which resolves
  /// from the old columns rather than rendering a review of nothing.
  List<String>? get storedSessionIds => _decodeIds(sessionIdsJson);

  /// The goals this review covers **as stored** — the ordered id array, or
  /// null when the pass picked none. Unreadable JSON reads as null (no goals),
  /// the same contract as [storedSessionIds].
  List<String>? get storedGoalIds => _decodeIds(goalIdsJson);

  /// The workouts marked done inside this pass, decoded — an id → when.
  /// Unreadable blobs read as "none done yet".
  Map<String, DateTime> get reviewedSessions {
    final json = reviewedSessionsJson;
    if (json == null) return const {};
    try {
      final decoded = jsonDecode(json);
      if (decoded is! Map) return const {};
      return {
        for (final entry in decoded.entries)
          if (DateTime.tryParse('${entry.value}') case final at?)
            '${entry.key}': at.toLocal(),
      };
    } catch (_) {
      return const {};
    }
  }

  /// The planned-session ids this review covers, resolved against [links] —
  /// the program's (sessionId, blockId) pairs, read from the live join rows
  /// for an open review or from the row's own snapshot for a completed one.
  ///
  /// Falls through until it has something, so every row ever written
  /// resolves: the stored set (minus ids the program no longer has), else its
  /// one session, else its block's sessions, else every session of the
  /// program — where the close rows, whose scope deliberately is everything,
  /// land too.
  ///
  /// A **standalone** review resolves to its stored set and nothing else. It
  /// never had a program to fall back to, so an empty or missing stored set
  /// means an empty pass — falling through would resolve "every session of"
  /// a program that does not exist.
  List<String> sessionsIn(List<({String sessionId, String? blockId})> links) {
    if (isStandalone) return storedSessionIds ?? const [];
    final known = {for (final l in links) l.sessionId};
    final stored = storedSessionIds;
    if (stored != null) {
      final alive = [for (final id in stored) if (known.contains(id)) id];
      if (alive.isNotEmpty) return alive;
    }
    final single = sessionId;
    if (single != null) return [single];
    final block = blockId;
    if (block != null) {
      final inBlock = [
        for (final l in links)
          if (l.blockId == block) l.sessionId,
      ];
      if (inBlock.isNotEmpty) return inBlock;
    }
    return [for (final l in links) l.sessionId];
  }

  bool get hasSnapshot => snapshotContent != null;

  bool get hasBaseline => baselineContent != null;

  /// The baseline, decoded — or null when there is none, or when the stored
  /// document was written by a newer build than this one. Unreadable reads as
  /// "nothing recorded" rather than crashing the comparison.
  ProgramContent? get baseline {
    final json = baselineContent;
    if (json == null) return null;
    try {
      return ProgramContent.decode(json);
    } catch (_) {
      return null;
    }
  }

  /// The review notes, decoded. An unreadable blob reads as "no notes".
  Map<String, String> get exerciseNotes => _decodeNotes(exerciseNotesJson);

  /// The workout-level notes, decoded — same contract as [exerciseNotes],
  /// keyed by planned-session id instead of planned-exercise id.
  Map<String, String> get workoutNotes => _decodeNotes(workoutNotesJson);

  /// The snapshot, decoded — or null when there is none, or when the stored
  /// document was written by a newer build than this one. An unreadable
  /// snapshot renders a placeholder rather than crashing the timeline.
  ProgramContent? get snapshot {
    final json = snapshotContent;
    if (json == null) return null;
    try {
      return ProgramContent.decode(json);
    } catch (_) {
      return null;
    }
  }

  /// When this review belongs on the timeline: when it was completed, else when
  /// it was scheduled for, else when it was created.
  ///
  /// Reviews used to order by `revision_number`, a per-program counter. Without
  /// it the date is the order, and this getter is it — one definition, so the
  /// panel and the digest chain can never disagree about which review came
  /// first.
  DateTime get effectiveDate => completedDate ?? scheduledFor ?? createdDate;

  /// An open review whose scheduled day has arrived. A review scheduled for
  /// today counts as due from the start of that day — the user asked to be
  /// reminded on the day, not at a particular hour.
  bool isDue(DateTime now) =>
      isOpen && scheduledFor != null && !scheduledFor!.isAfter(now);

  /// The proposed edit, decoded — or null when there is none, or when the
  /// stored document was written by a newer build than this one. An unreadable
  /// proposal must not crash the sheet that offers it.
  ProgramContent? get proposal {
    final json = proposedContent;
    if (json == null) return null;
    try {
      return ProgramContent.decode(json);
    } catch (_) {
      return null;
    }
  }

  factory ProgramReview.fromMap(Map<String, dynamic> map) => ProgramReview(
    reviewId: map['review_id'] as String,
    userId: map['user_id'] as String,
    programId: map['program_id'] as String?,
    blockId: map['block_id'] as String?,
    sessionId: map['session_id'] as String?,
    programRunId: map['program_run_id'] as String?,
    kind: (map['kind'] as String?) ?? kReviewKindReview,
    title: map['title'] as String?,
    notes: map['notes'] as String?,
    scheduledFor: _toDate(map['scheduled_for']),
    completedDate: _toDate(map['completed_date']),
    outcome: map['outcome'] as String?,
    proposedContent: map['proposed_content'] as String?,
    proposedHash: map['proposed_hash'] as String?,
    snapshotContent: map['snapshot_content'] as String?,
    snapshotHash: map['snapshot_hash'] as String?,
    baselineContent: map['baseline_content'] as String?,
    baselineHash: map['baseline_hash'] as String?,
    exerciseNotesJson: map['exercise_notes_json'] as String?,
    achievementsJson: map['achievements_json'] as String?,
    sessionIdsJson: map['session_ids_json'] as String?,
    reviewedSessionsJson: map['reviewed_sessions_json'] as String?,
    goalIdsJson: map['goal_ids_json'] as String?,
    workoutNotesJson: map['workout_notes_json'] as String?,
    createdDate: _toDate(map['created_date']) ?? DateTime.now(),
  );
}

/// Which checkpoint stream a review answers for: two snapshots compare only
/// when they answer the same question.
///
/// A stored set keys by its canonical (sorted) ids, so a review of {A,B} taken
/// twice chains; a different set never does — even one that overlaps, because
/// "what changed across these workouts" is a different question from "what
/// changed across those". Legacy rows keep their old per-scope keys; an old
/// pass and a new set review of the same ground do not chain.
///
/// A **standalone** pass over {A,B} and a program pass over {A,B} deliberately
/// share the key and therefore chain: they asked the same question — "what
/// changed across these workouts" — and the answer should read as one chain,
/// wherever each pass was started from.
String reviewScopeKey(ProgramReview review) {
  final stored = review.storedSessionIds;
  if (stored != null) {
    final sorted = [...stored]..sort();
    return 'set:${sorted.join(',')}';
  }
  return switch (review.scopeKind) {
    ReviewScopeKind.program => 'program',
    ReviewScopeKind.block => 'block:${review.blockId}',
    ReviewScopeKind.session => 'session:${review.sessionId}',
  };
}

/// What a review row is. Persisted as text; the DB has a CHECK constraint
/// listing exactly these.
const kReviewKindReview = 'review';
const kReviewKindChange = 'change';
const kReviewKindClose = 'close';

const kReviewKinds = <String>[
  kReviewKindReview,
  kReviewKindChange,
  kReviewKindClose,
];

/// What happened at completion. Non-null exactly when the review is completed.
const kOutcomeReviewed = 'reviewed';
const kOutcomeApplied = 'applied';
const kOutcomeDismissed = 'dismissed';
const kOutcomeClosed = 'closed';

const kReviewOutcomes = <String>[
  kOutcomeReviewed,
  kOutcomeApplied,
  kOutcomeDismissed,
  kOutcomeClosed,
];

/// Human label for a review's [ProgramReview.kind] — the chip in the timeline.
String reviewKindLabel(String kind) => switch (kind) {
  kReviewKindReview => 'Review',
  kReviewKindChange => 'Change',
  kReviewKindClose => 'Close',
  _ => 'Review',
};

/// Human label for a review's [ProgramReview.outcome] — what the row shows once
/// it is completed.
String reviewOutcomeLabel(String? outcome) => switch (outcome) {
  kOutcomeReviewed => 'Reviewed',
  kOutcomeApplied => 'Applied',
  kOutcomeDismissed => 'Dismissed',
  kOutcomeClosed => 'Closed',
  _ => 'Done',
};

/// Human label for what a review examines. The caller supplies the block or
/// workout name — this file has only ids.
String reviewScopeLabel(
  ReviewScopeKind kind, {
  String? blockName,
  String? sessionName,
}) => switch (kind) {
  ReviewScopeKind.program => 'Whole program',
  ReviewScopeKind.block => blockName ?? 'Block',
  ReviewScopeKind.session => sessionName ?? 'Workout',
};

DateTime? _toDate(dynamic v) {
  if (v == null) return null;
  return DateTime.tryParse('$v')?.toLocal();
}

/// A stored JSON array of ids, decoded — null when absent, empty, or
/// unreadable. Shared by the session set and the goal set; the two columns
/// decode identically on purpose, so one can never be read back more
/// forgivingly than the other.
List<String>? _decodeIds(String? json) {
  if (json == null) return null;
  try {
    final decoded = jsonDecode(json);
    if (decoded is! List || decoded.isEmpty) return null;
    return [for (final id in decoded) '$id'];
  } catch (_) {
    return null;
  }
}

/// A stored JSON map of id → note, decoded. An unreadable blob reads as "no
/// notes" — the shared contract of exercise and workout notes.
Map<String, String> _decodeNotes(String? json) {
  if (json == null) return const {};
  try {
    final decoded = jsonDecode(json);
    if (decoded is! Map) return const {};
    return {
      for (final entry in decoded.entries)
        if (entry.value is String) '${entry.key}': entry.value as String,
    };
  } catch (_) {
    return const {};
  }
}
