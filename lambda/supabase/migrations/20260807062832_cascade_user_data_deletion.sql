-- =============================================================================
-- Cascade user-data deletion.
--
-- Two bugs drove this:
--   1. Account deletion (`auth.admin.deleteUser`) aborts for any user with
--      data: `dim_user.user_id -> auth.users` is ON DELETE CASCADE, but every
--      other table FKs to `dim_user` with NO ACTION, so deleting the dim_user
--      row violates those FKs. Converting them to CASCADE lets one admin call
--      cascade through the whole graph.
--   2. Deleting a program fails server-side (FK 23503) because
--      `fact_program_run.program_id -> dim_program` is NO ACTION and the
--      client never deletes runs — the program "resurrects" after the next
--      sync.
--
-- Five FKs intentionally stay ON DELETE SET NULL so a deleted program (or
-- run/planned workout) does NOT destroy the user's completed workout history:
--   fact_workout.program_id / program_run_id / planned_workout_id
--   fact_workout_set.program_id / planned_set_id
-- Every other FK becomes CASCADE.
--
-- Idempotent (drop-if-exists + add-if-not-exists) so it can be re-run.
-- =============================================================================

-- ── dim_user -> auth.users (keep CASCADE, it's correct) ──────────────────────
-- (no change)

-- ── All FKs referencing dim_user → CASCADE (enables account deletion) ────────
alter table public.coaching_relationship drop constraint if exists coaching_relationship_coach_user_id_fkey;
alter table public.coaching_relationship add constraint coaching_relationship_coach_user_id_fkey foreign key (coach_user_id) references public.dim_user(user_id) on delete cascade;
alter table public.coaching_relationship drop constraint if exists coaching_relationship_athlete_user_id_fkey;
alter table public.coaching_relationship add constraint coaching_relationship_athlete_user_id_fkey foreign key (athlete_user_id) references public.dim_user(user_id) on delete cascade;

alter table public.dim_exercise drop constraint if exists user_custom_exercise_user_id_fkey;
alter table public.dim_exercise add constraint user_custom_exercise_user_id_fkey foreign key (user_id) references public.dim_user(user_id) on delete cascade;

alter table public.dim_exercise_variation_bridge drop constraint if exists user_custom_exercise_variation_bridge_user_id_fkey;
alter table public.dim_exercise_variation_bridge add constraint user_custom_exercise_variation_bridge_user_id_fkey foreign key (user_id) references public.dim_user(user_id) on delete cascade;

alter table public.dim_variation drop constraint if exists user_custom_variation_user_id_fkey;
alter table public.dim_variation add constraint user_custom_variation_user_id_fkey foreign key (user_id) references public.dim_user(user_id) on delete cascade;

alter table public.dim_program drop constraint if exists user_program_user_id_fkey;
alter table public.dim_program add constraint user_program_user_id_fkey foreign key (user_id) references public.dim_user(user_id) on delete cascade;

alter table public.dim_planned_workout drop constraint if exists program_planned_workout_user_id_fkey;
alter table public.dim_planned_workout add constraint program_planned_workout_user_id_fkey foreign key (user_id) references public.dim_user(user_id) on delete cascade;

alter table public.dim_planned_set drop constraint if exists program_planned_set_user_id_fkey;
alter table public.dim_planned_set add constraint program_planned_set_user_id_fkey foreign key (user_id) references public.dim_user(user_id) on delete cascade;

alter table public.dim_workout drop constraint if exists dim_workout_user_id_fkey;
alter table public.dim_workout add constraint dim_workout_user_id_fkey foreign key (user_id) references public.dim_user(user_id) on delete cascade;

alter table public.dim_workout_set drop constraint if exists dim_workout_set_user_id_fkey;
alter table public.dim_workout_set add constraint dim_workout_set_user_id_fkey foreign key (user_id) references public.dim_user(user_id) on delete cascade;

alter table public.fact_workout drop constraint if exists fact_user_workout_user_id_fkey;
alter table public.fact_workout add constraint fact_user_workout_user_id_fkey foreign key (user_id) references public.dim_user(user_id) on delete cascade;

alter table public.fact_workout_set drop constraint if exists fact_workout_set_user_id_fkey;
alter table public.fact_workout_set add constraint fact_workout_set_user_id_fkey foreign key (user_id) references public.dim_user(user_id) on delete cascade;

alter table public.fact_pr drop constraint if exists fact_pr_user_id_fkey;
alter table public.fact_pr add constraint fact_pr_user_id_fkey foreign key (user_id) references public.dim_user(user_id) on delete cascade;

alter table public.fact_lesson drop constraint if exists fact_lesson_user_id_fkey;
alter table public.fact_lesson add constraint fact_lesson_user_id_fkey foreign key (user_id) references public.dim_user(user_id) on delete cascade;

alter table public.fact_rest drop constraint if exists fact_rest_user_id_fkey;
alter table public.fact_rest add constraint fact_rest_user_id_fkey foreign key (user_id) references public.dim_user(user_id) on delete cascade;

alter table public.fact_program_run drop constraint if exists user_program_run_user_id_fkey;
alter table public.fact_program_run add constraint user_program_run_user_id_fkey foreign key (user_id) references public.dim_user(user_id) on delete cascade;

alter table public.fact_program_goal drop constraint if exists dim_program_goal_user_id_fkey;
alter table public.fact_program_goal add constraint dim_program_goal_user_id_fkey foreign key (user_id) references public.dim_user(user_id) on delete cascade;

-- fact_bodyweight.user_id already ON DELETE CASCADE — no change.

-- ── Intra-graph: program deletion cascade ─────────────────────────────────────
alter table public.dim_planned_workout drop constraint if exists program_planned_workout_program_id_fkey;
alter table public.dim_planned_workout add constraint program_planned_workout_program_id_fkey foreign key (program_id) references public.dim_program(program_id) on delete cascade;

alter table public.dim_planned_set drop constraint if exists program_planned_set_planned_workout_id_fkey;
alter table public.dim_planned_set add constraint program_planned_set_planned_workout_id_fkey foreign key (planned_workout_id) references public.dim_planned_workout(planned_workout_id) on delete cascade;

alter table public.fact_program_run drop constraint if exists user_program_run_program_id_fkey;
alter table public.fact_program_run add constraint user_program_run_program_id_fkey foreign key (program_id) references public.dim_program(program_id) on delete cascade;

alter table public.fact_program_goal drop constraint if exists fact_program_goal_run_fkey;
alter table public.fact_program_goal add constraint fact_program_goal_run_fkey foreign key (program_run_id) references public.fact_program_run(program_run_id) on delete cascade;

-- ── Intra-graph: exercise/variation deletion cascade ─────────────────────────
alter table public.dim_exercise_variation_bridge drop constraint if exists user_custom_exercise_variation_bridge_custom_exercise_id_fkey;
alter table public.dim_exercise_variation_bridge add constraint user_custom_exercise_variation_bridge_custom_exercise_id_fkey foreign key (custom_exercise_id) references public.dim_exercise(custom_exercise_id) on delete cascade;
alter table public.dim_exercise_variation_bridge drop constraint if exists user_custom_exercise_variation_bridge_custom_variation_id_fkey;
alter table public.dim_exercise_variation_bridge add constraint user_custom_exercise_variation_bridge_custom_variation_id_fkey foreign key (custom_variation_id) references public.dim_variation(custom_variation_id) on delete cascade;

alter table public.dim_planned_set drop constraint if exists program_planned_set_custom_exercise_id_fkey;
alter table public.dim_planned_set add constraint program_planned_set_custom_exercise_id_fkey foreign key (custom_exercise_id) references public.dim_exercise(custom_exercise_id) on delete cascade;
alter table public.dim_planned_set drop constraint if exists program_planned_set_custom_variation_id_fkey;
alter table public.dim_planned_set add constraint program_planned_set_custom_variation_id_fkey foreign key (custom_variation_id) references public.dim_variation(custom_variation_id) on delete cascade;

alter table public.fact_workout_set drop constraint if exists fact_workout_set_custom_exercise_id_fkey;
alter table public.fact_workout_set add constraint fact_workout_set_custom_exercise_id_fkey foreign key (custom_exercise_id) references public.dim_exercise(custom_exercise_id) on delete cascade;
alter table public.fact_workout_set drop constraint if exists fact_workout_set_custom_variation_id_fkey;
alter table public.fact_workout_set add constraint fact_workout_set_custom_variation_id_fkey foreign key (custom_variation_id) references public.dim_variation(custom_variation_id) on delete cascade;

alter table public.fact_lesson drop constraint if exists fact_lesson_custom_exercise_id_fkey;
alter table public.fact_lesson add constraint fact_lesson_custom_exercise_id_fkey foreign key (custom_exercise_id) references public.dim_exercise(custom_exercise_id) on delete cascade;

alter table public.fact_pr drop constraint if exists fact_pr_custom_exercise_id_fkey;
alter table public.fact_pr add constraint fact_pr_custom_exercise_id_fkey foreign key (custom_exercise_id) references public.dim_exercise(custom_exercise_id) on delete cascade;
alter table public.fact_pr drop constraint if exists fact_pr_custom_variation_id_fkey;
alter table public.fact_pr add constraint fact_pr_custom_variation_id_fkey foreign key (custom_variation_id) references public.dim_variation(custom_variation_id) on delete cascade;

alter table public.fact_rest drop constraint if exists fact_rest_custom_exercise_id_fkey;
alter table public.fact_rest add constraint fact_rest_custom_exercise_id_fkey foreign key (custom_exercise_id) references public.dim_exercise(custom_exercise_id) on delete cascade;

-- ── Intra-graph: workout deletion cascade (sets + rest) ──────────────────────
alter table public.fact_workout_set drop constraint if exists fact_workout_set_user_workout_id_fkey;
alter table public.fact_workout_set add constraint fact_workout_set_user_workout_id_fkey foreign key (user_workout_id) references public.fact_workout(user_workout_id) on delete cascade;

alter table public.fact_rest drop constraint if exists fact_rest_user_workout_id_fkey;
alter table public.fact_rest add constraint fact_rest_user_workout_id_fkey foreign key (user_workout_id) references public.fact_workout(user_workout_id) on delete cascade;

alter table public.dim_workout_set drop constraint if exists dim_workout_set_workout_id_fkey;
alter table public.dim_workout_set add constraint dim_workout_set_workout_id_fkey foreign key (workout_id) references public.dim_workout(workout_id) on delete cascade;

-- ── History-preserving FKs that intentionally stay SET NULL (no change) ──────
--   fact_workout.program_id           → dim_program
--   fact_workout.program_run_id       → fact_program_run
--   fact_workout.planned_workout_id   → dim_planned_workout
--   fact_workout_set.program_id       → dim_program
--   fact_workout_set.planned_set_id   → dim_planned_set
