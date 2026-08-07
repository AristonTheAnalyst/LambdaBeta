-- Volume type ('reps' vs 'duration') is now chosen per set instead of being
-- fixed per exercise, so this column is no longer read or written anywhere
-- in the app (see CustomExercise/ExerciseRepository).
--
-- Guarded with a table-existence check: the migration history was hand-applied
-- to an already-evolved schema, so this runs against databases where
-- `user_custom_exercise` is created *after* this migration (fresh replay) as
-- well as ones where it already existed. `if exists` is not enough — ALTER on a
-- missing table still errors, hence the DO block.
do $$
begin
  if exists (select 1 from pg_tables where schemaname = 'public' and tablename = 'user_custom_exercise') then
    alter table public.user_custom_exercise
      drop column if exists exercise_volume_type;
  end if;
end $$;
