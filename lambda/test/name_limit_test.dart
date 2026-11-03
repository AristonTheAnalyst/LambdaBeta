import 'package:flutter_test/flutter_test.dart';
import 'package:lambda/core/utils/name_limit.dart';

/// The name-length rule. Pure, so it lives in `test/` with no PowerSync
/// anywhere near it — the same reason it lives in `core/utils/`.
void main() {
  group('kMaxExerciseNameLength', () {
    test('is twenty', () {
      // Pinned deliberately. The number is spelled three times — here, in
      // `dim_exercise_name_length_check` / `dim_variation_name_length_check`,
      // and in the selector field it was measured from — and this is the only
      // place all three can be caught disagreeing.
      expect(kMaxExerciseNameLength, 20);
    });
  });

  group('the wider names', () {
    // Each is pinned to the number the field, the counter and the repository
    // assert pass — and each is bounded by the migration's 120-character rail
    // (`20261020120000_name_length_rails.sql`), whose header states why the
    // rail sits above the cap rather than at it: the PowerSync mirror has no
    // CHECK, so a rule the app can trip would quarantine the write instead of
    // refusing it. The last expectation is the invariant, not a coincidence —
    // if a cap ever crosses the rail, this fails before a row does.
    test('are twenty across the board', () {
      // Wider kinds get the same budget as an exercise name. The number is
      // measured from the narrowest surface a name is DRAWN on — the
      // `PageHeader` title, which holds about twenty average characters at
      // `AppTextStyles.lg` — not from the widest one (a card) (2026-10-20).
      // A capped name must never be a name the app has to cut.
      expect(kMaxWorkoutNameLength, 20);
      expect(kMaxProgramNameLength, 20);
      expect(kMaxBlockNameLength, 20);
      expect(kMaxGoalTextLength, 20);
      expect(kMaxReviewTitleLength, 20);
      expect(kMaxFriendNicknameLength, 20);
    });

    test('all sit below the database rail', () {
      const rail = 120;
      for (final max in [
        kMaxExerciseNameLength,
        kMaxWorkoutNameLength,
        kMaxProgramNameLength,
        kMaxBlockNameLength,
        kMaxGoalTextLength,
        kMaxReviewTitleLength,
        kMaxFriendNicknameLength,
      ]) {
        expect(max, lessThan(rail));
      }
    });
  });

  group('nameTooLong', () {
    test('a name at the limit passes', () {
      expect(nameTooLong('a' * 20), isFalse);
      expect(nameTooLong('Single Leg Glute Br.'), isFalse);
    });

    test('one character over fails', () {
      expect(nameTooLong('a' * 21), isTrue);
    });

    test('empty and short names pass — emptiness is not this rule', () {
      // An empty name is refused by the callers' own `isEmpty` guards. Folding
      // the two rules together would report a blank name as "too long", which
      // is not the thing that is wrong with it.
      expect(nameTooLong(''), isFalse);
      expect(nameTooLong('Squat'), isFalse);
    });

    test('measured on the trimmed value, because that is what gets stored', () {
      // Every write path stores `name.trim()`, so counting the untrimmed
      // characters would let trailing spaces trip a limit the user's own field
      // said they were inside of.
      expect(nameTooLong('${'a' * 20}   '), isFalse);
      expect(nameTooLong('   ${'a' * 20}'), isFalse);
      expect(nameTooLong('${'a' * 21}   '), isTrue);
    });

    test('counts characters, not bytes — the SQL says char_length', () {
      // A twenty-character name of non-ASCII glyphs is twenty characters and
      // inside the rule; `length()` in Postgres would call it sixty bytes.
      expect(nameTooLong('é' * 20), isFalse);
      expect(nameTooLong('é' * 21), isTrue);
    });

    test('splitting a long name into words does not change the count', () {
      expect(nameTooLong('Elevated Unilateral Glute Bridge'), isTrue);
      expect(nameTooLong('Elevated Glute Br.'), isFalse);
    });

    test('every kind of name states its own limit', () {
      // The second argument is what makes one predicate serve six fields. The
      // kinds agree on twenty today; the per-kind argument is what lets one
      // move again without touching the others.
      expect(nameTooLong('a' * 20, kMaxWorkoutNameLength), isFalse);
      expect(nameTooLong('a' * 21, kMaxWorkoutNameLength), isTrue);
      expect(nameTooLong('a' * 20, kMaxBlockNameLength), isFalse);
      expect(nameTooLong('a' * 21, kMaxBlockNameLength), isTrue);
      expect(nameTooLong('a' * 20, kMaxGoalTextLength), isFalse);
      expect(nameTooLong('a' * 21, kMaxGoalTextLength), isTrue);
      expect(nameTooLong('a' * 20, kMaxReviewTitleLength), isFalse);
      expect(nameTooLong('a' * 21, kMaxReviewTitleLength), isTrue);
    });
  });

  group('nameTooLongMessage', () {
    test('states the limit the field stated', () {
      // The counters under the fields read `12/20`; a refused write has to say
      // the same number in words, not a rounded or restated one.
      expect(nameTooLongMessage(20), contains('20'));
      expect(nameTooLongMessage(kMaxWorkoutNameLength), contains('20'));
    });
  });
}
