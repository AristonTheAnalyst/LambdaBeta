-- The seven exercise names that are longer than the field that draws them.
--
-- Twenty characters is a measurement, not a round number: the narrowest surface
-- that shows a name is the exercise selector's field, sitting between two 32px
-- arrows inside a padded card, and at phone width it holds about twenty
-- characters before it has to ellipsize. Every one of these seven overflowed it.
--
-- This runs *before* the constraints in the next migration, and it renames the
-- archived row too (`Trap Bar Deadlift Jump`) — the check is unconditional, so a
-- "rename the actives" pass would leave a migration that fails on its own
-- constraint. The rule is enforced at the write point from 2026-09-29, so this
-- is a one-time backfill, not a normalisation the app repeats.
--
-- Names resolve live through the FKs with no snapshots (since 2026-08-26), so
-- these renames propagate to every past session automatically. All seven
-- targets were verified free and mutually distinct against the live library;
-- note that `Trap Bar Jump` already exists, so the obvious shortening of the
-- archived row would have silently shadowed it through
-- `findExerciseByName(...).first` — there is no unique index on
-- `(user_id, lower(name))` to catch that.
--
-- Data-only: no schema change, so no PowerSync stream change and no dashboard
-- step.

update public.dim_exercise set exercise_name = 'Elevated Glute Br.'
  where exercise_name = 'Elevated Unilateral Glute Bridge';
update public.dim_exercise set exercise_name = 'Seated Good Morning'
  where exercise_name = 'Seated Good Morning Stretch';
update public.dim_exercise set exercise_name = 'Split Squat Stretch'
  where exercise_name = 'Split Squat Ankle Stretch';
update public.dim_exercise set exercise_name = 'Single Leg Glute Br.'
  where exercise_name = 'Single Leg Glute Bridge';
update public.dim_exercise set exercise_name = 'Side Jefferson Str.'
  where exercise_name = 'Side Jefferson Stretch';
update public.dim_exercise set exercise_name = 'Trap Bar DL Jump'
  where exercise_name = 'Trap Bar Deadlift Jump';
update public.dim_exercise set exercise_name = 'Single Leg Hip Thr.'
  where exercise_name = 'Single Leg Hip Thrust';
