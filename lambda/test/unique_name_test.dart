import 'package:flutter_test/flutter_test.dart';
import 'package:lambda/shared/utils/unique_name.dart';

void main() {
  group('uniqueName', () {
    test('returns base unchanged when it is free', () {
      expect(uniqueName('New Program', {}), 'New Program');
      expect(uniqueName('New Program', {'Push Day'}), 'New Program');
    });

    test('appends the first free integer when base is taken', () {
      expect(uniqueName('New Program', {'New Program'}), 'New Program 2');
      expect(
        uniqueName('New Program', {'New Program', 'New Program 2', 'New Program 3'}),
        'New Program 4',
      );
    });

    test('takes the smallest free slot even when a higher one exists', () {
      // Only "New Program 3" exists — the free slot 2 is still taken.
      expect(uniqueName('New Program', {'New Program', 'New Program 3'}), 'New Program 2');
    });

    test('copy pattern yields "(Copy)", "(Copy 2)" — never "(Copy) 2"', () {
      String numbered(int n) => 'Push Day (Copy $n)';
      expect(uniqueName('Push Day (Copy)', {'Push Day'}, numbered: numbered),
          'Push Day (Copy)');
      expect(
        uniqueName('Push Day (Copy)', {'Push Day', 'Push Day (Copy)'},
            numbered: numbered),
        'Push Day (Copy 2)',
      );
      expect(
        uniqueName(
            'Push Day (Copy)',
            {'Push Day', 'Push Day (Copy)', 'Push Day (Copy 2)'},
            numbered: numbered),
        'Push Day (Copy 3)',
      );
    });

    test('matches case-insensitively, like the repo assert paths', () {
      expect(uniqueName('New Program', {'NEW PROGRAM'}), 'New Program 2');
      expect(uniqueName('new program', {'New Program'}), 'new program 2');
    });

    test('compares trimmed', () {
      expect(uniqueName(' New Program ', {'New Program'}), 'New Program 2');
      expect(uniqueName('New Program', {'New Program '}), 'New Program 2');
    });
  });
}
