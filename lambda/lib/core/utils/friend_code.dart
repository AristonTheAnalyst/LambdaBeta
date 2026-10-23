/// The friend code — the one shareable handle a user has, Discord-style
/// (2026-10-23).
///
/// The server allocates it (a random 8-character string) and the client only
/// ever reads, formats and normalises it. Lives in `core/utils/` because both
/// the input field and the repository need the same rule: a pasted
/// `abcd-efgh`, a typed `ABCD EFGH` and a stored `ABCDEFGH` are one code.
library;

/// The alphabet the server draws from: 32 symbols, with I, O, 0 and 1 left
/// out because they are misread as 1/0/l. The migration's CHECK constraint is
/// the server's spelling of this same set.
const kFriendCodeAlphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

/// How many characters a code holds, letters and digits together.
const kFriendCodeLength = 8;

final _shape = RegExp('^[$kFriendCodeAlphabet]{$kFriendCodeLength}\$');
final _noise = RegExp('[^A-Za-z0-9]');

/// The code [raw] was trying to be, or null when it cannot be one.
///
/// Upper-cases, strips every non-alphanumeric (the hyphens the UI itself
/// draws, pasted spaces), then checks the length and alphabet. One parser for
/// the field, the button's enablement and the repository's request.
String? normalizeFriendCode(String raw) {
  final code = raw.toUpperCase().replaceAll(_noise, '');
  if (code.length != kFriendCodeLength) return null;
  return _shape.hasMatch(code) ? code : null;
}

/// `ABCDEFGH` → `ABCD-EFGH`, the grouped form the card draws and the Copy
/// button puts on the clipboard.
String formatFriendCode(String code) =>
    code.length == kFriendCodeLength
        ? '${code.substring(0, 4)}-${code.substring(4)}'
        : code;
