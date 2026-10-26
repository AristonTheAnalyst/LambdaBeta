import 'package:flutter/foundation.dart';

import '../../../data/models/program_content.dart';
import '../../../data/repositories/program_history_repository.dart';

/// One workout's story while it is being read: which frozen version is on
/// screen, and which exercise of it.
///
/// The versions are read once, before the page opens — walking between them
/// is a change of what the one page draws, never a read, so a step repaints
/// instead of spinning (2026-10-26). The page owns the marks, the notes and
/// the diff; this owns the *which*: the version on screen, the pair the eye
/// flips across, and the version the marks are read against.
class RecordWorkoutState {
  const RecordWorkoutState({
    this.versions = const [],
    this.index = -1,
    this.active = 0,
  });

  /// The workout's versions, newest first: the current plan when the workout
  /// still exists, then every completed review's end and start.
  final List<WorkoutVersion> versions;

  /// Which version is on screen; -1 when the review this page was opened
  /// from recorded nothing of the workout (a row written before snapshots
  /// existed). That is a fact the page says, not a version to draw.
  final int index;

  /// The exercise on screen, an index into the sorted exercises of the
  /// version on screen. Kept across a step — an index into a list both sides
  /// mostly hold — and clamped where the next version is shorter.
  final int active;

  WorkoutVersion? get version =>
      index < 0 || index >= versions.length ? null : versions[index];

  bool get hasRecord => version != null;

  ContentSession? get shown => version?.session;

  bool get isStart => version?.isStart ?? false;

  bool get isCurrent => version?.isCurrent ?? false;

  /// There is a version older than the one on screen.
  bool get canStepOlder => hasRecord && index < versions.length - 1;

  /// There is a version newer than the one on screen.
  bool get canStepNewer => hasRecord && index > 0;

  /// The other side of the review the version on screen belongs to — the
  /// pair the eye flips across. Null on the current plan, which no review
  /// recorded, and on a review that kept only one of its two documents.
  WorkoutVersion? get sibling {
    final current = version;
    if (current == null || current.reviewId == null || current.isCurrent) {
      return null;
    }
    for (final other in versions) {
      if (other.reviewId == current.reviewId &&
          other.isStart != current.isStart) {
        return other;
      }
    }
    return null;
  }

  /// Whether the eye is offered. Both sides must hold the workout: a flip
  /// onto a page saying "the workout was not there" would read as data gone
  /// missing, which is the one thing a record must never look like.
  bool get canFlip {
    final pair = sibling;
    return pair != null && pair.session != null && shown != null;
  }

  /// The newest version any review left — what the current plan is read
  /// against, so its marks say what has changed since the last record.
  WorkoutVersion? get newestEnd {
    for (final version in versions) {
      if (version.side == WorkoutVersionSide.end) return version;
    }
    return null;
  }

  /// The version the marks are read against: on a review version its own
  /// review's other side; on the current plan the newest end, because there
  /// is no "before" but the last record.
  WorkoutVersion? get markReference => isCurrent ? newestEnd : sibling;

  /// The review's exercise notes, keyed by `planned_exercise_id`. Only an end
  /// version carries notes — they are the pass's product, not the state it
  /// found — so a start or a current version answers empty.
  Map<String, String> get exerciseNotes => version?.exerciseNotes ?? const {};

  /// The review's note for the workout as a whole, under the same rule.
  String? get workoutNote => version?.workoutNote;
}

/// Owns the walk over one workout's versions (2026-10-26).
///
/// Every version is already in hand when this is built, so the walk is
/// synchronous: [stepOlder] / [stepNewer] move along the stack and [flip]
/// jumps to the other side of the review on screen — the eye — with no reads
/// in between and no spinner to show.
class RecordWorkoutViewModel extends ValueNotifier<RecordWorkoutState> {
  RecordWorkoutViewModel({
    List<WorkoutVersion> versions = const [],
    int initialIndex = 0,
  }) : super(
         RecordWorkoutState(
           versions: List<WorkoutVersion>.unmodifiable(versions),
           index: initialIndex >= 0 && initialIndex < versions.length
               ? initialIndex
               : -1,
         ),
       );

  /// Older — one step down the stack, toward the workout's first record. No
  /// move at the oldest end.
  void stepOlder() {
    if (!value.canStepOlder) return;
    _moveTo(value.index + 1);
  }

  /// Newer — one step up the stack, toward the current plan. No move at the
  /// newest end.
  void stepNewer() {
    if (!value.canStepNewer) return;
    _moveTo(value.index - 1);
  }

  /// The eye: the same workout on the other side of the review on screen. A
  /// no-op where there is no pair to flip across — the current plan, or a
  /// review whose other side does not hold the workout.
  void flip() {
    if (!value.canFlip) return;
    final pair = value.sibling!;
    final at = value.versions.indexOf(pair);
    if (at >= 0) _moveTo(at);
  }

  /// Switching exercises is looking, and stays — on every version. The index
  /// is clamped when drawn, so a shorter version never lands nowhere.
  void selectExercise(int index) {
    if (index == value.active) return;
    value = RecordWorkoutState(
      versions: value.versions,
      index: value.index,
      active: index,
    );
  }

  void _moveTo(int index) {
    value = RecordWorkoutState(
      versions: value.versions,
      index: index,
      active: value.active,
    );
  }
}
