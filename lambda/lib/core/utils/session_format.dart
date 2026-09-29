List<num> parseValues(String input) {
  return input
      .split(',')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .map((s) => num.tryParse(s))
      .whereType<num>()
      .toList();
}

/// Display names show EXACTLY as the user typed them — auto-capitalization
/// was removed (2026-08-22) because it wasn't respecting user input.
String toProperCase(String s) => s;

/// A program's 1–7 day assignment as a three-letter label. Null (and anything
/// outside 1–7) is the empty string — an unassigned session shows no chip.
String dayOfWeekLabel(int? d) => switch (d) {
  1 => 'Mon',
  2 => 'Tue',
  3 => 'Wed',
  4 => 'Thu',
  5 => 'Fri',
  6 => 'Sat',
  7 => 'Sun',
  _ => '',
};
