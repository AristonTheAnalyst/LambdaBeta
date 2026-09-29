import 'program_review.dart';

/// Data-layer value objects for the program-history surfaces. Kept here rather
/// than beside the achievements logic (`features/programs/model/`) because
/// repositories return them and `lib/data` never imports `lib/features`.

/// One completed session attributed to a run.
///
/// A plain value object, not a `Session` model: the achievements panel shows a
/// name and a date and nothing else, and pulling the full session graph into it
/// would make the history screen read the whole logging schema to render a list
/// of three words.
class AchievementSession {
  const AchievementSession({
    required this.sessionId,
    required this.date,
    this.name,
  });

  final String sessionId;

  /// The `planned_session_name` snapshot off `fact_session` — survives a
  /// template rename, which is exactly why the column exists. Null for a
  /// freestyle session started with no template.
  final String? name;

  final DateTime date;

  Map<String, dynamic> toMap() => {
        'session_id': sessionId,
        'name': name,
        'date': date.toUtc().toIso8601String(),
      };

  factory AchievementSession.fromMap(Map<String, dynamic> map) =>
      AchievementSession(
        sessionId: '${map['session_id']}',
        name: map['name'] as String?,
        date: DateTime.tryParse('${map['date']}')?.toLocal() ?? DateTime.now(),
      );
}

/// Why a program is asking for attention.
///
/// All three are prompts, and all three are derived — nothing here is written
/// to a table, and none of them does anything on its own. That is the point of
/// the pair about runs: a block's length running out used to end the run by
/// itself ([kDueRunFinished] only ever appeared over an already-closed run);
/// now it raises the question and waits, and [kDueBlockStart] is the same
/// courtesy at the other end of the phase.
const kDueReview = 'review';
const kDueRunFinished = 'run_finished';
const kDueBlockStart = 'block_start';

const kDueKinds = <String>[kDueReview, kDueRunFinished, kDueBlockStart];

/// Something waiting on the user, surfaced on the library card and the program
/// detail banner.
///
/// Deliberately carries no program name: every caller that renders a
/// [DueItem] already has the program in hand, and a join on every library open
/// to re-fetch a string the caller already holds is exactly the kind of
/// amplification the program layer avoids elsewhere. A block name is different
/// — it is not the caller's to know, because the item may be about a phase the
/// caller has not looked at.
class DueItem {
  const DueItem({
    required this.kind,
    required this.programId,
    this.review,
    this.dueDate,
    this.blockId,
    this.blockName,
  });

  /// One of [kDueReview], [kDueRunFinished], [kDueBlockStart].
  final String kind;

  final String programId;

  /// The review that is due — always set for [kDueReview], since the due item
  /// is that row. Null for the two derived kinds.
  final ProgramReview? review;

  /// When it came due. For a scheduled review this is the day the user chose,
  /// which may be well in the past; for [kDueBlockStart] it is the block's
  /// `start_date`.
  final DateTime? dueDate;

  /// The block this is about, when it is about one. Set for [kDueBlockStart],
  /// and for a [kDueRunFinished] over a block run — which is what lets the
  /// banner say "Block finished" rather than "Program finished", and what tells
  /// the begin flow which phase to preselect.
  final String? blockId;
  final String? blockName;

  bool get isReviewDue => kind == kDueReview;

  bool get isRunFinished => kind == kDueRunFinished;

  bool get isBlockStart => kind == kDueBlockStart;

  /// True when this run is bounded by a block rather than by the program.
  bool get isBlockScoped => blockId != null;

  /// Short label for a chip or badge.
  String get label => switch (kind) {
        kDueReview => 'Review due',
        // A block and a program are not the same thing to finish, and the user
        // is looking straight at the one this is about.
        kDueRunFinished => isBlockScoped ? 'Block finished' : 'Program finished',
        kDueBlockStart => 'Block ready',
        _ => 'Due',
      };

  /// What the banner says. Written here rather than at the render site because
  /// the wording and the kind are one decision: a banner that describes a
  /// state the item does not carry is how "this program has finished" ended up
  /// sitting over a run that was still going.
  String get prompt => switch (kind) {
        kDueReview => 'A review is due.',
        kDueRunFinished => isBlockScoped
            ? 'This block has run its length — end it to record what it produced.'
            : 'This program has finished — review what it produced.',
        kDueBlockStart => blockName == null
            ? 'A block is ready to begin.'
            : '$blockName is ready to begin.',
        _ => 'Something is due.',
      };
}
