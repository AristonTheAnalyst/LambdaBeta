-- Volume type ('reps' vs 'duration') is now chosen per set instead of being
-- fixed per exercise, so this column is no longer read or written anywhere
-- in the app (see CustomExercise/ExerciseRepository).
alter table public.user_custom_exercise
  drop column if exists exercise_volume_type;
