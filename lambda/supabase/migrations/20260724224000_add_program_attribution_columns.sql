-- Durable attribution: stamped at write time (not derived later) so a
-- logged workout/set's link back to the program/run/planned-workout/
-- planned-set it fulfilled survives future program switches intact.
-- All nullable/additive — existing rows and call sites are unaffected.

alter table public.fact_user_workout
  add column if not exists program_id text references public.user_program (program_id) on delete set null,
  add column if not exists program_run_id text references public.user_program_run (program_run_id) on delete set null,
  add column if not exists planned_workout_id text references public.program_planned_workout (planned_workout_id) on delete set null,
  add column if not exists user_workout_feeling smallint check (user_workout_feeling between 1 and 5);

alter table public.fact_workout_set
  add column if not exists program_id text references public.user_program (program_id) on delete set null,
  add column if not exists planned_set_id text references public.program_planned_set (planned_set_id) on delete set null;
