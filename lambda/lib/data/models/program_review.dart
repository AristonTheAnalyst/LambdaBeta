import 'program_content.dart';

/// What a review examines. Exactly one of the three, decided by which scope id
/// is set on the row — see [ProgramReview.scopeKind].
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
    required this.programId,
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
    this.achievementsJson,
  });

  final String reviewId;
  final String userId;
  final String programId;

  /// The review's BLOCK scope: null = not a block review, else the block it
  /// examines. Never set together with [sessionId].
  ///
  /// Scope rather than context, and the difference is the window: a
  /// program-level review's "since last time" is cut by program-level reviews
  /// only, a block's by the reviews of that same block
  /// ([ProgramHistoryRepository.checkpointFor]), and the contents and the
  /// achievements the sheet shows follow the same scope.
  final String? blockId;

  /// The review's SESSION scope: the `planned_session_id` being examined, or
  /// null. Never set together with [blockId] — the server has a CHECK for it.
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

  /// The frozen record of what the run achieved, written by `closeRun`
  /// together with [kOutcomeClosed]. The one deliberate exception to deriving
  /// on read: a finished block's record must not change because someone later
  /// corrected a set.
  final String? achievementsJson;

  final DateTime createdDate;

  bool get isOpen => completedDate == null;

  bool get isCompleted => completedDate != null;

  bool get hasProposal => proposedContent != null;

  bool get isClosed => kind == kReviewKindClose;

  /// What this review examines. Exactly one scope id is ever set, so the
  /// session wins the check only as a guard against a malformed row.
  ReviewScopeKind get scopeKind {
    if (sessionId != null) return ReviewScopeKind.session;
    if (blockId != null) return ReviewScopeKind.block;
    return ReviewScopeKind.program;
  }

  bool get hasSnapshot => snapshotContent != null;

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
    programId: map['program_id'] as String,
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
    achievementsJson: map['achievements_json'] as String?,
    createdDate: _toDate(map['created_date']) ?? DateTime.now(),
  );
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
