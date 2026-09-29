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
  });
}
