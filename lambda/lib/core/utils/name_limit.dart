/// How many characters each kind of user-created name may hold, and the one
/// check that reads them.
///
/// Lives in `core/utils/` because both layers need the same numbers and they
/// cannot import each other: the viewmodels refuse an over-long name before
/// writing, and the repositories — in `lib/data/`, which never imports
/// `lib/features/` — refuse it at the column. Two spellings of forty would
/// drift, and the drift would be invisible until a row failed to upload.
///
/// The database states each rule independently (`*_name_length_check`
/// constraints), so these constants are the client's spelling of invariants
/// that are already true on disk. `name_limit_test.dart` pins every number
/// precisely so the two cannot disagree.
library;

/// The most characters an exercise or variation name may hold — spaces
/// included.
///
/// Twenty is a measurement, not a round number. The narrowest surface that
/// draws a name is the exercise selector's field, which sits between two 32px
/// arrows inside a padded card and, at phone width, holds about twenty
/// characters at `AppTextStyles.sm` before it has to ellipsize. A name longer
/// than the field is a name no screen can show whole, and the picker is where
/// the user chooses it.
const kMaxExerciseNameLength = 20;

/// A planned session's name.
///
/// Twenty — the same budget as an exercise — because the surface that draws it
/// is the **header title** once the workout is running: `PageHeader` leaves the
/// title the middle 217–226pt of a 393–402pt phone, which holds about twenty
/// average characters at `AppTextStyles.lg` w600 before it ellipsizes. A wider
/// cap let names through that no screen could show whole (a 30-character name
/// elided in the session it was named for), which is the complaint this number
/// answers (2026-10-20). Cards and banners — the wider surfaces — all fit
/// twenty comfortably.
const kMaxWorkoutNameLength = 20;

/// A program's name — its own header title is the same `PageHeader` slot a
/// workout's name gets, so the same twenty.
const kMaxProgramNameLength = 20;

/// A program block's name. A phase label ("Base", "Build", "Peak") drawn on a
/// chip, in a segmented control and in a section header — never a sentence.
const kMaxBlockNameLength = 20;

/// A goal's text. The app writes the **exercise name** here at creation (the
/// label a goal keeps if the exercise is later deleted), so this rides the
/// exercise cap. A goal's prose is its `description`, which is uncapped.
const kMaxGoalTextLength = 20;

/// A review's title — drawn on the review landing's `PageHeader`, so the same
/// twenty the other header titles get.
const kMaxReviewTitleLength = 20;

/// A friend's nickname — the caller's private label for one friend, drawn in
/// the friends list where a name sits. The same twenty the other names get:
/// the row it is drawn in is exactly a name row (2026-10-25).
const kMaxFriendNicknameLength = 20;

/// Whether [value] breaks the rule the database checks enforce.
///
/// [max] defaults to [kMaxExerciseNameLength] because the exercise/variation
/// fields were the first to state the rule and their call sites are the ones
/// that never pass one; every other kind states its own.
///
/// Measured on the **trimmed** value, because that is the value that gets
/// stored: every write path stores `name.trim()`, so counting untrimmed
/// characters would let trailing spaces trip a limit the user's own field said
/// they were inside of.
///
/// Emptiness is deliberately not this function's business — an empty name is
/// already refused by the callers' existing `isEmpty` guards, and folding the
/// two rules together would make a blank name "too long" in an error message.
bool nameTooLong(String value, [int max = kMaxExerciseNameLength]) =>
    value.trim().length > max;

/// The sentence a screen shows when a write is refused for length.
///
/// One spelling again: the viewmodel's error and any field that has to say why
/// a Save did nothing read the same words. The counters under the fields
/// already state the number as `12/20`; this is the same fact in a sentence,
/// for the one place a write was attempted anyway.
String nameTooLongMessage(int max) => 'Names can be at most $max characters.';
