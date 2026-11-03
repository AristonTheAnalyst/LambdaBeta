import 'package:flutter_test/flutter_test.dart';
import 'package:lambda/core/utils/friend_code.dart';

/// The friend code has one parser (2026-10-23): the input field, the button's
/// enablement and the repository's request all read `normalizeFriendCode`, so
/// a pasted `abcd-efgh`, a typed `ABCD EFGH` and a stored `ABCDEFGH` are one
/// code everywhere.
void main() {
  group('normalizeFriendCode', () {
    test('a clean code passes through untouched', () {
      expect(normalizeFriendCode('ABCDEFGH'), 'ABCDEFGH');
    });

    test('lower-case is the same code', () {
      expect(normalizeFriendCode('abcdefgh'), 'ABCDEFGH');
    });

    test('the drawn hyphen is noise — pasting the formatted form works', () {
      expect(normalizeFriendCode('ABCD-EFGH'), 'ABCDEFGH');
      expect(normalizeFriendCode('abcd-efgh'), 'ABCDEFGH');
    });

    test('spaces around and inside are noise', () {
      expect(normalizeFriendCode('  ABCD EFGH  '), 'ABCDEFGH');
    });

    test('other punctuation is noise too', () {
      expect(normalizeFriendCode('AB.CD_EF-GH'), 'ABCDEFGH');
    });

    test('letters outside the alphabet never form a code', () {
      // I, O, 0 and 1 are left out of the alphabet deliberately — a code
      // containing them cannot be one the server issued.
      expect(normalizeFriendCode('ABCDEFGI'), isNull);
      expect(normalizeFriendCode('ABCDEFGO'), isNull);
      expect(normalizeFriendCode('ABCDEFG0'), isNull);
      expect(normalizeFriendCode('ABCDEFG1'), isNull);
    });

    test('too short or too long is null', () {
      expect(normalizeFriendCode('ABCDEFG'), isNull);
      expect(normalizeFriendCode('ABCDEFGHJ'), isNull);
      expect(normalizeFriendCode(''), isNull);
      expect(normalizeFriendCode('   '), isNull);
    });

    test('digits 2-9 are part of the alphabet', () {
      expect(normalizeFriendCode('23456789'), '23456789');
    });
  });

  group('formatFriendCode', () {
    test('groups eight characters as 4 + 4', () {
      expect(formatFriendCode('ABCDEFGH'), 'ABCD-EFGH');
    });

    test('round-trips through the parser', () {
      expect(normalizeFriendCode(formatFriendCode('ABCDEFGH')), 'ABCDEFGH');
    });

    test('a non-code is drawn as it is rather than half-grouped', () {
      // Defensive: the card only ever formats a stored code, but a malformed
      // one should read as itself, not gain a hyphen mid-string.
      expect(formatFriendCode('ABCD'), 'ABCD');
    });
  });
}
