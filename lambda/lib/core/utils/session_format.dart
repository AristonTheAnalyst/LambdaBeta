List<num> parseValues(String input) {
  return input
      .split(',')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .map((s) => num.tryParse(s))
      .whereType<num>()
      .toList();
}

String toProperCase(String s) {
  if (s.isEmpty) return s;
  return s
      .split(' ')
      .map((word) => word.isEmpty
          ? word
          : '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}')
      .join(' ');
}
