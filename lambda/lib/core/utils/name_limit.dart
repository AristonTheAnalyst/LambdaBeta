/// The most characters an exercise or variation name may hold, and the one
/// check that reads it.
///
/// Lives in `core/utils/` because both layers need the same number and they
/// cannot import each other: the viewmodels refuse an over-long name before
/// writing, and `ExerciseRepository` — in `lib/data/`, which never imports
/// `lib/features/` — refuses it at the column. Two spellings of twenty would
/// drift, and the drift would be invisible until a row failed to upload.
///
/// The database states the rule independently (`dim_exercise_name_length_check`
/// and `dim_variation_name_length_check`), so this constant is the client's
/// spelling of an invariant that is already true on disk. `name_limit_test.dart`
/// pins the number precisely so the two cannot disagree.
library;

/// How many characters a name may hold — spaces included.
///
/// Twenty is a measurement, not a round number. The narrowest surface that
/// draws a name is the exercise selector's field, which sits between two 32px
/// arrows inside a padded card and, at phone width, holds about twenty
/// characters at `AppTextStyles.sm` before it has to ellipsize. A name longer
/// than the field is a name no screen can show whole, and the picker is where
/// the user chooses it.
const kMaxExerciseNameLength = 20;

/// Whether [name] breaks the rule the two database checks enforce.
///
/// Measured on the **trimmed** value, because that is the value that gets
/// stored: every write path stores `name.trim()`, so counting untrimmed
/// characters would let trailing spaces trip a limit the user's own field said
/// they were inside of.
///
/// Emptiness is deliberately not this function's business — an empty name is
/// already refused by the callers' existing `isEmpty` guards, and folding the
/// two rules together would make a blank name "too long" in an error message.
bool nameTooLong(String name) => name.trim().length > kMaxExerciseNameLength;
