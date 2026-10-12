import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lambda/core/utils/friendly_error.dart';
import 'package:lambda/core/utils/lambda_exception.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('a connection failure reads as a connection problem', () {
    expect(
      friendlyError(const SocketException('Failed host lookup: example.com')),
      "Can't reach Lambda — check your connection and try again.",
    );
    expect(
      friendlyError(TimeoutException('timed out')),
      contains('connection'),
    );
  });

  test('a server refusal does not read as a network problem', () {
    expect(
      friendlyError(const PostgrestException(message: 'duplicate key')),
      'The server refused that change. Try again in a moment.',
    );
  });

  test('an expired session says so', () {
    expect(
      friendlyError(AuthException('JWT expired')),
      'Your session has expired — sign in again.',
    );
  });

  test('an exception Lambda wrote keeps its own words', () {
    expect(
      friendlyError(
          const LambdaException('A program named "Push" already exists.')),
      'A program named "Push" already exists.',
    );
  });

  test('a bare Exception is not assumed to be user-facing', () {
    // `Exception('…')` builds a private `_Exception`, so it cannot be told
    // apart from anyone else's at runtime — the reason `LambdaException`
    // exists. A sentence nobody wrote for the user must not reach the screen
    // just because it was thrown as an `Exception`.
    expect(
      friendlyError(Exception('A program named "Push" already exists.')),
      'Something went wrong. Please try again.',
    );
  });

  test('a bug gets a plain sentence, not the raw error', () {
    expect(
      friendlyError(StateError('Workout not found: abc')),
      'Something went wrong. Please try again.',
    );
  });
}
