import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'lambda_exception.dart';

/// Turns a thrown error into a sentence worth putting in front of a user.
///
/// The writes that go to the server first — beginning a run, creating a
/// program or a block — throw whatever the network threw, and a network error
/// is worded for a developer. Shown raw, a dropped connection reads
/// `ClientException: SocketException: Failed host lookup: '…'`, which is not
/// something a user can act on. The raw error still reaches the console from
/// here, so the detail is kept where it is useful.
String friendlyError(Object error) {
  debugPrint('friendlyError: $error');

  // `package:http` throws a `ClientException` that also *implements*
  // `SocketException` when the host cannot be reached, so this one check
  // covers both the wrapped and the bare form.
  if (error is SocketException || error is TimeoutException) {
    return "Can't reach Lambda — check your connection and try again.";
  }
  if (error is PostgrestException) {
    return 'The server refused that change. Try again in a moment.';
  }
  if (error is AuthException) {
    return 'Your session has expired — sign in again.';
  }
  // A refusal Lambda raised on purpose — its message was written to be read, so
  // it is shown as it stands.
  if (error is LambdaException) return error.message;
  // Everything left is a bug — a `StateError`, a `FormatException` — or a
  // failure not recognised here. That text is a diagnostic and belongs where
  // the `debugPrint` above already put it, not in an error bar.
  return 'Something went wrong. Please try again.';
}
