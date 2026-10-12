/// How much of a program has actually been trained — what the Programs
/// list's "last used" and "most used" sorts read per program.
///
/// Derived, never stored: it is a fact about the logged sessions, read on one
/// grouped query when the library loads. A program nothing was logged against
/// has no entry at all, which is not the same shape as one with zeros.
class ProgramUsage {
  const ProgramUsage({this.lastUsed, this.sessions = 0});

  /// The newest completed session logged against this program's workouts.
  /// Null = never trained (the caller reads that as "below everything dated").
  final DateTime? lastUsed;

  /// Completed sessions logged against its workouts. A session counts toward
  /// every program it can be attributed to — a workout shared by two programs
  /// was trained for both.
  final int sessions;
}
