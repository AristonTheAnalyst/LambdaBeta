-- A name has to fit the field that draws it.
--
-- The client states this rule in `lib/core/utils/name_limit.dart`
-- (`kMaxExerciseNameLength`), and `name_limit_test.dart` pins the constant to
-- the same twenty so the two cannot drift. This is the same invariant spelled
-- where it cannot be talked out of: the column.
--
-- The app **refuses** an over-long name rather than shortening it — the
-- viewmodels return null beside their existing `isEmpty` guard, and
-- `ExerciseRepository` throws `ArgumentError.value` — so a violation here is
-- unreachable from the app. That matters more than usual on the client: the
-- PowerSync mirror is a plain `Column.text` with no CHECK support, so a 25
-- character name would insert locally, render in the picker, survive a restart,
-- and then silently fail to upload (quarantined 23514 in `upload_failures`),
-- leaving the device and the server disagreeing with nothing shown to the user.
--
-- Constraints only, on columns that already exist: no new table, so no PowerSync
-- stream change and no dashboard step. `char_length` rather than `length` so the
-- count is characters and not bytes — the name limit is about how much of the
-- field a name fills.
--
-- Depends on 20260929000000: the seven over-long names must be renamed first,
-- or this fails on the rows it is meant to protect.

alter table public.dim_exercise
  add constraint dim_exercise_name_length_check
  check (char_length(exercise_name) <= 20);

alter table public.dim_variation
  add constraint dim_variation_name_length_check
  check (char_length(variation_name) <= 20);
