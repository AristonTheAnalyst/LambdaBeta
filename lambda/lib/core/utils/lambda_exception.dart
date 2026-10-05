/// An error Lambda raises on purpose, carrying a sentence meant for the user.
///
/// Most thrown errors are not for the user: the network throws text written for
/// a developer (`ClientException: SocketException: Failed host lookup: '…'`)
/// and a bug throws a diagnostic (`StateError: Workout not found: abc`).
/// Occasionally, though, a failure is an ordinary outcome that has to be told
/// plainly — a program name already taken. `friendlyError` shows this
/// exception's message word for word and sends every other unrecognised error
/// to the console instead, so raising this type is the one way a repository's
/// sentence reaches the screen.
///
/// Note that `Exception('…')` does *not* qualify — it builds a private
/// `_Exception`, indistinguishable at runtime from anyone else's, which is why
/// this named type exists at all.
///
/// Lives in `core/utils/` for the same reason as `name_limit.dart`: `lib/data/`
/// raises this and `lib/features/` reads it, and the two cannot import each
/// other.
library;

/// A failure whose [message] the user can act on.
class LambdaException implements Exception {
  const LambdaException(this.message);

  /// The sentence to show, written as the user should read it: no class name,
  /// no `Exception:` prefix, ending in a full stop.
  final String message;

  @override
  String toString() => 'LambdaException: $message';
}
