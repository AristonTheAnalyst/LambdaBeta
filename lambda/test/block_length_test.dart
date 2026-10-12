import 'package:flutter_test/flutter_test.dart';
import 'package:lambda/core/utils/block_length.dart';

/// The block length arithmetic. Pure, so it lives in `test/` with no PowerSync
/// anywhere near it — which is the point of keeping it in `core/utils/`.
void main() {
  group('blockLengthModeOf', () {
    test('sessions when only sessions is set', () {
      expect(
        blockLengthModeOf(targetWeeks: null, targetSessions: 24),
        BlockLengthMode.sessions,
      );
    });

    test('weeks when only weeks is set', () {
      expect(
        blockLengthModeOf(targetWeeks: 8, targetSessions: null),
        BlockLengthMode.weeks,
      );
    });

    test('weeks when neither is set — a new block has to open on something', () {
      expect(
        blockLengthModeOf(targetWeeks: null, targetSessions: null),
        BlockLengthMode.weeks,
      );
    });

    test('sessions wins the legacy both-set shape, deterministically', () {
      expect(
        blockLengthModeOf(targetWeeks: 8, targetSessions: 24),
        BlockLengthMode.sessions,
      );
    });
  });

  group('endDateFor', () {
    test('adds whole weeks to the calendar date', () {
      expect(
        endDateFor(DateTime(2026, 3, 3), 8),
        DateTime(2026, 4, 28),
      );
    });

    test('rolls across a year boundary', () {
      expect(
        endDateFor(DateTime(2026, 11, 12), 8),
        DateTime(2027, 1, 7),
      );
    });

    test('adds the days remainder on top of the weeks', () {
      // 8 weeks lands on 28 April; the three days are what put the block's last
      // session on a Friday instead of the Tuesday before it.
      expect(endDateFor(DateTime(2026, 3, 3), 8, 3), DateTime(2026, 5, 1));
    });

    test('week zero is still a length — the days carry it', () {
      expect(endDateFor(DateTime(2026, 3, 3), 0, 3), DateTime(2026, 3, 6));
    });

    test('keeps the time of day, so a run timestamp is not snapped', () {
      expect(
        endDateFor(DateTime(2026, 3, 3, 14, 30), 1),
        DateTime(2026, 3, 10, 14, 30),
      );
    });

    test('preserves UTC-ness — a run start and a block start differ', () {
      expect(endDateFor(DateTime.utc(2026, 3, 3), 8).isUtc, isTrue);
      expect(endDateFor(DateTime(2026, 3, 3), 8).isUtc, isFalse);
    });

    test('lands on midnight across a daylight-saving boundary', () {
      // 29 Mar 2026 is the UK spring-forward. A day-arithmetic result must
      // still be local midnight of the intended date, not 23:00 the day before.
      final end = endDateFor(DateTime(2026, 3, 22), 1);
      expect(end, DateTime(2026, 3, 29));
      expect(end.hour, 0);
    });
  });

  group('lengthBetween', () {
    test('round-trips endDateFor exactly, remainder included', () {
      final start = DateTime(2026, 3, 3);
      // The pairs that matter: a day-only length, both ends of the remainder
      // range, a week-only length, and a long one. Together they are the claim
      // that the two fields are one value — pick an end, read the length back,
      // get the same end.
      for (final (weeks, days) in const [(0, 1), (0, 6), (1, 0), (1, 1),
        (8, 0), (8, 3), (52, 6)]) {
        expect(
          lengthBetween(
            startDate: start,
            endDate: endDateFor(start, weeks, days),
          ),
          (weeks: weeks, days: days),
          reason: '$weeks weeks $days days must read back unchanged',
        );
      }
    });

    test('is exact, not rounded to the nearer week', () {
      // 62 days is 8.86 weeks. The whole-week inverse this replaced called that
      // 9; carrying the remainder lets it be 8 weeks 6 days — a length that
      // projects back to the same day it was read from.
      expect(
        lengthBetween(
          startDate: DateTime(2026, 3, 3),
          endDate: DateTime(2026, 5, 4),
        ),
        (weeks: 8, days: 6),
      );
    });

    test('counts a seven-day span across a DST boundary as one week', () {
      // Absolute elapsed time is 6d23h, so a naive local `inDays` reads 6.
      expect(
        lengthBetween(
          startDate: DateTime(2026, 3, 28),
          endDate: DateTime(2026, 4, 4),
        ),
        (weeks: 1, days: 0),
      );
    });

    test('null when there is no anchor, or no length to read', () {
      expect(
        lengthBetween(startDate: null, endDate: DateTime(2026, 5, 4)),
        isNull,
      );
      expect(
        lengthBetween(startDate: DateTime(2026, 3, 3), endDate: null),
        isNull,
      );
      expect(
        lengthBetween(
          startDate: DateTime(2026, 3, 3),
          endDate: DateTime(2026, 3, 3),
        ),
        isNull,
        reason: 'an end on the start is not a length',
      );
      expect(
        lengthBetween(
          startDate: DateTime(2026, 5, 4),
          endDate: DateTime(2026, 3, 3),
        ),
        isNull,
        reason: 'an end before the start is not a plan',
      );
    });
  });

  group('blockLengthPhrase', () {
    test('weeks and days together', () {
      expect(
        blockLengthPhrase(targetWeeks: 8, targetSessions: null, targetDays: 3),
        '8 weeks 3 days',
      );
    });

    test('a whole number of weeks names only weeks', () {
      expect(blockLengthPhrase(targetWeeks: 8, targetSessions: null), '8 weeks');
      expect(
        blockLengthPhrase(targetWeeks: 8, targetSessions: null, targetDays: 0),
        '8 weeks',
        reason: 'a zero remainder is absent, not a second unit',
      );
    });

    test('singulars', () {
      expect(blockLengthPhrase(targetWeeks: 1, targetSessions: null), '1 week');
      expect(
        blockLengthPhrase(targetWeeks: 1, targetSessions: null, targetDays: 1),
        '1 week 1 day',
      );
      expect(blockLengthPhrase(targetWeeks: null, targetSessions: 1),
          '1 session');
    });

    test('a sub-week block drops the weeks entirely', () {
      expect(
        blockLengthPhrase(targetWeeks: 0, targetSessions: null, targetDays: 3),
        '3 days',
        reason: '"0 weeks 3 days" is not a thing anyone typed',
      );
    });

    test('sessions wins, exactly as blockLengthModeOf does', () {
      expect(
        blockLengthPhrase(targetWeeks: 8, targetSessions: 24),
        '24 sessions',
      );
    });

    test('null when the block declares no length', () {
      expect(blockLengthPhrase(targetWeeks: null, targetSessions: null), isNull);
      expect(
        blockLengthPhrase(targetWeeks: 0, targetSessions: null, targetDays: 0),
        isNull,
        reason: 'unwritable, but a malformed read is not an empty phrase',
      );
    });
  });

  group('sameCalendarDay', () {
    test('ignores time of day and UTC-ness', () {
      expect(
        sameCalendarDay(DateTime(2026, 3, 3, 23), DateTime.utc(2026, 3, 3, 1)),
        isTrue,
      );
      expect(sameCalendarDay(DateTime(2026, 3, 3), DateTime(2026, 3, 4)), isFalse);
    });

    test('nulls are equal only to nulls', () {
      expect(sameCalendarDay(null, null), isTrue);
      expect(sameCalendarDay(null, DateTime(2026, 3, 3)), isFalse);
      expect(sameCalendarDay(DateTime(2026, 3, 3), null), isFalse);
    });
  });
}
