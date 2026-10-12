/// Compares two values that may be absent, for sorting.
///
/// Values are compared in [direction] (+1 ascending, -1 descending); a null
/// sits below every present value in EITHER direction. That asymmetry is the
/// point: "never used" is missing data, not "used a very long time ago" — the
/// front of a recency sort is the one place it must never land, while the tail
/// of one is exactly where it belongs.
int compareNullable<T extends Comparable<T>>(T? a, T? b, int direction) {
  if (a == null && b == null) return 0;
  if (a == null) return 1;
  if (b == null) return -1;
  return a.compareTo(b) * direction;
}
