import 'program_revision.dart';

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
    this.programRunId,
    this.title,
    this.notes,
    this.scheduledFor,
    this.completedDate,
    this.outcome,
    this.proposedContent,
    this.proposedHash,
    this.achievementsJson,
    this.revisionId,
  });

  final String reviewId;
  final String userId;
  final String programId;

  /// CONTEXT, not scope — the block that was active when this was written.
  /// Plain text with no FK until the blocks migration lands.
  final String? blockId;

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
  /// this is a PROPOSAL, never a revision. Nothing copies it into live rows:
  /// applying one opens the normal editor pre-filled.
  final String? proposedContent;
  final String? proposedHash;

  /// The frozen record of what the run achieved, written by `closeRun`
  /// together with [kOutcomeClosed]. The one deliberate exception to deriving
  /// on read: a finished block's record must not change because someone later
  /// corrected a set.
  final String? achievementsJson;

  /// Plain ref (no FK) to the revision this checkpoint cut. Revisions point
  /// back at their review, so an FK pair would be circular and break upload
  /// ordering. Neither table is ever deleted.
  final String? revisionId;

  final DateTime createdDate;

  bool get isOpen => completedDate == null;

  bool get isCompleted => completedDate != null;

  bool get hasProposal => proposedContent != null;

  bool get isClosed => kind == kReviewKindClose;

  /// An open review whose scheduled day has arrived. A review scheduled for
  /// today counts as due from the start of that day — the user asked to be
  /// reminded on the day, not at a particular hour.
  bool isDue(DateTime now) =>
      isOpen && scheduledFor != null && !scheduledFor!.isAfter(now);

  /// The proposed edit, decoded — or null when there is none, or when the
  /// stored document was written by a newer build than this one. An unreadable
  /// proposal must not crash the sheet that offers it.
  ProgramRevisionContent? get proposal {
    final json = proposedContent;
    if (json == null) return null;
    try {
      return ProgramRevisionContent.decode(json);
    } catch (_) {
      return null;
    }
  }

  factory ProgramReview.fromMap(Map<String, dynamic> map) => ProgramReview(
        reviewId: map['review_id'] as String,
        userId: map['user_id'] as String,
        programId: map['program_id'] as String,
        blockId: map['block_id'] as String?,
        programRunId: map['program_run_id'] as String?,
        kind: (map['kind'] as String?) ?? kReviewKindReview,
        title: map['title'] as String?,
        notes: map['notes'] as String?,
        scheduledFor: _toDate(map['scheduled_for']),
        completedDate: _toDate(map['completed_date']),
        outcome: map['outcome'] as String?,
        proposedContent: map['proposed_content'] as String?,
        proposedHash: map['proposed_hash'] as String?,
        achievementsJson: map['achievements_json'] as String?,
        revisionId: map['revision_id'] as String?,
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

DateTime? _toDate(dynamic v) {
  if (v == null) return null;
  return DateTime.tryParse('$v')?.toLocal();
}
