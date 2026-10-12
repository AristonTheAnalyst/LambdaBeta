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
