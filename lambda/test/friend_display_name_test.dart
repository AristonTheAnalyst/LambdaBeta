import 'package:flutter_test/flutter_test.dart';
import 'package:lambda/data/models/friend.dart';

/// The friends list's naming rule (2026-10-25): nickname → real name → code
/// → Friend. Pure, so it lives beside the other model tests with no database
/// anywhere near it.
void main() {
  Friend friend({
    String? first,
    String? last,
    String? nickname,
    String? code,
  }) => Friend(
    userId: 'u1',
    firstName: first,
    lastName: last,
    nickname: nickname,
    friendCode: code,
  );

  group('displayName', () {
    test('a nickname outranks the real name', () {
      expect(
        friend(first: 'Jamie', last: 'Rivera', nickname: 'Natasha').displayName,
        'Natasha',
      );
    });

    test('the nickname is trimmed', () {
      expect(
        friend(first: 'Jamie', nickname: '  Natasha  ').displayName,
        'Natasha',
      );
    });

    test('a blank nickname falls through to the real name', () {
      expect(
        friend(first: 'Jamie', last: 'Rivera', nickname: '   ').displayName,
        'Jamie Rivera',
      );
    });

    test('first and last join; a missing part is left out', () {
      expect(
        friend(first: 'Jamie', last: 'Rivera').displayName,
        'Jamie Rivera',
      );
      expect(friend(first: 'Jamie').displayName, 'Jamie');
      expect(friend(last: 'Rivera').displayName, 'Rivera');
    });

    test('a real name outranks the code', () {
      expect(friend(first: 'Jamie', code: 'WXYZ2345').displayName, 'Jamie');
    });

    test('a friend with no name reads as their code, grouped', () {
      expect(friend(code: 'WXYZ2345').displayName, 'WXYZ-2345');
      expect(friend(nickname: '', code: 'WXYZ2345').displayName, 'WXYZ-2345');
    });

    test('a padded code is trimmed before it is grouped', () {
      expect(friend(code: ' WXYZ2345 ').displayName, 'WXYZ-2345');
    });

    test('nothing at all still reads Friend', () {
      expect(friend().displayName, 'Friend');
      expect(friend(nickname: ' ').displayName, 'Friend');
    });
  });
}
