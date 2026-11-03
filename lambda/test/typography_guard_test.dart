import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The typography scaffold, enforced (2026-10-22).
///
/// Production and shared code may not set a numeric text size below the 12px
/// label floor nor track a label past 0.8. Sizes and tracking are chosen from
/// `AppTextStyles`; when a screen needs a new value, the token and this
/// ceiling move in the same change (see the `typography` skill).
///
/// `lib/features/dev/` is exempt: those screens deliberately demonstrate
/// variants, and the PR Lab is the finished-look reference, not a subject.

final _fontSize = RegExp(r'fontSize:\s*(\d+(?:\.\d+)?)\b');
final _tracking = RegExp(r'letterSpacing:\s*(-?\d+(?:\.\d+)?)\b');

Iterable<File> _productionFiles() => Directory('lib')
    .listSync(recursive: true)
    .whereType<File>()
    .map((f) => f)
    .where((f) {
      final path = f.path.replaceAll('\\', '/');
      return path.endsWith('.dart') && !path.contains('/features/dev/');
    });

/// The line with any trailing `//` comment removed, so documentation that
/// quotes an old value is not mistaken for code.
String _code(String line) => line.split('//').first;

List<String> _violations(RegExp pattern, bool Function(double) isBad) {
  final found = <String>[];
  for (final file in _productionFiles()) {
    final lines = file.readAsLinesSync();
    for (var i = 0; i < lines.length; i++) {
      for (final match in pattern.allMatches(_code(lines[i]))) {
        final value = double.parse(match.group(1)!);
        if (isBad(value)) {
          found.add('${file.path}:${i + 1}: ${lines[i].trim()}');
        }
      }
    }
  }
  return found;
}

void main() {
  test('no text below the 12px floor outside the dev demos', () {
    final found = _violations(_fontSize, (v) => v < 12);
    expect(
      found,
      isEmpty,
      reason:
          'Numeric font sizes below 12 are off the ladder:\n'
          '${found.join('\n')}',
    );
  });

  test('no tracking beyond 0.8 outside the dev demos', () {
    final found = _violations(_tracking, (v) => v.abs() > 0.8);
    expect(
      found,
      isEmpty,
      reason:
          'Uppercase mono labels track 0.6–0.8; anything else is drifted:\n'
          '${found.join('\n')}',
    );
  });
}
